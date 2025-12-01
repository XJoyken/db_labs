CREATE DATABASE lab_10;

CREATE TABLE accounts (
id SERIAL PRIMARY KEY,
name VARCHAR(100) NOT NULL,
balance DECIMAL(10, 2) DEFAULT 0.00
);
CREATE TABLE products (
id SERIAL PRIMARY KEY,
shop VARCHAR(100) NOT NULL,
product VARCHAR(100) NOT NULL,
price DECIMAL(10, 2) NOT NULL
);
-- Insert test data
INSERT INTO accounts (name, balance) VALUES
                                        ('Alice', 1000.00),
                                        ('Bob', 500.00),
                                        ('Wally', 750.00);
INSERT INTO products (shop, product, price) VALUES
                                                ('Joe''s Shop', 'Coke', 2.50),
                                                ('Joe''s Shop', 'Pepsi', 3.00);

--3.2 TASK 1
BEGIN;
UPDATE accounts SET balance = balance - 100.00 WHERE name = 'Alice';
UPDATE accounts SET balance = balance + 100.00 WHERE name = 'Bob';
COMMIT;
--1)Alice = 900, Bob = 600
--2)The money may disappear
--3)The money will disappear

--3.3 TASK 2

BEGIN;
UPDATE accounts SET balance = balance - 500.00 WHERE name = 'Alice';
SELECT * FROM accounts WHERE name = 'Alice';
ROLLBACK;
SELECT * FROM accounts WHERE name = 'Alice';
--balance - 500
--balance
--if there is not enough money

--3.4 TASK 3
select * from accounts;
BEGIN;
UPDATE accounts SET balance = balance - 100.00 WHERE name = 'Alice';
SAVEPOINT my_savepoint;
UPDATE accounts SET balance = balance + 100.00 WHERE name = 'Bob';
ROLLBACK TO my_savepoint;
UPDATE accounts SET balance = balance + 100.00 WHERE name = 'Wally';
COMMIT;
--alice - 100, wally + 100
--no, we did rollback
--it will not be possible to roll back only part of the operation, the new transaction will not change the external one in any way

--3.5 TASK 4
--scenario a
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT * FROM products WHERE shop = 'Joe''s Shop';

BEGIN;
DELETE FROM products WHERE shop = 'Joe''s Shop';
INSERT INTO products (shop, product, price)
VALUES ('Joe''s Shop', 'Fanta', 3.50);
COMMIT;

SELECT * FROM products WHERE shop = 'Joe''s Shop';
COMMIT;

--scenario b
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE ;
SELECT * FROM products WHERE shop = 'Joe''s Shop';

BEGIN;
DELETE FROM products WHERE shop = 'Joe''s Shop';
INSERT INTO products (shop, product, price)
VALUES ('Joe''s Shop', 'Fanta', 3.50);
COMMIT;

SELECT * FROM products WHERE shop = 'Joe''s Shop';
COMMIT;

--a) before - information is unchanged, after - only fanta (phantom)
--b) before - information is unchanged, after - the same information, without changing (no phantom)
--c) in serializable operations are guaranteed to take turns, but in read committed not

--3.6 TASK 5
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT MAX(price), MIN(price) FROM products WHERE shop = 'Joe''s Shop';
BEGIN;
INSERT INTO products (shop, product, price)
VALUES ('Joe''s Shop', 'Sprite', 4.00);
COMMIT;
SELECT MAX(price), MIN(price) FROM products WHERE shop = 'Joe''s Shop';
COMMIT;

--a) no, does not see
--b) A Phantom Read is a situation where, when executing the same query repeatedly, new rows appear (or old ones disappear) inside the same transaction that were not there when it was first executed
--c) Repeatable Read and Serializable

--3.7 Task 6
--terminal 1
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT * FROM products WHERE shop = 'Joe''s Shop';
-- Wait for Terminal 2 to UPDATE but NOT commit
SELECT * FROM products WHERE shop = 'Joe''s Shop';
-- Wait for Terminal 2 to ROLLBACK
SELECT * FROM products WHERE shop = 'Joe''s Shop';
COMMIT;
--terminal 2
BEGIN;
UPDATE products SET price = 99.99
WHERE product = 'Fanta';
-- Wait here (don't commit yet)
-- Then:
ROLLBACK;

--a) no, does not
--b) Dirty Read is when one transaction reads the uncommitted ("dirty") changes of another transaction, which can then be rolled back
--c) It's dangerous because it allows you to read data that never existed

--4
--Ex 1
DO $$
DECLARE
    bob_balance DECIMAL(12,2);
BEGIN
    SELECT balance INTO bob_balance
    FROM accounts
    WHERE name = 'Bob'
    FOR UPDATE;

    IF bob_balance < 200.00 THEN
        RAISE EXCEPTION 'Unsufficient funds: %', bob_balance;
    END IF;

    UPDATE accounts SET balance = balance - 200 WHERE name = 'Bob';
    UPDATE accounts SET balance = balance + 200 WHERE name = 'Wally';
END $$;

--Ex 2
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
INSERT INTO products(shop, product, price) VALUES(
                                                  'sulpak', 'laptop', 1200.00
                                                 );
SAVEPOINT after_insert;

UPDATE products SET price = 999.99 WHERE product = 'Laptop';
SAVEPOINT after_update;

DELETE FROM products WHERE product = 'Laptop';
ROLLBACK TO SAVEPOINT after_insert;
COMMIT;

--Ex 3
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE accounts SET balance = balance - 300 WHERE name = 'Alice';
COMMIT;

BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE accounts SET balance = balance - 300 WHERE name = 'Alice';
COMMIT;


BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM accounts WHERE name = 'Alice' FOR UPDATE;
UPDATE accounts SET balance = balance - 300 WHERE name = 'Alice';
COMMIT;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM accounts WHERE name = 'Alice' FOR UPDATE;
ROLLBACK;


BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT balance FROM accounts WHERE name = 'Alice';
UPDATE accounts SET balance = balance - 300 WHERE name = 'Alice';
COMMIT;

BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT balance FROM accounts WHERE name = 'Alice';
UPDATE accounts SET balance = balance - 300 WHERE name = 'Alice';
COMMIT;


--Ex 4
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT MAX(price) AS max_price, MIN(price) AS min_price
FROM products
WHERE shop = 'Joe''s Shop';

UPDATE products SET price = 10.00 WHERE product = 'Fanta';
UPDATE products SET price = 1.00  WHERE product = 'Sprite';
COMMIT;

SELECT MAX(price) AS max_price, MIN(price) AS min_price
FROM products
WHERE shop = 'Joe''s Shop';

COMMIT;