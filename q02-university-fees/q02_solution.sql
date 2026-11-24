-- ICT371 Question 2: University Fee Payments (PostgreSQL)

DROP TABLE IF EXISTS daily_collections, payment_audit, payments, students CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE students (
    student_id     SERIAL PRIMARY KEY,
    student_number VARCHAR(20)   NOT NULL UNIQUE,
    full_name      VARCHAR(100)  NOT NULL,
    fee_due        NUMERIC(12,2) NOT NULL CHECK (fee_due >= 0)
);

CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    student_id INTEGER       NOT NULL REFERENCES students(student_id),
    amount     NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    paid_on    DATE          NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE payment_audit (
    audit_id   SERIAL PRIMARY KEY,
    payment_id INTEGER       NOT NULL REFERENCES payments(payment_id),
    student_id INTEGER       NOT NULL REFERENCES students(student_id),
    amount     NUMERIC(12,2) NOT NULL,
    logged_at  TIMESTAMP     NOT NULL DEFAULT now()
);

CREATE TABLE daily_collections (
    collection_date DATE PRIMARY KEY,
    payment_count   INTEGER       NOT NULL,
    total_amount    NUMERIC(12,2) NOT NULL
);

INSERT INTO students (student_number, full_name, fee_due) VALUES
    ('202401001', 'Chanda Mulenga', 5000.00),
    ('202401002', 'Mwila Banda',    3000.00),
    ('202401003', 'Temba Phiri',    4500.00);   -- this student starts with no payments

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INTEGER)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_fee  NUMERIC;
    v_paid NUMERIC;
BEGIN
    SELECT fee_due INTO v_fee FROM students WHERE student_id = p_student_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown student_id %', p_student_id;
    END IF;

    -- COALESCE makes "no payments" count as 0, so the full fee is returned.
    SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM payments
    WHERE student_id = p_student_id;

    RETURN v_fee - v_paid;
END;
$$;

-- =====================================================================
-- (c) Procedure (does NOT write the audit row; the trigger does)
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INTEGER, p_amount NUMERIC, p_paid_on DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero (got %)', p_amount;
    END IF;
    IF p_paid_on IS NULL THEN
        RAISE EXCEPTION 'Payment date must not be NULL';
    END IF;

    -- Lock the student row so two simultaneous payments cannot overpay.
    PERFORM 1 FROM students WHERE student_id = p_student_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown student_id %', p_student_id;
    END IF;

    v_balance := fn_fee_balance(p_student_id);
    IF p_amount > v_balance THEN
        RAISE EXCEPTION 'Payment % exceeds outstanding balance % for student %',
            p_amount, v_balance, p_student_id;
    END IF;

    INSERT INTO payments (student_id, amount, paid_on)
    VALUES (p_student_id, p_amount, p_paid_on);      -- fee_due is never touched
END;
$$;

-- =====================================================================
-- (d) Trigger: automatic audit of every payment
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_payment_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO payment_audit (payment_id, student_id, amount, logged_at)
    VALUES (NEW.payment_id, NEW.student_id, NEW.amount, now());
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_payment_audit
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION trg_fn_payment_audit();

-- =====================================================================
-- (a, continued) Seed payments through the procedure (audit is automatic)
-- Student 1 pays in full, student 2 pays part, student 3 pays nothing.
-- =====================================================================
CALL pr_receive_payment(1, 2000.00, CURRENT_DATE - 3);
CALL pr_receive_payment(1, 1500.00, CURRENT_DATE - 2);
CALL pr_receive_payment(1, 1500.00, CURRENT_DATE - 1);   -- student 1 now fully settled
CALL pr_receive_payment(2,  800.00, CURRENT_DATE - 2);
CALL pr_receive_payment(2,  700.00, CURRENT_DATE - 1);
CALL pr_receive_payment(2,  500.00, CURRENT_DATE - 1);

SELECT * FROM payments ORDER BY payment_id;
SELECT * FROM payment_audit ORDER BY audit_id;           -- one row per payment

-- Tests for (b) and (c)
SELECT student_id, fn_fee_balance(student_id) AS balance FROM students ORDER BY student_id;
-- expected: 0.00, 1000.00, 4500.00 (student 3 has no payments, full fee returned)
DO $$ BEGIN PERFORM fn_fee_balance(999);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error: %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_payment(3, NULL, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (NULL): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_payment(3, 0, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (zero): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_payment(3, -10, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (negative): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_payment(2, 5000, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (above balance): %', SQLERRM; END $$;
SELECT student_id, fee_due FROM students ORDER BY student_id;   -- fee_due unchanged

-- =====================================================================
-- (e) View: only students who still owe fees
-- =====================================================================
CREATE OR REPLACE VIEW v_fee_balances AS
SELECT s.student_number,
       s.full_name,
       s.fee_due - COALESCE(SUM(p.amount), 0) AS outstanding_balance
FROM students s
LEFT JOIN payments p ON p.student_id = s.student_id
GROUP BY s.student_id, s.student_number, s.full_name, s.fee_due
HAVING s.fee_due - COALESCE(SUM(p.amount), 0) > 0;

SELECT * FROM v_fee_balances;      -- student 1 (settled) is excluded

-- =====================================================================
-- (f) Index
-- Equality on student_id first, range on paid_on second. INCLUDE (amount)
-- lets the query be answered from the index alone.
-- =====================================================================
CREATE INDEX idx_payments_student_paid_on ON payments (student_id, paid_on) INCLUDE (amount);

ANALYZE payments;
SET enable_seqscan = off;
EXPLAIN
SELECT payment_id, amount, paid_on
FROM payments
WHERE student_id = 2
  AND paid_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: replaces the day's summary row on every rerun
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO daily_collections (collection_date, payment_count, total_amount)
    SELECT p_day, COUNT(*), COALESCE(SUM(amount), 0)
    FROM payments
    WHERE paid_on = p_day
    ON CONFLICT (collection_date) DO UPDATE
    SET payment_count = EXCLUDED.payment_count,
        total_amount  = EXCLUDED.total_amount;
END;
$$;

CALL pr_refresh_collections(CURRENT_DATE - 1);
CALL pr_refresh_collections(CURRENT_DATE - 1);     -- rerun replaces, never adds
SELECT * FROM daily_collections;

-- Schedule with pg_cron: daily at 01:00 for the previous day
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_collections_daily', '0 1 * * *',
                     $$CALL pr_refresh_collections(CURRENT_DATE - 1)$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
