CREATE DATABASE lab_4;

-- Create tables
CREATE TABLE employees (
employee_id SERIAL PRIMARY KEY,
first_name VARCHAR(50),
last_name VARCHAR(50),
department VARCHAR(50),
salary NUMERIC(10,2),
hire_date DATE,
manager_id INTEGER,
email VARCHAR(100)
);
CREATE TABLE projects (
project_id SERIAL PRIMARY KEY,
project_name VARCHAR(100),
budget NUMERIC(12,2),
start_date DATE,
end_date DATE,
status VARCHAR(20)
);
CREATE TABLE assignments (
assignment_id SERIAL PRIMARY KEY,
employee_id INTEGER REFERENCES employees(employee_id),
project_id INTEGER REFERENCES projects(project_id),
hours_worked NUMERIC(5,1),
assignment_date DATE
);

-- Insert sample data
INSERT INTO employees (first_name, last_name, department,
salary, hire_date, manager_id, email) VALUES
('John', 'Smith', 'IT', 75000, '2020-01-15', NULL,
'john.smith@company.com'),
('Sarah', 'Johnson', 'IT', 65000, '2020-03-20', 1,
'sarah.j@company.com'),
('Michael', 'Brown', 'Sales', 55000, '2019-06-10', NULL,
'mbrown@company.com'),
('Emily', 'Davis', 'HR', 60000, '2021-02-01', NULL,
'emily.davis@company.com'),
('Robert', 'Wilson', 'IT', 70000, '2020-08-15', 1, NULL),
('Lisa', 'Anderson', 'Sales', 58000, '2021-05-20', 3,
'lisa.a@company.com');
INSERT INTO projects (project_name, budget, start_date,
end_date, status) VALUES
('Website Redesign', 150000, '2024-01-01', '2024-06-30',
'Active'),
('CRM Implementation', 200000, '2024-02-15', '2024-12-31',
'Active'),
('Marketing Campaign', 80000, '2024-03-01', '2024-05-31',
'Completed'),
('Database Migration', 120000, '2024-01-10', NULL, 'Active');
INSERT INTO assignments (employee_id, project_id,
hours_worked, assignment_date) VALUES
(1, 1, 120.5, '2024-01-15'),
(2, 1, 95.0, '2024-01-20'),
(1, 4, 80.0, '2024-02-01'),
(3, 3, 60.0, '2024-03-05'),
(5, 2, 110.0, '2024-02-20'),
(6, 3, 75.5, '2024-03-10');

--TASK 1.1
SELECT
    employees.first_name || ' ' || employees.last_name AS full_name,
    employees.department,
    employees.salary
FROM employees;

--TASK 1.2
SELECT DISTINCT employees.department
FROM employees;

--TASK 1.3
SELECT
    projects.project_name,
    projects.budget,
    CASE
        WHEN projects.budget > 150000 THEN 'Large'
        WHEN projects.budget BETWEEN 100000 AND 150000 THEN 'Medium'
        ELSE 'Small'
    END AS budget_category
FROM projects;

--TASK 1.4
SELECT
    employees.first_name || ' ' || employees.last_name AS full_name,
    COALESCE(employees.email, 'No email provided') AS email
FROM employees;

--TASK 2.1
SELECT *
FROM employees
WHERE hire_date > '2020-01-01';

--TASK 2.2
SELECT *
FROM employees
WHERE salary BETWEEN 60000 AND 70000;

--TASK 2.3
SELECT *
FROM employees
WHERE last_name LIKE 'S%' OR last_name LIKE 'J%';

--TASK 2.4
SELECT *
FROM employees
WHERE manager_id IS NOT NULL
AND department = 'IT';

--TASK 3.1
SELECT
    upper(employees.first_name || ' ' || employees.last_name) AS full_name,
    length(employees.last_name) AS last_name_length,
    substring(employees.email FROM 1 FOR 3) AS email
FROM employees;

--TASK 3.2
SELECT
    employees.salary AS anual_salary,
    ROUND(employees.salary / 12, 2) AS monthly_salary,
    employees.salary * 0.1 AS raise_amount
FROM employees;

--TASK 3.3
SELECT
    format(
    'Project: %s - Budget: $%s - Status: %s',
    project_name,
    budget,
    status
    ) AS project_info
FROM projects;

--TASK 3.4
SELECT
    employees.first_name || ' ' || employees.last_name AS full_name,
    hire_date,
    extract(YEAR FROM AGE(CURRENT_DATE, employees.hire_date)) AS years_with_company
FROM employees;

--TASK 4.1
SELECT employees.department, AVG(employees.salary) AS avg_salary
FROM employees
GROUP BY department;

--TASK 4.2
SELECT projects.project_name,
       SUM(a.hours_worked) as total_hours_worked
FROM projects
JOIN assignments a ON a.project_id = projects.project_id
GROUP BY project_name;

--TASK 4.3
SELECT employees.department,
       count(*) AS employee_count
FROM employees
GROUP BY department
HAVING count(*) > 1;

--TASK 4.4
SELECT MAX(employees.salary) AS max_salary,
       MIN(employees.salary) AS min_salary,
       SUM(employees.salary) AS total_payroll
FROM employees;

--TASK 5.1
SELECT
    employee_id,
    employees.first_name || ' ' || employees.last_name AS full_name,
    salary
FROM employees
WHERE salary > 65000
UNION
SELECT
    employee_id,
    employees.first_name || ' ' || employees.last_name AS full_name,
    salary
FROM employees
WHERE hire_date > '2020-01-01';

--TASK 5.2
SELECT
    employees.employee_id,
    employees.first_name || ' ' || employees.last_name AS full_name
FROM employees
WHERE department = 'IT'
UNION
SELECT
    employees.employee_id,
    employees.first_name || ' ' || employees.last_name AS full_name
FROM employees
WHERE salary > 65000;

--TASK 5.3
SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name
FROM employees e
EXCEPT
SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name
FROM employees e
JOIN assignments a ON a.employee_id = e.employee_id;

--TASK 6.1
SELECT
    first_name || ' ' || last_name AS full_name
FROM employees
WHERE EXISTS(
    SELECT 1
    FROM assignments a
    WHERE a.employee_id = employees.employee_id
);

--TASK 6.2
SELECT DISTINCT
    e.employee_id,
    first_name || ' ' || last_name AS full_name
FROM employees e
JOIN assignments a ON a.employee_id = e.employee_id
WHERE a.project_id IN(
    SELECT p.project_id
    FROM projects p
    WHERE p.status = 'Active'
    );

--TASK 6.3
SELECT
    employee_id,
    first_name || ' ' || last_name AS full_name,
    salary
FROM employees
WHERE salary > ANY(
    SELECT salary
    FROM employees
    WHERE department = 'Sales'
    );

--TASK 7.1
SELECT
    first_name || ' ' || last_name AS full_name,
    e.department,
    e.salary,
    AVG(a.hours_worked) AS avg_hours_worked,
    RANK() OVER (PARTITION BY e.department ORDER BY e.salary DESC ) AS salary_rank
FROM employees e
JOIN assignments a on e.employee_id = a.employee_id
GROUP BY full_name, department, salary
ORDER BY department, salary_rank;

--TASK 7.2
SELECT
    projects.project_name,
    SUM(a.hours_worked) AS total_hours,
    COUNT(*) AS employees_assigned
FROM projects
JOIN assignments a on projects.project_id = a.project_id
GROUP BY project_name
HAVING SUM(a.hours_worked) > 150;

--TASK 7.3
SELECT
    e.department,
    COUNT(*) AS number_of_employees,
    AVG(e.salary) AS avg_salary,
    (
        SELECT e2.first_name || ' ' || e2.last_name AS full_name
        FROM employees e2
        WHERE e2.department = e.department
        ORDER BY e2.salary DESC
        LIMIT 1
        ),
    GREATEST(MAX(salary), AVG(salary)) AS salary_comparison,
    LEAST(MAX(salary), AVG(salary)) AS lowest_vs_avg
FROM employees e
GROUP BY department