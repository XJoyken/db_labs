CREATE DATABASE lab_6;

-- Create table: employees
CREATE TABLE employees (
emp_id INT PRIMARY KEY,
emp_name VARCHAR(50),
dept_id INT,
salary DECIMAL(10, 2)
);
-- Create table: departments
CREATE TABLE departments (
dept_id INT PRIMARY KEY,
dept_name VARCHAR(50),
location VARCHAR(50)
);
-- Create table: projects
CREATE TABLE projects (
project_id INT PRIMARY KEY,
project_name VARCHAR(50),
dept_id INT,
budget DECIMAL(10, 2)
);


-- Insert data into employees
INSERT INTO employees (emp_id, emp_name, dept_id, salary)
VALUES
(1, 'John Smith', 101, 50000),
(2, 'Jane Doe', 102, 60000),
(3, 'Mike Johnson', 101, 55000),
(4, 'Sarah Williams', 103, 65000),
(5, 'Tom Brown', NULL, 45000);
-- Insert data into departments
INSERT INTO departments (dept_id, dept_name, location) VALUES
(101, 'IT', 'Building A'),
(102, 'HR', 'Building B'),
(103, 'Finance', 'Building C'),
(104, 'Marketing', 'Building D');
-- Insert data into projects
INSERT INTO projects (project_id, project_name, dept_id,
budget) VALUES
(1, 'Website Redesign', 101, 100000),
(2, 'Employee Training', 102, 50000),
(3, 'Budget Analysis', 103, 75000),
(4, 'Cloud Migration', 101, 150000),
(5, 'AI Research', NULL, 200000);


--TASK 2.1
SELECT e.emp_name, d.dept_name
FROM employees e
CROSS JOIN departments d;
-- N * M

--TASK 2.2
SELECT e.emp_name, d.dept_name
FROM employees e, departments d;

SELECT e.emp_name, d.dept_name
FROM employees e
INNER JOIN departments d ON TRUE;

--TASK 2.3
SELECT e.emp_name, p.project_name
FROM employees e
CROSS JOIN projects p;


--TASK 3.1
SELECT e.emp_name, d.dept_name, d.location
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id;
-- 4 rows were returned. Tom is not included because he does not have a specific dept_id

--TASK 3.2
SELECT e.emp_name, d.dept_name, d.location
FROM employees e
INNER JOIN departments d USING (dept_id);

--TASK 3.3
SELECT e.emp_name, d.dept_name, d.location
FROM employees e
NATURAL INNER JOIN departments d;

--TASK 3.4
SELECT e.emp_name, d.dept_name, p.project_name
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id
INNER JOIN projects p on d.dept_id = p.dept_id;


--TASK 4.1
SELECT e.emp_name, e.dept_id AS emp_dept, d.dept_id AS dept_dept, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id;
--Tom was represented with null values in the columns

--TASK 4.2
SELECT e.emp_name, e.dept_id AS emp_dept, d.dept_id AS dept_dept, d.dept_name
FROM employees e
LEFT JOIN departments d USING (dept_id);

--TASK 4.3
SELECT e.emp_name, e.dept_id
FROM employees e
LEFT JOIN departments d USING (dept_id)
WHERE d.dept_id IS NULL;

--TASK 4.4
SELECT d.dept_id, d.dept_name, COUNT(e.emp_id) AS employee_count
FROM departments d
LEFT JOIN employees e USING (dept_id)
GROUP BY d.dept_id, d.dept_name
ORDER BY employee_count DESC;


--TASK 5.1
SELECT e.emp_name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id;

--TASK 5.2
SELECT e.emp_name, d.dept_name
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id;

--TASK 5.3
SELECT d.dept_name, d.location
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id
WHERE e.emp_id IS NULL;

--TASK 6.1
SELECT e.emp_name, e.dept_id AS emp_dept, d.dept_id AS dept_dept, d.dept_name
FROM employees e
FULL JOIN departments d ON e.dept_id = d.dept_id;
--On the left - there is not a single employee in the marketing department
--On the right - Tom does not have a department

--TASK 6.2
SELECT d.dept_name, p.project_name, p.budget
FROM departments d
FULL JOIN projects p ON d.dept_id = p.dept_id;

--TASK 6.3
SELECT
    CASE
        WHEN e.emp_id IS NULL THEN 'Department without employees'
        WHEN d.dept_id IS NULL THEN 'Employee without department'
        ELSE 'Matched'
    END AS record_status,
    e.emp_name, d.dept_name
FROM employees e
FULL JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_id IS NULL OR e.emp_id IS NULL;


--TASK 7.1
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id AND d.location = 'Building A';

--TASK 7.2
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.location = 'Building A';
--Applies the filter BEFORE the join, so all employees are included, but only departments in Building A are matched.
--Applies the filter AFTER the join, so employees are excluded if their department is not in Building A.

--TASK 7.3
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id AND d.location = 'Building A';

--TASK 7.4
SELECT e.emp_name, d.dept_name, e.salary
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.location = 'Building A';
--There is no difference


--TASK 8.1
SELECT
    d.dept_name,
    e.emp_name,
    e.salary,
    p.project_name,
    p.budget
FROM departments d
LEFT JOIN employees e ON d.dept_id = e.dept_id
LEFT JOIN projects p on d.dept_id = p.dept_id
ORDER BY d.dept_name, e.emp_name;

--TASK 8.2
ALTER TABLE employees
ADD COLUMN manager_id INT;

UPDATE employees SET manager_id = 3 WHERE emp_id = 1;
UPDATE employees SET manager_id = 3 WHERE emp_id = 2;
UPDATE employees SET manager_id = NULL WHERE emp_id = 3;
UPDATE employees SET manager_id = 3 WHERE emp_id = 4;
UPDATE employees SET manager_id = 3 WHERE emp_id = 5;

SELECT e.emp_id, e.emp_name, m.emp_id, m.emp_name
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.emp_id;

--TASK 8.3
SELECT d.dept_id, d.dept_name, AVG(e.salary) AS avg_salary
FROM departments d
INNER JOIN employees e ON d.dept_id = e.dept_id
GROUP BY d.dept_id
HAVING AVG(e.salary) > 50000;


--Questions
--1)
--INNER JOIN: returns only matching rows.
--LEFT JOIN: returns all rows from the left table, with NULLs where no match.
--2)
--When you need all combinations of rows — e.g., color × size, or to create test data.
--3)
--Matters only for outer joins:
--In ON, unmatched rows stay (NULLs kept).
--In WHERE, unmatched rows are removed.
--For inner joins, no difference.
--4)
--If table1 has 5 rows and table2 has 10 the result = 5 × 10 = 50 rows.
--5)
--Joins automatically on all columns with the same name and compatible types.
--6)
--Unclear behavior — new same-named columns may change results; less control.
--7)
--SELECT * FROM A LEFT JOIN B ON A.id = B.id;
--SELECT * FROM B RIGHT JOIN A ON A.id = B.id;
--8)
--When you need all rows from both tables — matches and non-matches.

SELECT e.emp_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id

UNION

SELECT e.emp_name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id


SELECT e.emp_name, d.dept_name, dept_projects.project_count
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
JOIN (
    SELECT dept_id, COUNT(*) AS project_count
    FROM projects
    GROUP BY dept_id
    HAVING COUNT(*) > 1
) AS dept_projects ON d.dept_id = dept_projects.dept_id;

SELECT
    e.emp_name AS employee,
    m.emp_name AS manager,
    mm.emp_name AS manager_of_manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.emp_id
LEFT JOIN employees mm ON m.manager_id = mm.emp_id;
--or
WITH RECURSIVE org_chart AS (
    SELECT emp_id, emp_name, manager_id, 1 AS level
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    SELECT e.emp_id, e.emp_name, e.manager_id, oc.level + 1
    FROM employees e
    JOIN org_chart oc ON e.manager_id = oc.emp_id
)
SELECT emp_name, manager_id, level
FROM org_chart
ORDER BY level, emp_name;


SELECT e.emp_name, e2.emp_name, e.dept_id
FROM employees e
JOIN employees e2 ON e.dept_id = e2.dept_id AND e.emp_name < e2.emp_name;