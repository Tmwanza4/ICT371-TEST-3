-- ICT371 Question 9: Farmer Cooperative Maize Deliveries (PostgreSQL)
-- Rates: grade A K5/kg, grade B K4/kg, grade C K3/kg.

DROP TABLE IF EXISTS daily_purchases, deliveries, farmers CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE farmers (
    farmer_id     SERIAL PRIMARY KEY,
    farmer_number VARCHAR(20)  NOT NULL UNIQUE,
    full_name     VARCHAR(100) NOT NULL
);

CREATE TABLE deliveries (
    delivery_id  SERIAL PRIMARY KEY,
    farmer_id    INTEGER       NOT NULL REFERENCES farmers(farmer_id),
    grade        CHAR(1)       NOT NULL CHECK (grade IN ('A', 'B', 'C')),
    weight_kg    NUMERIC(10,2) NOT NULL CHECK (weight_kg > 0),
    unit_rate    NUMERIC(10,2) NOT NULL,     -- filled in by the trigger
    total_value  NUMERIC(12,2) NOT NULL,     -- filled in by the trigger
    delivered_on DATE          NOT NULL,
    is_paid      BOOLEAN       NOT NULL DEFAULT FALSE
);

CREATE TABLE daily_purchases (
    purchase_date DATE PRIMARY KEY,
    total_weight  NUMERIC(12,2) NOT NULL,
    total_value   NUMERIC(14,2) NOT NULL
);

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    IF p_grade IS NULL THEN
        RAISE EXCEPTION 'Grade must not be NULL';
    END IF;

    v_rate := CASE p_grade WHEN 'A' THEN 5 WHEN 'B' THEN 4 WHEN 'C' THEN 3 END;

    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'Unsupported grade "%" (use A, B or C)', p_grade;
    END IF;

    RETURN v_rate;
END;
$$;

-- =====================================================================
-- (d) Trigger: one pricing rule for procedure AND direct SQL
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_delivery_pricing()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN
        RAISE EXCEPTION 'Weight must be greater than zero (got %)', NEW.weight_kg;
    END IF;

    NEW.unit_rate   := fn_maize_rate(NEW.grade);
    NEW.total_value := ROUND(NEW.weight_kg * NEW.unit_rate, 2);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_delivery_pricing
BEFORE INSERT OR UPDATE ON deliveries
FOR EACH ROW
EXECUTE FUNCTION trg_fn_delivery_pricing();

-- =====================================================================
-- (c) Procedure: inserts basic fields only; the trigger prices the delivery
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INTEGER, p_grade TEXT, p_weight NUMERIC, p_date DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM 1 FROM farmers WHERE farmer_id = p_farmer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown farmer_id %', p_farmer_id;
    END IF;

    PERFORM fn_maize_rate(p_grade);          -- rejects NULL / unsupported grade early

    IF p_weight IS NULL OR p_weight <= 0 THEN
        RAISE EXCEPTION 'Weight must be greater than zero (got %)', p_weight;
    END IF;
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Delivery date must not be NULL';
    END IF;

    INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on, is_paid)
    VALUES (p_farmer_id, p_grade, p_weight, p_date, FALSE);
END;
$$;

-- (a, continued) Seed data, loaded AFTER the trigger is installed.
INSERT INTO farmers (farmer_number, full_name) VALUES
    ('F001', 'Chanda Mulenga'),
    ('F002', 'Mwila Banda'),
    ('F003', 'Temba Phiri');       -- will have no unpaid deliveries

-- Direct SQL with only the basic fields: the trigger supplies unit_rate and
-- total_value before the NOT NULL checks run.
INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on, is_paid) VALUES
    (1, 'A', 100.00, CURRENT_DATE - 2, TRUE),
    (1, 'B',  80.50, CURRENT_DATE - 1, FALSE),
    (2, 'C', 200.00, CURRENT_DATE - 1, FALSE),
    (2, 'A',  50.00, CURRENT_DATE - 1, TRUE),
    (3, 'B', 120.00, CURRENT_DATE - 2, TRUE);
-- Sixth delivery through the procedure (is_paid starts FALSE)
CALL pr_receive_delivery(1, 'C', 40.00, CURRENT_DATE);

SELECT * FROM deliveries ORDER BY delivery_id;
-- expected values: 500.00, 322.00, 600.00, 250.00, 480.00, 120.00

-- Tests for (b)
SELECT fn_maize_rate('A') AS a, fn_maize_rate('B') AS b, fn_maize_rate('C') AS c;
DO $$ BEGIN PERFORM fn_maize_rate(NULL);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (NULL): %', SQLERRM; END $$;
DO $$ BEGIN PERFORM fn_maize_rate('D');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (grade D): %', SQLERRM; END $$;

-- Tests for (c)
DO $$ BEGIN CALL pr_receive_delivery(99, 'A', 10, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown farmer): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_delivery(1, 'A', -5, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (negative weight): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_delivery(1, 'X', 5, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (bad grade): %', SQLERRM; END $$;

-- Tests for (d): the trigger also fixes wrong values from direct SQL
INSERT INTO deliveries (farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on)
VALUES (2, 'B', 10, 999, 999, CURRENT_DATE - 5);          -- bogus rate/value supplied
SELECT delivery_id, unit_rate, total_value FROM deliveries ORDER BY delivery_id DESC LIMIT 1;  -- 4.00, 40.00
UPDATE deliveries SET grade = 'A' WHERE delivery_id = 7;   -- re-priced on UPDATE
SELECT delivery_id, unit_rate, total_value FROM deliveries WHERE delivery_id = 7;              -- 5.00, 50.00
DO $$ BEGIN INSERT INTO deliveries (farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on)
            VALUES (2, 'A', 0, 0, 0, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (zero weight): %', SQLERRM; END $$;
DELETE FROM deliveries WHERE delivery_id = 7;              -- remove the test row

-- =====================================================================
-- (e) View: farmers with no unpaid deliveries show 0
-- =====================================================================
CREATE OR REPLACE VIEW v_farmer_amount_due AS
SELECT f.farmer_number,
       f.full_name,
       COALESCE(SUM(d.total_value) FILTER (WHERE NOT d.is_paid), 0) AS total_unpaid
FROM farmers f
LEFT JOIN deliveries d ON d.farmer_id = f.farmer_id
GROUP BY f.farmer_id, f.farmer_number, f.full_name;

SELECT * FROM v_farmer_amount_due ORDER BY farmer_number;   -- 442.00, 600.00, 0

-- =====================================================================
-- (f) Index
-- farmer_id (equality) first, delivered_on (range) second.
-- =====================================================================
CREATE INDEX idx_deliveries_farmer_date ON deliveries (farmer_id, delivered_on);

ANALYZE deliveries;
SET enable_seqscan = off;
EXPLAIN
SELECT delivery_id, grade, weight_kg, total_value
FROM deliveries
WHERE farmer_id = 1
  AND delivered_on BETWEEN CURRENT_DATE - 7 AND CURRENT_DATE;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: replaces the day's totals, never adds to them
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO daily_purchases (purchase_date, total_weight, total_value)
    SELECT p_day, COALESCE(SUM(weight_kg), 0), COALESCE(SUM(total_value), 0)
    FROM deliveries
    WHERE delivered_on = p_day
    ON CONFLICT (purchase_date) DO UPDATE
    SET total_weight = EXCLUDED.total_weight,
        total_value  = EXCLUDED.total_value;
END;
$$;

CALL pr_refresh_purchases(CURRENT_DATE - 1);
CALL pr_refresh_purchases(CURRENT_DATE - 1);     -- same result on rerun
SELECT * FROM daily_purchases;

-- Schedule with pg_cron: daily at 01:30 for the previous day
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_purchases_daily', '30 1 * * *',
                     $$CALL pr_refresh_purchases(CURRENT_DATE - 1)$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
