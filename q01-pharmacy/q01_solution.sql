-- ICT371 Question 1: Pharmacy Stock and Daily Sales (PostgreSQL)
-- Run this file top to bottom in an empty database.

DROP TABLE IF EXISTS daily_sales, stock_audit, sales, medicines CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE medicines (
    medicine_id   SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100)  NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    stock_qty     INTEGER       NOT NULL CHECK (stock_qty >= 0)
);

CREATE TABLE sales (
    sale_id     SERIAL PRIMARY KEY,
    medicine_id INTEGER       NOT NULL REFERENCES medicines(medicine_id),
    quantity    INTEGER       NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    sold_on     DATE          NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE stock_audit (
    audit_id    SERIAL PRIMARY KEY,
    medicine_id INTEGER   NOT NULL REFERENCES medicines(medicine_id),
    old_qty     INTEGER   NOT NULL,
    new_qty     INTEGER   NOT NULL,
    changed_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE daily_sales (
    sales_date   DATE PRIMARY KEY,
    total_qty    INTEGER       NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL
);

-- Seed medicines (the six sales are loaded through pr_record_sale further down,
-- after the function, procedure and trigger exist).
INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES
    ('Paracetamol 500mg', 2.50, 100),
    ('Amoxicillin 250mg', 8.00,  30),
    ('ORS Sachet',        3.00,  12);

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INTEGER, p_quantity INTEGER)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_price NUMERIC;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be a positive number (got %)', p_quantity;
    END IF;

    SELECT unit_price INTO v_price
    FROM medicines
    WHERE medicine_id = p_medicine_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown medicine_id %', p_medicine_id;
    END IF;

    RETURN v_price * p_quantity;
END;
$$;

-- =====================================================================
-- (c) Procedure
-- A procedure runs as one transaction: if any RAISE EXCEPTION happens,
-- nothing is written to sales or medicines.
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INTEGER, p_quantity INTEGER, p_sold_on DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_price NUMERIC;
    v_stock INTEGER;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be a positive number (got %)', p_quantity;
    END IF;
    IF p_sold_on IS NULL THEN
        RAISE EXCEPTION 'Sale date must not be NULL';
    END IF;

    -- Lock the medicine row so two simultaneous sales cannot oversell.
    SELECT unit_price, stock_qty INTO v_price, v_stock
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown medicine_id %', p_medicine_id;
    END IF;

    IF v_stock < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for medicine %: available %, requested %',
            p_medicine_id, v_stock, p_quantity;
    END IF;

    -- Store the CURRENT price in the sale, then deduct stock exactly once.
    INSERT INTO sales (medicine_id, quantity, unit_price, sold_on)
    VALUES (p_medicine_id, p_quantity, v_price, p_sold_on);

    UPDATE medicines
    SET stock_qty = stock_qty - p_quantity
    WHERE medicine_id = p_medicine_id;
END;
$$;

-- =====================================================================
-- (d) Trigger: audit stock changes (only when stock_qty really changes)
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_medicine_stock_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO stock_audit (medicine_id, old_qty, new_qty)
    VALUES (OLD.medicine_id, OLD.stock_qty, NEW.stock_qty);
    RETURN NULL;   -- return value is ignored for AFTER row triggers
END;
$$;

CREATE TRIGGER trg_medicine_stock_audit
AFTER UPDATE ON medicines
FOR EACH ROW
WHEN (OLD.stock_qty IS DISTINCT FROM NEW.stock_qty)
EXECUTE FUNCTION trg_fn_medicine_stock_audit();

-- =====================================================================
-- (a, continued) Load six valid sales THROUGH the procedure
-- =====================================================================
CALL pr_record_sale(1, 10, CURRENT_DATE - 2);
CALL pr_record_sale(1,  5, CURRENT_DATE - 1);
CALL pr_record_sale(2,  4, CURRENT_DATE - 1);
CALL pr_record_sale(2,  6, CURRENT_DATE);
CALL pr_record_sale(3,  2, CURRENT_DATE - 1);
CALL pr_record_sale(3,  3, CURRENT_DATE);

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM sales ORDER BY sale_id;

-- Tests for (b): valid call, then the two rejected calls
SELECT fn_sale_value(2, 3) AS value_of_3_amoxicillin;   -- 24.00
DO $$ BEGIN PERFORM fn_sale_value(999, 1);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown medicine): %', SQLERRM; END $$;
DO $$ BEGIN PERFORM fn_sale_value(1, 0);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (bad quantity): %', SQLERRM; END $$;

-- Test for (c): an oversell must change nothing
SELECT stock_qty AS stock_before FROM medicines WHERE medicine_id = 1;
DO $$ BEGIN CALL pr_record_sale(1, 9999, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (oversell): %', SQLERRM; END $$;
SELECT stock_qty AS stock_after_failed_sale FROM medicines WHERE medicine_id = 1;  -- unchanged
SELECT count(*) AS sales_rows FROM sales;                                          -- still 6

-- Test for (d): audit rows exist, and a no-change update adds nothing
SELECT * FROM stock_audit ORDER BY audit_id;
UPDATE medicines SET stock_qty = stock_qty WHERE medicine_id = 1;   -- no real change
SELECT count(*) AS audit_rows_unchanged FROM stock_audit;

-- =====================================================================
-- (e) View
-- =====================================================================
CREATE OR REPLACE VIEW v_low_stock AS
SELECT medicine_id,
       medicine_name,
       unit_price,
       stock_qty AS remaining_stock
FROM medicines
WHERE stock_qty < 10;

-- Query the view after a sale
CALL pr_record_sale(3, 1, CURRENT_DATE);   -- ORS drops from 7 to 6
SELECT * FROM v_low_stock;

-- =====================================================================
-- (f) Index
-- One medicine + a sold_on range: equality column first (medicine_id),
-- range column second (sold_on), so one index scan finds exactly the rows.
-- =====================================================================
CREATE INDEX idx_sales_medicine_sold_on ON sales (medicine_id, sold_on);

ANALYZE sales;
SET enable_seqscan = off;   -- the table is tiny, so force the planner to show the index
EXPLAIN
SELECT sale_id, quantity, unit_price, sold_on
FROM sales
WHERE medicine_id = 1
  AND sold_on BETWEEN CURRENT_DATE - 7 AND CURRENT_DATE;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job
-- Replaces the day's row, so a rerun never duplicates or double-counts.
-- A day with no sales is stored as 0 / 0.
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO daily_sales (sales_date, total_qty, total_amount)
    SELECT p_day,
           COALESCE(SUM(quantity), 0),
           COALESCE(SUM(quantity * unit_price), 0)
    FROM sales
    WHERE sold_on = p_day
    ON CONFLICT (sales_date) DO UPDATE
    SET total_qty    = EXCLUDED.total_qty,
        total_amount = EXCLUDED.total_amount;
END;
$$;

-- Rerun test: both calls leave the same single row
CALL pr_refresh_sales(CURRENT_DATE - 1);
CALL pr_refresh_sales(CURRENT_DATE - 1);
SELECT * FROM daily_sales;

-- Schedule with pg_cron: daily at 00:15 for the previous day
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_sales_daily', '15 0 * * *',
                     $$CALL pr_refresh_sales(CURRENT_DATE - 1)$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
