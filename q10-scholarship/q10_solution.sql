-- ICT371 Question 10: Scholarship Application Assessment (PostgreSQL)
-- Eligible only if: age 18-25 inclusive AND monthly income <= K3,000 AND average mark >= 70.

DROP TABLE IF EXISTS decision_audit, applications, students CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE students (
    student_id     SERIAL PRIMARY KEY,
    student_number VARCHAR(20)  NOT NULL UNIQUE,
    full_name      VARCHAR(100) NOT NULL
);

CREATE TABLE applications (
    application_id     SERIAL PRIMARY KEY,
    student_id         INTEGER       NOT NULL REFERENCES students(student_id),
    age_at_application INTEGER       NOT NULL CHECK (age_at_application > 0),
    monthly_income     NUMERIC(10,2) NOT NULL CHECK (monthly_income >= 0),
    average_mark       NUMERIC(5,2)  NOT NULL CHECK (average_mark BETWEEN 0 AND 100),
    submitted_on       DATE          NOT NULL,
    status             VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    CONSTRAINT ck_app_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED'))
);

CREATE TABLE decision_audit (
    audit_id       SERIAL PRIMARY KEY,
    application_id INTEGER     NOT NULL REFERENCES applications(application_id),
    old_status     VARCHAR(10) NOT NULL,
    new_status     VARCHAR(10) NOT NULL,
    changed_at     TIMESTAMP   NOT NULL DEFAULT now()
);

INSERT INTO students (student_number, full_name) VALUES
    ('202406001', 'Chanda Mulenga'),
    ('202406002', 'Mwila Banda'),
    ('202406003', 'Temba Phiri');

-- Six PENDING applications: clearly qualifying, exact boundaries, and failures
INSERT INTO applications (student_id, age_at_application, monthly_income, average_mark, submitted_on) VALUES
    (1, 20, 1500.00, 85.00, CURRENT_DATE - 20),   -- 1: clearly qualifies
    (1, 18, 3000.00, 70.00, CURRENT_DATE - 15),   -- 2: boundary (min age, max income, min mark): qualifies
    (2, 25, 2999.99, 70.00, CURRENT_DATE - 12),   -- 3: boundary (max age): qualifies
    (2, 26, 1000.00, 90.00, CURRENT_DATE - 10),   -- 4: too old: rejected
    (3, 22, 3000.01, 80.00, CURRENT_DATE - 7),    -- 5: income just above K3,000: rejected
    (3, 21, 2000.00, 69.99, CURRENT_DATE - 3);    -- 6: mark just below 70: rejected

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INTEGER, p_income NUMERIC, p_mark NUMERIC)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN
        RAISE EXCEPTION 'Age, income and mark must not be NULL';
    END IF;
    IF p_age <= 0 THEN
        RAISE EXCEPTION 'Age must be positive (got %)', p_age;
    END IF;
    IF p_income < 0 THEN
        RAISE EXCEPTION 'Income must not be negative (got %)', p_income;
    END IF;
    IF p_mark < 0 OR p_mark > 100 THEN
        RAISE EXCEPTION 'Mark must be between 0 and 100 (got %)', p_mark;
    END IF;

    RETURN p_age BETWEEN 18 AND 25
       AND p_income <= 3000
       AND p_mark >= 70;
END;
$$;

-- =====================================================================
-- (c) Procedure
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_app applications%ROWTYPE;
BEGIN
    -- Lock the row so the same application cannot be assessed twice at once.
    SELECT * INTO v_app
    FROM applications
    WHERE application_id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application % does not exist', p_application_id;
    END IF;
    IF v_app.status <> 'PENDING' THEN
        RAISE EXCEPTION 'Application % was already assessed (status %)', p_application_id, v_app.status;
    END IF;

    UPDATE applications
    SET status = CASE
                   WHEN fn_scholarship_eligible(v_app.age_at_application,
                                                v_app.monthly_income,
                                                v_app.average_mark)
                   THEN 'APPROVED' ELSE 'REJECTED'
                 END
    WHERE application_id = p_application_id;
END;
$$;

-- =====================================================================
-- (d) Trigger: audit real status changes only
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_decision_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO decision_audit (application_id, old_status, new_status, changed_at)
    VALUES (OLD.application_id, OLD.status, NEW.status, now());
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_decision_audit
AFTER UPDATE ON applications
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION trg_fn_decision_audit();

-- Tests for (b): both sides of every boundary
SELECT fn_scholarship_eligible(18, 3000, 70)      AS all_minimum_boundaries,   -- true
       fn_scholarship_eligible(25, 2999.99, 70)   AS max_age,                  -- true
       fn_scholarship_eligible(17, 1000, 90)      AS too_young,                -- false
       fn_scholarship_eligible(26, 1000, 90)      AS too_old,                  -- false
       fn_scholarship_eligible(20, 3000.01, 90)   AS income_over,              -- false
       fn_scholarship_eligible(20, 1000, 69.99)   AS mark_under;               -- false
DO $$ BEGIN PERFORM fn_scholarship_eligible(NULL, 1000, 80);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (NULL): %', SQLERRM; END $$;
DO $$ BEGIN PERFORM fn_scholarship_eligible(20, -1, 80);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (negative income): %', SQLERRM; END $$;
DO $$ BEGIN PERFORM fn_scholarship_eligible(0, 1000, 80);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (age 0): %', SQLERRM; END $$;
DO $$ BEGIN PERFORM fn_scholarship_eligible(20, 1000, 101);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (mark 101): %', SQLERRM; END $$;

-- Tests for (c)
DO $$ BEGIN CALL pr_assess_application(999);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown): %', SQLERRM; END $$;
CALL pr_assess_application(1);                       -- PENDING -> APPROVED
DO $$ BEGIN CALL pr_assess_application(1);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (already assessed): %', SQLERRM; END $$;

-- Tests for (d)
SELECT * FROM decision_audit ORDER BY audit_id;      -- one row: application 1
UPDATE applications SET status = status WHERE application_id = 1;   -- unchanged status
SELECT COUNT(*) AS audit_rows FROM decision_audit;   -- still 1

-- =====================================================================
-- (e) View: APPROVED only, household income omitted
-- =====================================================================
CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number,
       s.full_name,
       a.average_mark,
       a.status
FROM applications a
JOIN students s ON s.student_id = a.student_id
WHERE a.status = 'APPROVED';

SELECT * FROM v_approved_applicants;

-- =====================================================================
-- (f) Index
-- Equality column (status) first, range column (submitted_on) second.
-- =====================================================================
CREATE INDEX idx_applications_status_submitted ON applications (status, submitted_on);

ANALYZE applications;
SET enable_seqscan = off;
EXPLAIN
SELECT application_id, student_id, submitted_on
FROM applications
WHERE status = 'PENDING'
  AND submitted_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: query FOR loop over PENDING applications only
-- Completed applications are never selected, so a rerun does nothing to them
-- and creates no duplicate audit rows.
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_assess_pending()
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT application_id
        FROM applications
        WHERE status = 'PENDING'
        ORDER BY application_id
    LOOP
        CALL pr_assess_application(rec.application_id);
    END LOOP;
END;
$$;

CALL pr_assess_pending();      -- assesses the five remaining PENDING applications
SELECT application_id, status FROM applications ORDER BY application_id;
-- expected: 1 APPROVED, 2 APPROVED, 3 APPROVED, 4 REJECTED, 5 REJECTED, 6 REJECTED
SELECT COUNT(*) AS audit_rows_after_first_run FROM decision_audit;     -- 6

CALL pr_assess_pending();      -- rerun: nothing PENDING, nothing changes
SELECT COUNT(*) AS audit_rows_after_rerun FROM decision_audit;         -- still 6

-- Schedule with pg_cron: every Monday at 08:00
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_assess_pending_weekly', '0 8 * * 1',
                     $$CALL pr_assess_pending()$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
