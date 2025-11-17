CREATE DATABASE lab_8;

-- Create tables
CREATE TABLE departments (
dept_id INT PRIMARY KEY,
dept_name VARCHAR(50),
location VARCHAR(50)
);
CREATE TABLE employees (
emp_id INT PRIMARY KEY,
emp_name VARCHAR(100),
dept_id INT,
salary DECIMAL(10,2),
FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);
CREATE TABLE projects (
proj_id INT PRIMARY KEY,
proj_name VARCHAR(100),
budget DECIMAL(12,2),
dept_id INT,
FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);
-- Insert sample data
INSERT INTO departments VALUES
(101, 'IT', 'Building A'),
(102, 'HR', 'Building B'),
(103, 'Operations', 'Building C');
INSERT INTO employees VALUES
(1, 'John Smith', 101, 50000),
(2, 'Jane Doe', 101, 55000),
(3, 'Mike Johnson', 102, 48000),
(4, 'Sarah Williams', 102, 52000),
(5, 'Tom Brown', 103, 60000);
INSERT INTO projects VALUES
(201, 'Website Redesign', 75000, 101),
(202, 'Database Migration', 120000, 101),
(203, 'HR System Upgrade', 50000, 102);

--TASK 2.1
CREATE INDEX emp_salary_idx ON employees(salary);

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'employees';
--2, 1 - primary key, 2 - salary index

--TASK 2.2
CREATE INDEX emp_dept_idx ON employees(dept_id);
SELECT * FROM employees WHERE dept_id = 101;
--Faster JOINs, faster DELETE/UPDATE on the parent table etc.

--TASK 2.3
SELECT
tablename,
indexname,
indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
--primary key
--TASK 3.1
CREATE INDEX emp_dept_salary_idx ON employees(dept_id, salary);

SELECT emp_name, salary
FROM employees
WHERE dept_id = 101 AND salary > 52000;
--No, the index is not useful for queries filtering only by salary, because PostgreSQL must use the first column (dept_id) to navigate the index. Without it, the index can't be searched efficiently.

--TASK 3.2
CREATE INDEX emp_salary_dept_idx ON employees(salary, dept_id);

SELECT * FROM employees WHERE dept_id = 102 AND salary > 50000;
SELECT * FROM employees WHERE salary > 50000 AND dept_id = 102;
--Yes, it does. A multicolumn index works only when the query uses the index's leftmost prefix.

--TASK 4.1
ALTER TABLE employees ADD COLUMN email VARCHAR(100);
UPDATE employees SET email = 'john.smith@company.com' WHERE emp_id = 1;
UPDATE employees SET email = 'jane.doe@company.com' WHERE emp_id = 2;
UPDATE employees SET email = 'mike.johnson@company.com' WHERE emp_id = 3;
UPDATE employees SET email = 'sarah.williams@company.com' WHERE emp_id = 4;
UPDATE employees SET email = 'tom.brown@company.com' WHERE emp_id = 5;

CREATE UNIQUE INDEX emp_email_unique_idx ON employees(email);

INSERT INTO employees (emp_id, emp_name, dept_id, salary, email)
VALUES (6, 'New Employee', 101, 55000, 'john.smith@company.com');
--ERROR: duplicate key value violates unique constraint "emp_email_unique_idx"
--Подробности: Key (email)=(john.smith@company.com) already exists.

--TASK 4.2
ALTER TABLE employees ADD COLUMN phone VARCHAR(20) UNIQUE;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'employees' AND indexname LIKE '%phone%';
--Yes. Unique index on phone column

--TASK 5.1
CREATE INDEX emp_salary_desc_idx ON employees(salary DESC);

SELECT emp_name, salary
FROM employees
ORDER BY salary DESC;
--The descending index stores values already sorted in DESC order, so PostgreSQL can satisfy ORDER BY salary DESC directly from the index without performing an extra sort, making the query faster and more efficient.

--TASK 5.2
CREATE INDEX proj_budget_nulls_first_idx ON projects(budget NULLS FIRST);

SELECT proj_name, budget
FROM projects
ORDER BY budget NULLS FIRST;

--TASK 6.1
CREATE INDEX emp_name_lower_idx ON employees(lower(emp_name));

SELECT * FROM employees WHERE LOWER(emp_name) = 'john smith';
--Without the expression index, PostgreSQL must perform a full table scan, converting every emp_name to lowercase at runtime, because a normal index on emp_name cannot be used with LOWER(emp_name) in the WHERE clause.

--TASK 6.2
ALTER TABLE employees ADD COLUMN hire_date DATE;
UPDATE employees SET hire_date = '2020-01-15' WHERE emp_id = 1;
UPDATE employees SET hire_date = '2019-06-20' WHERE emp_id = 2;
UPDATE employees SET hire_date = '2021-03-10' WHERE emp_id = 3;
UPDATE employees SET hire_date = '2020-11-05' WHERE emp_id = 4;
UPDATE employees SET hire_date = '2018-08-25' WHERE emp_id = 5;

CREATE INDEX emp_hire_year_idx ON employees(EXTRACT(YEAR FROM hire_date));

SELECT emp_name, hire_date
FROM employees
WHERE EXTRACT(YEAR FROM hire_date) = 2020;

--TASK 7.1
ALTER INDEX emp_salary_idx
RENAME TO employees_salary_index;

SELECT indexname FROM pg_indexes WHERE tablename = 'employees';

--TASK 7.2
DROP INDEX emp_salary_dept_idx;
--You might drop an index because it's unused, slows down writes, takes up space, duplicates another index, or is no longer useful due to schema or workload changes.

--TASK 7.3
REINDEX INDEX employees_salary_index;

--TASK 8.1
SELECT e.emp_name, e.salary, d.dept_name
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
WHERE e.salary > 50000
ORDER BY e.salary DESC;

CREATE INDEX emp_salary_filter_idx ON employees(salary DESC) WHERE salary > 50000;

--TASK 8.2
CREATE INDEX proj_high_budget_idx ON projects(budget) WHERE budget > 80000;

SELECT proj_name, budget
FROM projects
WHERE budget > 80000;

--Partial index is better when your queries target a specific subset of rows — it’s smaller, faster, and reduces write overhead compared to a full index.

--TASK 8.3
EXPLAIN SELECT * FROM employees WHERE salary > 52000;
--Seeing a Seq Scan here tells us there is no suitable index for salary > 52000

--TASK 9.1
CREATE INDEX dept_name_hash_idx ON departments USING HASH (dept_name);
SELECT * FROM departments WHERE dept_name = 'IT';
EXPLAIN SELECT * FROM departments WHERE dept_name = 'IT';
--Seq Scan on departments  (cost=0.00..1.04 rows=1 width=240)
--Filter: ((dept_name)::text = 'IT'::text)
--Very large tables with highly selective equality queries

--TASK 9.2
CREATE INDEX proj_name_btree_idx ON projects(proj_name);
CREATE INDEX proj_name_hash_idx ON projects USING hash(proj_name);

-- Equality search (both can be used)
SELECT * FROM projects WHERE proj_name = 'Website Redesign';
-- Range search (only B-tree can be used)
SELECT * FROM projects WHERE proj_name > 'Database';

--TASK 10.1
SELECT
schemaname,
tablename,
indexname,
pg_size_pretty(pg_relation_size(indexname::regclass)) as index_size
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

--The HASH index is the largest because of pre-allocated hash buckets and extra storage overhead, even though it stores the same number of entries as other indexes. B-tree indexes are more compact and efficient in storage.

--TASK 10.2
DROP INDEX IF EXISTS proj_name_hash_idx;

--TASK 10.3
CREATE VIEW index_documentation AS
SELECT
tablename,
indexname,
indexdef,
'Improves salary-based queries' as purpose
FROM pg_indexes
WHERE schemaname = 'public'
AND indexname LIKE '%salary%';
SELECT * FROM index_documentation;

--Questions:
--1) B-tree
--2) Columns frequently used in WHERE clauses; Columns used in JOIN conditions; Columns used in ORDER BY or GROUP BY
--3) Columns rarely used in queries; Columns with very high write activity (INSERT/UPDATE/DELETE), where index maintenance overhead outweighs benefits
--4) Indexes are updated automatically to reflect the changes; More indexes - slower write operations
--5) Use EXPLAIN or EXPLAIN ANALYZE

--Additional Challenges:
--1)
CREATE INDEX emp_hire_month_idx ON employees (EXTRACT(MONTH FROM hire_date));
--2)
CREATE UNIQUE INDEX dept_id_email_unq_idx ON employees(dept_id, email);
--3)
EXPLAIN ANALYZE SELECT * FROM employees WHERE salary > 52000;
--4)
CREATE INDEX idx_employees_covering ON employees (dept_id, salary) INCLUDE (emp_name);

EXPLAIN ANALYZE
SELECT emp_name, salary
FROM employees
WHERE dept_id = 101 AND salary > 52000;