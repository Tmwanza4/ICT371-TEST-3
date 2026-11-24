-- ICT371 Question 6: Monthly Payroll Processing (PostgreSQL)
-- gross = basic_salary + allowance;  net = gross - deduction

DROP TABLE IF EXISTS salary_audit, payroll, employees CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE employees (
    employee_id  SERIAL PRIMARY KEY,
    full_name    VARCHAR(100)  NOT NULL,
    basic_salary NUMERIC(12,2) NOT NULL CHECK (basic_salary >= 0),
    allowance    NUMERIC(12,2) NOT NULL CHECK (allowance >= 0),
    deduction    NUMERIC(12,2) NOT NULL CHECK (deduction >= 0),
    active       BOOLEAN       NOT NULL DEFAULT TRUE
);

CREATE TABLE payroll (
    payroll_id  SERIAL PRIMARY KEY,
    employee_id INTEGER       NOT NULL REFERENCES employees(employee_id),
    pay_month   DATE          NOT NULL,
    gross_pay   NUMERIC(12,2) NOT NULL,
    net_pay     NUMERIC(12,2) NOT NULL,
    CONSTRAINT ck_month_start CHECK (EXTRACT(DAY FROM pay_month) = 1),   -- first day of a month
    CONSTRAINT uq_employee_month UNIQUE (employee_id, pay_month)
);

CREATE TABLE salary_audit (
    audit_id    SERIAL PRIMARY KEY,
    employee_id INTEGER       NOT NULL REFERENCES employees(employee_id),
    old_salary  NUMERIC(12,2) NOT NULL,
    new_salary  NUMERIC(12,2) NOT NULL,
    changed_at  TIMESTAMP     NOT NULL DEFAULT now()
);

INSERT INTO employees (full_name, basic_salary, allowance, deduction, active) VALUES
    ('Chanda Mulenga', 8000.00, 1500.00, 1200.00, TRUE),
    ('Mwila Banda',    6500.00, 1000.00,  900.00, TRUE),
    ('Temba Phiri',    7200.00,  800.00, 1000.00, TRUE),
    ('Natasha Zulu',   5500.00,  500.00,  700.00, TRUE),
    ('Bwalya Tembo',   6000.00,  700.00,  800.00, TRUE);   -- becomes inactive further down

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INTEGER)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_basic NUMERIC;
    v_allow NUMERIC;
    v_deduc NUMERIC;
    v_net   NUMERIC;
BEGIN
    SELECT basic_salary, allowance, deduction
    INTO v_basic, v_allow, v_deduc
    FROM employees
    WHERE employee_id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown employee_id %', p_employee_id;
    END IF;

    v_net := v_basic + v_allow - v_deduc;

    IF v_net < 0 THEN
        RAISE EXCEPTION 'Negative net pay (%) for employee %', v_net, p_employee_id;
    END IF;

    RETURN v_net;
END;
$$;

-- =====================================================================
-- (c) Procedure: query FOR loop over active employees
-- Any exception (e.g. negative net pay) aborts the whole call, so no
-- partial month is ever stored.
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    rec    RECORD;
    v_net  NUMERIC;
BEGIN
    IF p_month IS NULL OR EXTRACT(DAY FROM p_month) <> 1 THEN
        RAISE EXCEPTION 'p_month must be the first date of a month (got %)', p_month;
    END IF;

    FOR rec IN
        SELECT employee_id, basic_salary, allowance
        FROM employees
        WHERE active = TRUE
        ORDER BY employee_id
    LOOP
        v_net := fn_net_pay(rec.employee_id);     -- raises if invalid

        INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay)
        VALUES (rec.employee_id, p_month, rec.basic_salary + rec.allowance, v_net)
        ON CONFLICT (employee_id, pay_month) DO NOTHING;   -- existing rows stay unchanged
    END LOOP;
END;
$$;

-- =====================================================================
-- (d) Trigger: log real basic_salary changes only
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_salary_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO salary_audit (employee_id, old_salary, new_salary)
    VALUES (OLD.employee_id, OLD.basic_salary, NEW.basic_salary);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_salary_audit
AFTER UPDATE ON employees
FOR EACH ROW
WHEN (OLD.basic_salary IS DISTINCT FROM NEW.basic_salary)
EXECUTE FUNCTION trg_fn_salary_audit();

-- (a, continued) Two payroll months of data, then changes
CALL pr_process_payroll(DATE '2026-09-01');
CALL pr_process_payroll(DATE '2026-10-01');
UPDATE employees SET active = FALSE WHERE employee_id = 5;        -- later becomes inactive
UPDATE employees SET basic_salary = 8500.00 WHERE employee_id = 1;   -- real salary change
UPDATE employees SET allowance = allowance WHERE employee_id = 2;    -- no salary change

SELECT * FROM payroll ORDER BY pay_month, employee_id;

-- Tests for (b)
SELECT employee_id, fn_net_pay(employee_id) AS net FROM employees ORDER BY employee_id;
DO $$ BEGIN PERFORM fn_net_pay(999);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown): %', SQLERRM; END $$;
-- negative computed net: deduction larger than basic + allowance
UPDATE employees SET deduction = 99999 WHERE employee_id = 4;
DO $$ BEGIN PERFORM fn_net_pay(4);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (negative net): %', SQLERRM; END $$;
-- the whole call must fail and store nothing for the new month
DO $$ BEGIN CALL pr_process_payroll(DATE '2026-11-01');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (whole call fails): %', SQLERRM; END $$;
SELECT COUNT(*) AS november_rows FROM payroll WHERE pay_month = DATE '2026-11-01';   -- 0
UPDATE employees SET deduction = 700.00 WHERE employee_id = 4;      -- repair the data

-- Tests for (c)
DO $$ BEGIN CALL pr_process_payroll(DATE '2026-10-15');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (not month start): %', SQLERRM; END $$;
CALL pr_process_payroll(DATE '2026-10-01');       -- rerun: existing rows unchanged
SELECT COUNT(*) AS october_rows FROM payroll WHERE pay_month = DATE '2026-10-01';    -- still 5

-- Test for (d)
SELECT * FROM salary_audit ORDER BY audit_id;     -- employee 1 only

-- =====================================================================
-- (e) View: inner join keeps history of employees who are now inactive
-- =====================================================================
CREATE OR REPLACE VIEW v_payroll_report AS
SELECT e.full_name,
       p.pay_month,
       p.gross_pay,
       p.net_pay
FROM payroll p
JOIN employees e ON e.employee_id = p.employee_id;

SELECT * FROM v_payroll_report ORDER BY pay_month, full_name;

-- =====================================================================
-- (f) Index
-- The existing unique index is (employee_id, pay_month). It starts with
-- employee_id, so it cannot efficiently answer "all employees for one month".
-- A single-column index on pay_month does, and does not duplicate it.
-- =====================================================================
CREATE INDEX idx_payroll_pay_month ON payroll (pay_month);

ANALYZE payroll;
SET enable_seqscan = off;
EXPLAIN
SELECT employee_id, gross_pay, net_pay
FROM payroll
WHERE pay_month = DATE '2026-10-01';
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: 02:00 on the 1st of each month, for the PREVIOUS month
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule(
    'pr_process_payroll_monthly',
    '0 2 1 * *',
    $$CALL pr_process_payroll(date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date)$$
);

-- Inspect the job definition
SELECT jobid, jobname, schedule, command FROM cron.job;

-- Inspect run history (pg_cron records every run here)
SELECT jobid, status, start_time FROM cron.job_run_details ORDER BY start_time DESC;
-- With the real pg_cron, you can also use:
--   SELECT runid, jobid, status, return_message, start_time, end_time
--   FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
