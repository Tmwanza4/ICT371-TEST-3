-- ICT371 Question 3: Library Returns and Overdue Fines (PostgreSQL)
-- Fine rule: K2 per day after due_on. Returning ON the due date = no fine.

DROP TABLE IF EXISTS overdue_summary, loan_audit, loans, books CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title   VARCHAR(150) NOT NULL
);

CREATE TABLE loans (
    loan_id       SERIAL PRIMARY KEY,
    book_id       INTEGER       NOT NULL REFERENCES books(book_id),
    borrower_name VARCHAR(100)  NOT NULL,
    borrowed_on   DATE          NOT NULL,
    due_on        DATE          NOT NULL,
    returned_on   DATE          NULL,
    fine_amount   NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (fine_amount >= 0),
    CONSTRAINT ck_due_after_borrowed CHECK (due_on >= borrowed_on)
);

CREATE TABLE loan_audit (
    audit_id         SERIAL PRIMARY KEY,
    loan_id          INTEGER   NOT NULL REFERENCES loans(loan_id),
    old_returned_on  DATE      NULL,
    new_returned_on  DATE      NULL,
    changed_at       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE overdue_summary (
    snapshot_date DATE PRIMARY KEY,
    overdue_count INTEGER       NOT NULL,
    total_fine    NUMERIC(12,2) NOT NULL
);

INSERT INTO books (title) VALUES
    ('Database System Concepts'),
    ('Clean Code'),
    ('Introduction to Algorithms');

-- Six loans, all inserted open; the returned ones are closed through
-- pr_return_loan below (after the trigger is installed).
INSERT INTO loans (book_id, borrower_name, borrowed_on, due_on) VALUES
    (1, 'Chanda Mulenga', CURRENT_DATE - 30, CURRENT_DATE - 16),  -- 1: open, overdue 16 days
    (2, 'Mwila Banda',    CURRENT_DATE - 20, CURRENT_DATE - 6),   -- 2: open, overdue 6 days
    (3, 'Temba Phiri',    CURRENT_DATE - 5,  CURRENT_DATE + 9),   -- 3: open, on time (not due yet)
    (1, 'Natasha Zulu',   CURRENT_DATE - 40, CURRENT_DATE - 26),  -- 4: will be returned late
    (2, 'Bwalya Tembo',   CURRENT_DATE - 25, CURRENT_DATE - 11),  -- 5: will be returned on time
    (3, 'Kabwe Lungu',    CURRENT_DATE - 28, CURRENT_DATE - 14);  -- 6: will be returned ON the due date

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id INTEGER, p_as_of DATE)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_due      DATE;
    v_returned DATE;
    v_end      DATE;
BEGIN
    IF p_as_of IS NULL THEN
        RAISE EXCEPTION 'p_as_of must not be NULL';
    END IF;

    SELECT due_on, returned_on INTO v_due, v_returned
    FROM loans
    WHERE loan_id = p_loan_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown loan_id %', p_loan_id;
    END IF;

    -- A returned loan stops accumulating fines: use the earlier date.
    IF v_returned IS NOT NULL THEN
        v_end := LEAST(p_as_of, v_returned);
    ELSE
        v_end := p_as_of;
    END IF;

    RETURN 2 * GREATEST(v_end - v_due, 0);
END;
$$;

-- =====================================================================
-- (c) Procedure: store the return date and final fine together
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id INTEGER, p_returned_on DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_borrowed DATE;
    v_returned DATE;
    v_fine     NUMERIC;
BEGIN
    SELECT borrowed_on, returned_on INTO v_borrowed, v_returned
    FROM loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown loan_id %', p_loan_id;
    END IF;
    IF v_returned IS NOT NULL THEN
        RAISE EXCEPTION 'Loan % was already returned on %', p_loan_id, v_returned;
    END IF;
    IF p_returned_on IS NULL THEN
        RAISE EXCEPTION 'Return date must not be NULL';
    END IF;
    IF p_returned_on < v_borrowed THEN
        RAISE EXCEPTION 'Return date % is before the borrow date %', p_returned_on, v_borrowed;
    END IF;

    -- returned_on is still NULL here, so the function measures up to p_returned_on.
    v_fine := fn_loan_fine(p_loan_id, p_returned_on);

    UPDATE loans
    SET returned_on = p_returned_on,
        fine_amount = v_fine
    WHERE loan_id = p_loan_id;
END;
$$;

-- =====================================================================
-- (d) Trigger: log changes to returned_on
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_loan_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO loan_audit (loan_id, old_returned_on, new_returned_on)
    VALUES (OLD.loan_id, OLD.returned_on, NEW.returned_on);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_loan_audit
AFTER UPDATE ON loans
FOR EACH ROW
WHEN (OLD.returned_on IS DISTINCT FROM NEW.returned_on)
EXECUTE FUNCTION trg_fn_loan_audit();

-- (a, continued) Close the three returned loans through the procedure
CALL pr_return_loan(4, CURRENT_DATE - 20);   -- 6 days late  -> K12
CALL pr_return_loan(5, CURRENT_DATE - 15);   -- early        -> K0
CALL pr_return_loan(6, CURRENT_DATE - 14);   -- on due date  -> K0

SELECT * FROM loans ORDER BY loan_id;
SELECT * FROM loan_audit ORDER BY audit_id;

-- Tests for (b)
SELECT loan_id, fn_loan_fine(loan_id, CURRENT_DATE) AS fine_today FROM loans ORDER BY loan_id;
-- expected: 32, 12, 0, 12, 0, 0  (returned loans stop growing)
DO $$ BEGIN PERFORM fn_loan_fine(999, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error: %', SQLERRM; END $$;

-- Tests for (c) and (d)
DO $$ BEGIN CALL pr_return_loan(999, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_return_loan(4, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (already returned): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_return_loan(1, CURRENT_DATE - 60);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (before borrowed_on): %', SQLERRM; END $$;
UPDATE loans SET returned_on = returned_on WHERE loan_id = 4;    -- unchanged date
SELECT count(*) AS audit_rows FROM loan_audit;                    -- still 3

-- =====================================================================
-- (e) View
-- =====================================================================
CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT l.loan_id,
       b.title,
       l.borrower_name,
       l.due_on,
       fn_loan_fine(l.loan_id, CURRENT_DATE) AS fine_as_of_today
FROM loans l
JOIN books b ON b.book_id = l.book_id
WHERE l.returned_on IS NULL
  AND l.due_on < CURRENT_DATE;

SELECT * FROM v_overdue_loans;

-- =====================================================================
-- (f) Index
-- Partial index: only unreturned loans are indexed. Returned loans are the
-- majority over time, so the index stays small and fast for this search.
-- =====================================================================
CREATE INDEX idx_loans_unreturned_by_book ON loans (book_id) WHERE returned_on IS NULL;

ANALYZE loans;
SET enable_seqscan = off;
EXPLAIN
SELECT loan_id, borrower_name, due_on
FROM loans
WHERE book_id = 1
  AND returned_on IS NULL;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: snapshot of loans still unreturned (and overdue) as of a date
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO overdue_summary (snapshot_date, overdue_count, total_fine)
    SELECT p_as_of,
           COUNT(*),
           COALESCE(SUM(fn_loan_fine(loan_id, p_as_of)), 0)
    FROM loans
    WHERE borrowed_on <= p_as_of
      AND (returned_on IS NULL OR returned_on > p_as_of)   -- still out on that date
      AND due_on < p_as_of                                 -- and past its due date
    ON CONFLICT (snapshot_date) DO UPDATE
    SET overdue_count = EXCLUDED.overdue_count,
        total_fine    = EXCLUDED.total_fine;
END;
$$;

CALL pr_refresh_overdue(CURRENT_DATE);
CALL pr_refresh_overdue(CURRENT_DATE);   -- rerun replaces the same snapshot_date
SELECT * FROM overdue_summary;           -- expected: 2 loans, K44

-- Schedule with pg_cron: daily at 00:10 for CURRENT_DATE
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_overdue_daily', '10 0 * * *',
                     $$CALL pr_refresh_overdue(CURRENT_DATE)$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
