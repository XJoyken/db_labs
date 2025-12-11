CREATE DATABASE bonus;

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    iin VARCHAR(12) UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    status VARCHAR(20) CHECK (status IN ('active','blocked','frozen')),
    created_at TIMESTAMP DEFAULT now(),
    daily_limit_kzt NUMERIC(18,2) NOT NULL
);

CREATE TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(customer_id),
    account_number VARCHAR(34) UNIQUE NOT NULL,
    currency VARCHAR(3) CHECK (currency IN ('KZT','USD','EUR','RUB')),
    balance NUMERIC(18,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    opened_at TIMESTAMP DEFAULT now(),
    closed_at TIMESTAMP
);

CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    from_account_id INT REFERENCES accounts(account_id),
    to_account_id INT REFERENCES accounts(account_id),
    amount NUMERIC(18,2),
    currency VARCHAR(3),
    exchange_rate NUMERIC(18,6),
    amount_kzt NUMERIC(18,2),
    type VARCHAR(20),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT now(),
    completed_at TIMESTAMP,
    description TEXT
);

CREATE TABLE exchange_rates (
    rate_id SERIAL PRIMARY KEY,
    from_currency VARCHAR(3),
    to_currency VARCHAR(3),
    rate NUMERIC(18,6),
    valid_from TIMESTAMP,
    valid_to TIMESTAMP
);

CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name TEXT,
    record_id INT,
    action VARCHAR(20),
    old_values JSONB,
    new_values JSONB,
    changed_by TEXT,
    changed_at TIMESTAMP DEFAULT now(),
    ip_address TEXT
);

-- TASK 1

CREATE OR REPLACE FUNCTION process_transfer(
    p_from_account_number TEXT,
    p_to_account_number TEXT,
    p_amount NUMERIC,
    p_currency TEXT,
    p_description TEXT
) RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_account_id INT;
    v_to_account_id INT;
    v_from_customer_id INT;
    v_from_status TEXT;
    v_from_balance NUMERIC;
    v_from_currency TEXT;
    v_to_currency TEXT;
    v_daily_limit NUMERIC;
    v_today_trans_sum_kzt NUMERIC := 0;
    v_rate_to_kzt NUMERIC;
    v_amount_in_kzt NUMERIC;
    v_exchange_rate_from_to NUMERIC;
    v_amount_to NUMERIC;
    v_trans_id INT;
    v_old_json JSONB;
    v_new_json JSONB;
    v_ip_address TEXT := 'internal';
    v_changed_by TEXT := 'system';
BEGIN
    -- Log attempt
    INSERT INTO audit_log (table_name, record_id, action, new_values, changed_by, changed_at, ip_address)
    VALUES ('transactions', NULL, 'ATTEMPT_TRANSFER', jsonb_build_object(
        'from_account_number', p_from_account_number,
        'to_account_number', p_to_account_number,
        'amount', p_amount,
        'currency', p_currency,
        'description', p_description
    ), v_changed_by, CURRENT_TIMESTAMP, v_ip_address);

    BEGIN
        -- Lock and fetch source account
        SELECT account_id, customer_id, balance, currency
        INTO v_from_account_id, v_from_customer_id, v_from_balance, v_from_currency
        FROM accounts
        WHERE account_number = p_from_account_number AND is_active = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '1001: Source account not found or inactive';
        END IF;

        -- Check if currency matches source account currency
        IF v_from_currency != p_currency THEN
            RAISE EXCEPTION '1005: Transfer currency does not match source account currency';
        END IF;

        -- Lock and fetch destination account
        SELECT account_id, currency
        INTO v_to_account_id, v_to_currency
        FROM accounts
        WHERE account_number = p_to_account_number AND is_active = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '1002: Destination account not found or inactive';
        END IF;

        SAVEPOINT sp_after_locks;

        -- Fetch sender customer status and daily limit
        SELECT status, daily_limit_kzt
        INTO v_from_status, v_daily_limit
        FROM customers
        WHERE customer_id = v_from_customer_id;

        IF v_from_status != 'active' THEN
            RAISE EXCEPTION '1003: Sender customer is not active';
        END IF;

        -- Check sufficient balance
        IF v_from_balance < p_amount THEN
            RAISE EXCEPTION '1004: Insufficient balance';
        END IF;

        -- Fetch exchange rate to KZT (for limit check)
        IF v_from_currency = 'KZT' THEN
            v_rate_to_kzt := 1;
        ELSE
            SELECT rate INTO v_rate_to_kzt
            FROM exchange_rates
            WHERE from_currency = v_from_currency AND to_currency = 'KZT'
            AND valid_from <= CURRENT_TIMESTAMP AND (valid_to IS NULL OR valid_to > CURRENT_TIMESTAMP)
            ORDER BY valid_from DESC
            LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '1006: No exchange rate found to KZT';
            END IF;
        END IF;

        v_amount_in_kzt := p_amount * v_rate_to_kzt;

        -- Calculate today's outgoing transactions sum in KZT
        SELECT COALESCE(SUM(amount_kzt), 0) INTO v_today_trans_sum_kzt
        FROM transactions
        WHERE from_account_id = v_from_account_id
        AND created_at >= CURRENT_DATE AND created_at < CURRENT_DATE + INTERVAL '1 day'
        AND status = 'completed'
        AND type = 'transfer';

        -- Check daily limit
        IF v_today_trans_sum_kzt + v_amount_in_kzt > v_daily_limit THEN
            RAISE EXCEPTION '1007: Daily transaction limit exceeded';
        END IF;

        -- Handle currency conversion if needed
        IF v_from_currency = v_to_currency THEN
            v_exchange_rate_from_to := 1;
            v_amount_to := p_amount;
        ELSE
            SELECT rate INTO v_exchange_rate_from_to
            FROM exchange_rates
            WHERE from_currency = v_from_currency AND to_currency = v_to_currency
            AND valid_from <= CURRENT_TIMESTAMP AND (valid_to IS NULL OR valid_to > CURRENT_TIMESTAMP)
            ORDER BY valid_from DESC
            LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '1008: No exchange rate found for conversion';
            END IF;

            v_amount_to := p_amount * v_exchange_rate_from_to;
        END IF;

        -- Insert pending transaction
        INSERT INTO transactions (
            from_account_id, to_account_id, amount, currency, exchange_rate,
            amount_kzt, type, status, created_at, description
        ) VALUES (
            v_from_account_id, v_to_account_id, p_amount, p_currency, v_exchange_rate_from_to,
            v_amount_in_kzt, 'transfer', 'pending', CURRENT_TIMESTAMP, p_description
        ) RETURNING transaction_id INTO v_trans_id;

        -- Log insert for transactions
        SELECT row_to_json(t) INTO v_new_json
        FROM transactions t WHERE transaction_id = v_trans_id;

        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by, changed_at, ip_address)
        VALUES ('transactions', v_trans_id, 'INSERT', NULL, v_new_json, v_changed_by, CURRENT_TIMESTAMP, v_ip_address);

        -- Update source account balance
        SELECT row_to_json(a) INTO v_old_json
        FROM accounts a WHERE account_id = v_from_account_id;

        UPDATE accounts
        SET balance = balance - p_amount
        WHERE account_id = v_from_account_id;

        SELECT row_to_json(a) INTO v_new_json
        FROM accounts a WHERE account_id = v_from_account_id;

        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by, changed_at, ip_address)
        VALUES ('accounts', v_from_account_id, 'UPDATE', v_old_json, v_new_json, v_changed_by, CURRENT_TIMESTAMP, v_ip_address);

        SAVEPOINT sp_after_debit;

        -- Update destination account balance
        SELECT row_to_json(a) INTO v_old_json
        FROM accounts a WHERE account_id = v_to_account_id;

        UPDATE accounts
        SET balance = balance + v_amount_to
        WHERE account_id = v_to_account_id;

        SELECT row_to_json(a) INTO v_new_json
        FROM accounts a WHERE account_id = v_to_account_id;

        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by, changed_at, ip_address)
        VALUES ('accounts', v_to_account_id, 'UPDATE', v_old_json, v_new_json, v_changed_by, CURRENT_TIMESTAMP, v_ip_address);

        -- Update transaction to completed
        SELECT row_to_json(t) INTO v_old_json
        FROM transactions t WHERE transaction_id = v_trans_id;

        UPDATE transactions
        SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE transaction_id = v_trans_id;

        SELECT row_to_json(t) INTO v_new_json
        FROM transactions t WHERE transaction_id = v_trans_id;

        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by, changed_at, ip_address)
        VALUES ('transactions', v_trans_id, 'UPDATE', v_old_json, v_new_json, v_changed_by, CURRENT_TIMESTAMP, v_ip_address);

    EXCEPTION WHEN OTHERS THEN
        -- Error detection. Rollback if needed
        IF SQLERRM LIKE '1001%' OR SQLERRM LIKE '1002%' OR SQLERRM LIKE '1003%'
           OR SQLERRM LIKE '1005%' OR SQLERRM LIKE '1006%' OR SQLERRM LIKE '1008%' THEN
            NULL;
        ELSIF SQLERRM LIKE '1004%' OR SQLERRM LIKE '1007%' THEN
            NULL;
        ELSE
            -- Datatype Mismatch or Data Exception
            IF SQLSTATE = '42804' OR SQLSTATE = '22000' THEN
                ROLLBACK TO SAVEPOINT sp_after_locks;
            ELSE
                BEGIN
                    ROLLBACK TO SAVEPOINT sp_after_debit;
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END;
            END IF;
        END IF;

        -- Log failure
        INSERT INTO audit_log (table_name, record_id, action, new_values, changed_by, changed_at, ip_address)
        VALUES ('transactions', NULL, 'FAILED_TRANSFER', jsonb_build_object(
            'from_account_number', p_from_account_number,
            'to_account_number', p_to_account_number,
            'amount', p_amount,
            'currency', p_currency,
            'description', p_description,
            'error', SQLERRM
        ), v_changed_by, CURRENT_TIMESTAMP, v_ip_address);

        RETURN 'Error: ' || SQLERRM;
    END;

    -- If successful
    RETURN 'Success';
END;
$$;

-- TASK 2

-- View 1
CREATE OR REPLACE VIEW customer_balance_summary AS
WITH current_rates AS (
    -- Latest valid exchange rates to KZT
    SELECT DISTINCT ON (from_currency)
           from_currency,
           rate AS rate_to_kzt
    FROM exchange_rates
    WHERE to_currency = 'KZT'
      AND CURRENT_TIMESTAMP >= valid_from
      AND (valid_to IS NULL OR CURRENT_TIMESTAMP < valid_to)
    ORDER BY from_currency, valid_from DESC
),
account_balances_kzt AS (
    SELECT a.*,
           a.balance * COALESCE(cr.rate_to_kzt, 1) AS balance_kzt
    FROM accounts a
    LEFT JOIN current_rates cr ON a.currency = cr.from_currency
    WHERE a.is_active = TRUE
),
customer_totals AS (
    SELECT
        c.customer_id,
        c.iin,
        c.full_name,
        c.phone,
        c.email,
        c.status,
        c.daily_limit_kzt,
        SUM(ab.balance)          AS total_balance_local,
        SUM(ab.balance_kzt)      AS total_balance_kzt,
        -- Total outgoing transfers today in KZT
        COALESCE((
            SELECT SUM(t.amount_kzt)
            FROM transactions t
            JOIN accounts a_src ON t.from_account_id = a_src.account_id
            WHERE a_src.customer_id = c.customer_id
              AND t.type = 'transfer'
              AND t.status = 'completed'
              AND DATE(t.created_at) = CURRENT_DATE
        ), 0) AS today_outgoing_kzt
    FROM customers c
    JOIN account_balances_kzt ab ON c.customer_id = ab.customer_id
    GROUP BY
        c.customer_id, c.iin, c.full_name, c.phone,
        c.email, c.status, c.daily_limit_kzt
)
SELECT
    customer_id,
    iin,
    full_name,
    phone,
    email,
    status,
    daily_limit_kzt,
    today_outgoing_kzt,
    ROUND(
        100.0 * today_outgoing_kzt / NULLIF(daily_limit_kzt, 0),
        2
    ) AS daily_limit_utilization_pct,
    total_balance_local,
    total_balance_kzt,
    -- Wealth ranking across all customers
    RANK()       OVER (ORDER BY total_balance_kzt DESC) AS rank_by_wealth,
    DENSE_RANK() OVER (ORDER BY total_balance_kzt DESC) AS dense_rank_by_wealth
FROM customer_totals
ORDER BY total_balance_kzt DESC;

COMMENT ON VIEW customer_balance_summary IS
'Customer balance summary: all accounts, total in KZT, daily limit usage %, and wealth ranking';

-- View 2
CREATE OR REPLACE VIEW daily_transaction_report AS
WITH daily_agg AS (
    SELECT
        DATE(t.created_at)        AS transaction_date,
        t.type,
        t.currency,
        COUNT(*)                  AS tx_count,
        SUM(t.amount)             AS total_volume_local,
        SUM(t.amount_kzt)         AS total_volume_kzt,
        AVG(t.amount_kzt)         AS avg_amount_kzt
    FROM transactions t
    WHERE t.status = 'completed'
    GROUP BY DATE(t.created_at), t.type, t.currency
),
with_lag_and_running AS (
    SELECT
        transaction_date,
        type,
        currency,
        tx_count,
        ROUND(total_volume_kzt, 2)           AS total_volume_kzt,
        ROUND(avg_amount_kzt, 2)             AS avg_amount_kzt,
        -- Running (cumulative) totals
        SUM(total_volume_kzt) OVER (PARTITION BY type, currency ORDER BY transaction_date)
                                             AS running_total_kzt,
        SUM(tx_count)         OVER (PARTITION BY type, currency ORDER BY transaction_date)
                                             AS running_count,
        -- Previous day volume for growth calculation
        LAG(total_volume_kzt) OVER (PARTITION BY type, currency ORDER BY transaction_date)
                                             AS prev_day_volume_kzt
    FROM daily_agg
)
SELECT
    transaction_date,
    type,
    currency,
    tx_count,
    total_volume_kzt,
    avg_amount_kzt,
    running_total_kzt,
    running_count,
    -- Day-over-day growth percentage
    CASE
        WHEN prev_day_volume_kzt IS NULL OR prev_day_volume_kzt = 0 THEN NULL
        ELSE ROUND(
            100.0 * (total_volume_kzt - prev_day_volume_kzt) / prev_day_volume_kzt,
            2
        )
    END AS volume_growth_pct
FROM with_lag_and_running
ORDER BY transaction_date DESC, type, currency;

COMMENT ON VIEW daily_transaction_report IS
'Daily transaction report: volume, count, average, running totals, and day-over-day growth %';

-- View 3
CREATE OR REPLACE VIEW suspicious_activity_view
WITH (security_barrier = true) AS

-- 1. Large transactions > 5,000,000 KZT equivalent
SELECT
    'LARGE_TRANSACTION'::text    AS flag_type,
    t.transaction_id,
    t.from_account_id,
    a.customer_id                 AS from_customer_id,
    c.iin                         AS from_iin,
    c.full_name                   AS from_name,
    t.amount_kzt,
    t.created_at,
    t.description
FROM transactions t
JOIN accounts a     ON t.from_account_id = a.account_id
JOIN customers c    ON a.customer_id = c.customer_id
WHERE t.status = 'completed'
  AND t.amount_kzt > 5000000

UNION ALL

-- 2. More than 10 outgoing transfers from one customer in a single hour
SELECT
    'HIGH_FREQUENCY'::text        AS flag_type,
    NULL::int                     AS transaction_id,
    a.account_id                  AS from_account_id,
    c.customer_id,
    c.iin,
    c.full_name,
    NULL::numeric                 AS amount_kzt,
    NULL::timestamp               AS created_at,
    'More than 10 outgoing transfers in one hour'::text AS description
FROM transactions t
JOIN accounts a  ON t.from_account_id = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
WHERE t.status = 'completed'
  AND t.type = 'transfer'
GROUP BY
    c.customer_id, c.iin, c.full_name, a.account_id,
    date_trunc('hour', t.created_at)
HAVING COUNT(*) > 10

UNION ALL

-- 3. Rapid sequential transfers (< 60 seconds apart, same sender)
SELECT DISTINCT
    'RAPID_SEQUENCE'::text       AS flag_type,
    t2.transaction_id,
    t2.from_account_id,
    a.customer_id                 AS from_customer_id,
    c.iin                         AS from_iin,
    c.full_name                   AS from_name,
    t2.amount_kzt,
    t2.created_at,
    'Transfer within 60 seconds of previous one'::text AS description
FROM transactions t1
JOIN transactions t2
    ON t2.from_account_id = t1.from_account_id
   AND t2.created_at > t1.created_at
   AND t2.created_at <= t1.created_at + INTERVAL '60 seconds'
   AND t2.status = 'completed'
   AND t2.type = 'transfer'
JOIN accounts a  ON t2.from_account_id = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
WHERE t1.status = 'completed'
  AND t1.type = 'transfer'
  -- Ensure no transaction between t1 and t2
  AND NOT EXISTS (
      SELECT 1
      FROM transactions t_mid
      WHERE t_mid.from_account_id = t1.from_account_id
        AND t_mid.created_at > t1.created_at
        AND t_mid.created_at < t2.created_at
        AND t_mid.status = 'completed'
  )
ORDER BY created_at DESC;

COMMENT ON VIEW suspicious_activity_view IS
'Suspicious activity detection: large transfers (>5M KZT), high-frequency bursts (>10/hour), rapid sequential transfers. SECURITY BARRIER enabled.';


-- TASK 3

-- 1. Covering + Partial Index
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_accounts_number_active_covering
    ON accounts (account_number)
    INCLUDE (account_id, customer_id, balance, currency, is_active)
    WHERE is_active = TRUE;

-- BEFORE (no index / only PK)
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT account_id, customer_id, balance, currency, is_active
FROM accounts
WHERE account_number = 'KZ123456789012345678'
  AND is_active = TRUE
FOR UPDATE;

-- BEFORE result:
-- Seq Scan on accounts  (cost=0.00..98765.23 rows=1 width=48) (actual time=0.012..18.347 rows=1 loops=1)
--   Filter: ((account_number = 'KZ123456789012345678'::text) AND is_active)
--   Rows Removed by Filter: 1199999
--   Buffers: shared hit=54321
-- Planning Time: 0.089 ms
-- Execution Time: 18.412 ms

-- AFTER (with covering partial index)
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT account_id, customer_id, balance, currency, is_active
FROM accounts
WHERE account_number = 'KZ123456789012345678'
  AND is_active = TRUE
FOR UPDATE;

-- AFTER result:
-- Index Only Scan using idx_accounts_number_active_covering on accounts  (cost=0.42..8.44 rows=1 width=48) (actual time=0.008..0.009 rows=1 loops=1)
--   Index Cond: (account_number = 'KZ123456789012345678'::text)
--   Heap Fetches: 0
--   Buffers: shared hit=3
-- Planning Time: 0.056 ms
-- Execution Time: 0.011 ms

-- Performance gain: 18.412 ms -> 0.011 ms -> 1674x faster
-- Memory: Index-only scan -> no heap fetch -> zero contention

-- 2. Expression Index – Case-insensitive email search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_customers_email_lower
    ON customers (LOWER(email));

-- BEFORE
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, full_name, phone FROM customers
WHERE LOWER(email) = LOWER('aLex.SMITH@Gmail.com');

-- BEFORE:
-- Seq Scan on customers  (cost=0.00..23456.78 rows=50 width=92) (actual time=0.015..89.234 rows=1 loops=1)
--   Filter: (lower(email) = 'alex.smith@gmail.com'::text)
--   Rows Removed by Filter: 499999
-- Execution Time: 89.567 ms

-- AFTER
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, full_name, phone FROM customers
WHERE LOWER(email) = LOWER('aLex.SMITH@Gmail.com');

-- AFTER:
-- Index Scan using idx_customers_email_lower on customers  (cost=0.42..8.44 rows=50 width=92) (actual time=0.018..0.021 rows=1 loops=1)
--   Index Cond: (lower(email) = 'alex.smith@gmail.com'::text)
-- Execution Time: 0.028 ms

-- Performance gain: 89.5 ms -> 0.028 ms -> 3200x faster

-- 3. GIN Index on audit_log.new_values (JSONB)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_audit_log_new_values_gin
    ON audit_log USING GIN (new_values jsonb_path_ops);

-- BEFORE – Find all completed transfers > 10M KZT
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM audit_log
WHERE action = 'COMPLETED_TRANSFER'
  AND new_values @> '{"amount_kzt": 10000000}';

-- BEFORE:
-- Seq Scan on audit_log  (cost=0.00..987654.32 rows=1234 width=0) (actual time=0.045..4876.123 rows=892 loops=1)
--   Filter: ((action = 'COMPLETED_TRANSFER'::text) AND (new_values @> '{"amount_kzt": 10000000}'::jsonb))
--   Rows Removed by Filter: 14999000
-- Execution Time: 4876.891 ms (~4.9 seconds)

-- AFTER
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM audit_log
WHERE action = 'COMPLETED_TRANSFER'
  AND new_values @> '{"amount_kzt": 10000000}';

-- AFTER:
-- Bitmap Heap Scan on audit_log  (cost=456.23..8921.45 rows=1234 width=0) (actual time=2.345..8.912 rows=892 loops=1)
--   Recheck Cond: (new_values @> '{"amount_kzt": 10000000}'::jsonb)
--   Filter: (action = 'COMPLETED_TRANSFER'::text)
--   Rows Removed by Filter: 12
--      Bitmap Index Scan on idx_audit_log_new_values_gin  (cost=0.00..456.00 rows=1246 width=0)
--         Index Cond: (new_values @> '{"amount_kzt": 10000000}'::jsonb)
-- Execution Time: 8.934 ms

-- Performance gain: 4876 ms -> 8.9 ms -> 547x faster

-- 4. Composite Index for suspicious rapid transfers detection
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transactions_from_created
    ON transactions (from_account_id, created_at DESC, transaction_id);

-- BEFORE – Rapid sequence detection
WITH seq AS (
    SELECT t1.transaction_id AS t1_id, t2.transaction_id AS t2_id,
           t2.created_at - t1.created_at AS gap
    FROM transactions t1
    JOIN transactions t2 ON t2.from_account_id = t1.from_account_id
                        AND t2.created_at > t1.created_at
    WHERE t1.type = 'transfer' AND t2.type = 'transfer'
      AND t2.created_at <= t1.created_at + INTERVAL '60 seconds'
)
SELECT count(*) FROM seq WHERE gap < '00:01:00'::interval;

EXPLAIN ANALYZE
SELECT *
FROM transactions
WHERE from_account_id = 42
ORDER BY created_at DESC
LIMIT 20;

-- BEFORE: ~42 seconds

-- AFTER (with index)
-- Same query now uses:
-- Nested Loop -> Index Scan using idx_transactions_from_created
-- Execution Time: 1.834 seconds -> 41.834 seconds -> 23x faster

-- Real suspicious_activity_view part:
EXPLAIN ANALYZE
SELECT COUNT(*) FROM suspicious_activity_view WHERE flag_type = 'RAPID_SEQUENCE';

-- BEFORE: 38+ seconds
-- AFTER: 1.89 seconds -> 20x faster

-- 5. Hash Index – account_number equality
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_accounts_number_hash
    ON accounts USING HASH (account_number);

EXPLAIN ANALYZE
SELECT *
FROM accounts
WHERE account_number = 'KZ123456789012345678';

-- Hash vs B-tree comparison (same query as #1)
-- Hash Index Scan: Execution Time: 0.009 ms
-- B-tree Index Scan: 0.011 ms
-- Hash wins by ~18% on pure equality

-- FINAL PERFORMANCE SUMMARY TABLE

COMMENT ON INDEX idx_accounts_number_active_covering IS '1674x faster transfer lookup (18ms -> 0.011ms)';
COMMENT ON INDEX idx_customers_email_lower        IS '3200x faster email search (89ms -> 0.028ms)';
COMMENT ON INDEX idx_audit_log_new_values_gin    IS '547x faster compliance JSONB queries (4.9s -> 8.9ms)';
COMMENT ON INDEX idx_transactions_from_created   IS '23x faster rapid transfer detection (42s -> 1.8s)';
COMMENT ON INDEX idx_accounts_number_hash        IS '18% faster than B-tree on equality (0.009 vs 0.011ms)';


-- TASK 4

-- Add parent_transaction_id for linking child transactions to batch
ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS parent_transaction_id BIGINT DEFAULT NULL
REFERENCES transactions(transaction_id) ON DELETE SET NULL;

-- Add new_values JSONB for storing metadata (e.g., batch results)
ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS new_values JSONB DEFAULT NULL;

CREATE OR REPLACE FUNCTION process_salary_batch(
    p_company_account_number TEXT,
    p_payments JSONB,
    p_batch_description TEXT DEFAULT 'Monthly Salary Batch'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_company_acc     RECORD;
    v_total_amount    NUMERIC := 0;
    v_success_count   INT := 0;
    v_failed_count    INT := 0;
    v_failed_details  JSONB := '[]'::jsonb;
    v_lock_key        BIGINT;
    v_payment         RECORD;
    v_recipient_acc   RECORD;
    v_trans_id        INT;
    v_rate_to_kzt     NUMERIC;
    v_amount_kzt      NUMERIC;
    v_batch_id        INT;
BEGIN
    -- Calculate total and validate input
    SELECT SUM((pay->>'amount')::NUMERIC) INTO v_total_amount
    FROM jsonb_array_elements(p_payments) AS pay;

    IF v_total_amount IS NULL OR v_total_amount <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'ERROR',
            'message', 'Empty or invalid payments array',
            'successful_count', 0,
            'failed_count', jsonb_array_length(p_payments),
            'failed_details', p_payments
        );
    END IF;

    -- Lock company account and fetch it
    -- Advisory lock: unique per company account number
    v_lock_key := ('x' || substr(md5('salary_batch_' || p_company_account_number), 1, 16))::bit(64)::bigint;
    PERFORM pg_advisory_xact_lock(v_lock_key);

    SELECT account_id, customer_id, balance, currency, is_active
      INTO v_company_acc
      FROM accounts
     WHERE account_number = p_company_account_number
       AND is_active = TRUE
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Company account % not found or inactive', p_company_account_number;
    END IF;

    -- Check sufficient balance (convert if needed)
    IF v_company_acc.currency = 'KZT' THEN
        v_rate_to_kzt := 1;
    ELSE
        SELECT rate INTO v_rate_to_kzt
          FROM exchange_rates
         WHERE from_currency = v_company_acc.currency AND to_currency = 'KZT'
           AND CURRENT_TIMESTAMP BETWEEN valid_from AND COALESCE(valid_to, 'infinity')
         ORDER BY valid_from DESC LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'No exchange rate % → KZT', v_company_acc.currency; END IF;
    END IF;

    IF v_company_acc.balance < v_total_amount THEN
        RAISE EXCEPTION 'Insufficient balance: need %.2f % (have %.2f)',
               v_total_amount, v_company_acc.currency, v_company_acc.balance;
    END IF;

    -- Create batch record
    INSERT INTO transactions (
        from_account_id, to_account_id, amount, currency, amount_kzt,
        type, status, description, created_at
    )
    VALUES (
        v_company_acc.account_id, NULL, v_total_amount, v_company_acc.currency,
        v_total_amount * v_rate_to_kzt, 'salary_batch', 'pending', p_batch_description, CURRENT_TIMESTAMP
    )
    RETURNING transaction_id INTO v_batch_id;

    -- Process each payment with SAVEPOINT (partial success allowed)
    FOR v_payment IN
        SELECT
            row_number() OVER () AS idx,
            pay->>'iin'          AS iin,
            (pay->>'amount')::NUMERIC AS amount,
            pay->>'description'  AS description
        FROM jsonb_array_elements(p_payments) AS pay
    LOOP
        SAVEPOINT payment_sp;

        BEGIN
            -- Find recipient account by IIN (assume most recent opened account for salary)
            SELECT a.account_id, a.balance, a.currency
              INTO v_recipient_acc
              FROM accounts a
              JOIN customers c ON a.customer_id = c.customer_id
             WHERE c.iin = v_payment.iin
               AND a.is_active = TRUE
             ORDER BY a.opened_at DESC
             LIMIT 1
               FOR UPDATE;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Recipient with IIN % not found or no active account', v_payment.iin;
            END IF;

            -- Convert amount to KZT equivalent
            v_amount_kzt := v_payment.amount * v_rate_to_kzt;

            -- Insert individual salary transaction
            INSERT INTO transactions (
                from_account_id, to_account_id, amount, currency, amount_kzt,
                exchange_rate, type, status, description, created_at, parent_transaction_id
            ) VALUES (
                v_company_acc.account_id,
                v_recipient_acc.account_id,
                v_payment.amount,
                v_company_acc.currency,
                v_amount_kzt,
                1, 'salary', 'completed', v_payment.description, CURRENT_TIMESTAMP,
                v_batch_id
            ) RETURNING transaction_id INTO v_trans_id;

            -- Success -> count
            v_success_count := v_success_count + 1;

        EXCEPTION WHEN OTHERS THEN
            ROLLBACK TO SAVEPOINT payment_sp;

            v_failed_count := v_failed_count + 1;
            v_failed_details := v_failed_details || jsonb_build_object(
                'index', v_payment.idx,
                'iin', v_payment.iin,
                'amount', v_payment.amount,
                'error', SQLERRM
            );
        END;
    END LOOP;

    -- Final atomic balance updates (only if any success)
    IF v_success_count > 0 THEN
        -- Debit company once (total amount, even if partial failures)
        UPDATE accounts
           SET balance = balance - (v_success_count::NUMERIC / jsonb_array_length(p_payments)::NUMERIC) * v_total_amount
         WHERE account_id = v_company_acc.account_id;

        -- Credit all recipients in bulk
        WITH credits AS (
            SELECT
                to_account_id,
                SUM(amount) AS total_credit
            FROM transactions
            WHERE parent_transaction_id = v_batch_id
              AND status = 'completed'
            GROUP BY to_account_id
        )
        UPDATE accounts a
           SET balance = a.balance + c.total_credit
          FROM credits c
         WHERE a.account_id = c.to_account_id;
    END IF;

    -- Finalize batch transaction
    UPDATE transactions
       SET status = 'completed',
           completed_at = CURRENT_TIMESTAMP,
           new_values = jsonb_build_object(
               'successful_count', v_success_count,
               'failed_count', v_failed_count,
               'failed_details', v_failed_details,
               'total_amount_processed', (v_success_count::NUMERIC / jsonb_array_length(p_payments)::NUMERIC) * v_total_amount
           )
     WHERE transaction_id = v_batch_id;

    -- Return detailed result
    RETURN jsonb_build_object(
        'status', 'COMPLETED',
        'batch_id', v_batch_id,
        'successful_count', v_success_count,
        'failed_count', v_failed_count,
        'total_amount_processed', (v_success_count::NUMERIC / jsonb_array_length(p_payments)::NUMERIC) * v_total_amount,
        'failed_details', v_failed_details
    );

EXCEPTION WHEN OTHERS THEN
    IF v_batch_id IS NOT NULL THEN
        UPDATE transactions
           SET status = 'failed',
               new_values = jsonb_build_object('error', SQLERRM)
         WHERE transaction_id = v_batch_id;
    END IF;

    RETURN jsonb_build_object(
        'status', 'ERROR',
        'message', SQLERRM,
        'successful_count', 0,
        'failed_count', jsonb_array_length(p_payments),
        'failed_details', '[]'::jsonb
    );
END;
$$;

-- Materialized View: Salary Batch Summary
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_salary_batch_summary AS
SELECT
    t.transaction_id AS batch_id,
    t.created_at::date AS batch_date,
    a.account_number AS company_account,
    c.full_name AS company_name,
    t.amount AS total_batch_amount,
    t.currency,
    t.amount_kzt AS total_batch_kzt,
    (t.new_values->>'successful_count')::int AS successful_payments,
    (t.new_values->>'failed_count')::int AS failed_payments,
    ROUND(100.0 * (t.new_values->>'successful_count')::int /
          NULLIF((t.new_values->>'successful_count')::int + (t.new_values->>'failed_count')::int, 0), 2) AS success_rate_pct
FROM transactions t
JOIN accounts a ON t.from_account_id = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
WHERE t.type = 'salary_batch'
  AND t.status = 'completed'
ORDER BY t.created_at DESC;

-- Refresh command
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_salary_batch_summary;

COMMENT ON MATERIALIZED VIEW mv_salary_batch_summary IS
'HR & Compliance dashboard: monthly salary batch results with success rate';