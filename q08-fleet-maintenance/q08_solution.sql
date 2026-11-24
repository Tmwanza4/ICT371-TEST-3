-- ICT371 Question 8: Transport Fleet Maintenance (PostgreSQL)
-- Service is due when current_odometer - last_service_odometer >= 5000 km.

DROP TABLE IF EXISTS service_alerts, trips, vehicles CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE vehicles (
    vehicle_id            SERIAL PRIMARY KEY,
    registration          VARCHAR(15) NOT NULL UNIQUE,
    current_odometer      INTEGER     NOT NULL CHECK (current_odometer >= 0),
    last_service_odometer INTEGER     NOT NULL CHECK (last_service_odometer >= 0),
    CONSTRAINT ck_service_not_ahead CHECK (last_service_odometer <= current_odometer)
);

CREATE TABLE trips (
    trip_id        SERIAL PRIMARY KEY,
    vehicle_id     INTEGER NOT NULL REFERENCES vehicles(vehicle_id),
    trip_on        DATE    NOT NULL,
    start_odometer INTEGER NOT NULL CHECK (start_odometer >= 0),
    end_odometer   INTEGER NOT NULL CHECK (end_odometer >= 0)
);

CREATE TABLE service_alerts (
    vehicle_id       INTEGER PRIMARY KEY REFERENCES vehicles(vehicle_id),
    km_since_service INTEGER NOT NULL,
    flagged_on       DATE    NOT NULL
);

-- Three vehicles in different service positions
INSERT INTO vehicles (registration, current_odometer, last_service_odometer) VALUES
    ('ABC 1001 ZM', 12000,  8000),    -- 4,000 km since service: not due
    ('ABC 1002 ZM', 20000, 14000),    -- 6,000 km since service: due
    ('ABC 1003 ZM',  5000,     0);    -- exactly 5,000 km: due (rule is "at least")

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_current INTEGER;
    v_last    INTEGER;
BEGIN
    SELECT current_odometer, last_service_odometer INTO v_current, v_last
    FROM vehicles
    WHERE vehicle_id = p_vehicle_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown vehicle_id %', p_vehicle_id;
    END IF;

    RETURN (v_current - v_last) >= 5000;
END;
$$;

-- =====================================================================
-- (d) Trigger: validates the trip and moves the odometer exactly once
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_trip_odometer()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_current INTEGER;
BEGIN
    IF NEW.start_odometer IS NULL OR NEW.end_odometer IS NULL
       OR NEW.end_odometer <= NEW.start_odometer THEN
        RAISE EXCEPTION 'Invalid mileage: end (%) must be greater than start (%)',
            NEW.end_odometer, NEW.start_odometer;
    END IF;

    -- Lock the vehicle row so two simultaneous trips cannot both start at the same value.
    SELECT current_odometer INTO v_current
    FROM vehicles
    WHERE vehicle_id = NEW.vehicle_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown vehicle_id %', NEW.vehicle_id;
    END IF;

    IF NEW.start_odometer <> v_current THEN
        RAISE EXCEPTION 'Trip must start at the current odometer (%), but starts at %',
            v_current, NEW.start_odometer;
    END IF;

    UPDATE vehicles
    SET current_odometer = NEW.end_odometer
    WHERE vehicle_id = NEW.vehicle_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_trip_odometer
BEFORE INSERT ON trips
FOR EACH ROW
EXECUTE FUNCTION trg_fn_trip_odometer();

-- =====================================================================
-- (c) Procedure: does NOT touch the vehicle odometer (the trigger does)
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INTEGER, p_trip_on DATE, p_start INTEGER, p_end INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM 1 FROM vehicles WHERE vehicle_id = p_vehicle_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown vehicle_id %', p_vehicle_id;
    END IF;

    IF p_trip_on IS NULL OR p_start IS NULL OR p_end IS NULL THEN
        RAISE EXCEPTION 'Trip date, start and end odometer must not be NULL';
    END IF;
    IF p_end <= p_start THEN
        RAISE EXCEPTION 'end_odometer (%) must be greater than start_odometer (%)', p_end, p_start;
    END IF;

    INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer)
    VALUES (p_vehicle_id, p_trip_on, p_start, p_end);
END;
$$;

-- (a, continued) Six trips through the procedure, after the trigger exists
CALL pr_record_trip(1, CURRENT_DATE - 6, 12000, 12400);
CALL pr_record_trip(1, CURRENT_DATE - 5, 12400, 12900);
CALL pr_record_trip(2, CURRENT_DATE - 4, 20000, 20500);
CALL pr_record_trip(2, CURRENT_DATE - 3, 20500, 21000);
CALL pr_record_trip(3, CURRENT_DATE - 2,  5000,  5300);
CALL pr_record_trip(3, CURRENT_DATE - 1,  5300,  5800);

SELECT * FROM trips ORDER BY trip_id;
SELECT * FROM vehicles ORDER BY vehicle_id;    -- odometers: 12900, 21000, 5800

-- Tests for (b)
SELECT vehicle_id, fn_service_due(vehicle_id) AS due FROM vehicles ORDER BY vehicle_id;  -- f, t, t
DO $$ BEGIN PERFORM fn_service_due(999);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error: %', SQLERRM; END $$;

-- Tests for (c) and (d)
DO $$ BEGIN CALL pr_record_trip(1, CURRENT_DATE, 12900, 12900);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (end not greater): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_record_trip(1, CURRENT_DATE, 100, 200);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (wrong start): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_record_trip(999, CURRENT_DATE, 1, 2);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown vehicle): %', SQLERRM; END $$;
DO $$ BEGIN INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer)
            VALUES (1, CURRENT_DATE, 12900, 12000);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (direct SQL, bad mileage): %', SQLERRM; END $$;
SELECT vehicle_id, current_odometer FROM vehicles ORDER BY vehicle_id;   -- unchanged after failures

-- =====================================================================
-- (e) View
-- =====================================================================
CREATE OR REPLACE VIEW v_service_due AS
SELECT registration,
       current_odometer - last_service_odometer AS km_since_service
FROM vehicles
WHERE current_odometer - last_service_odometer >= 5000;

SELECT * FROM v_service_due ORDER BY registration;     -- vehicles 2 and 3

-- =====================================================================
-- (f) Index
-- Equality on vehicle_id first, range on trip_on second, so one vehicle's
-- trips within a date range come from one contiguous slice of the index.
-- =====================================================================
CREATE INDEX idx_trips_vehicle_trip_on ON trips (vehicle_id, trip_on);

ANALYZE trips;
SET enable_seqscan = off;
EXPLAIN
SELECT trip_id, trip_on, start_odometer, end_odometer
FROM trips
WHERE vehicle_id = 2
  AND trip_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: insert/update an alert per due vehicle, remove stale ones
-- flagged_on keeps the date the vehicle was FIRST flagged.
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO service_alerts (vehicle_id, km_since_service, flagged_on)
    SELECT vehicle_id, current_odometer - last_service_odometer, CURRENT_DATE
    FROM vehicles
    WHERE fn_service_due(vehicle_id)
    ON CONFLICT (vehicle_id) DO UPDATE
    SET km_since_service = EXCLUDED.km_since_service;

    DELETE FROM service_alerts sa
    WHERE NOT fn_service_due(sa.vehicle_id);      -- serviced vehicles lose their alert
END;
$$;

CALL pr_refresh_service_alerts();
CALL pr_refresh_service_alerts();                 -- rerun: still one row per vehicle
SELECT * FROM service_alerts ORDER BY vehicle_id; -- vehicles 2 and 3

-- Vehicle 2 gets serviced: the next run removes its alert
UPDATE vehicles SET last_service_odometer = current_odometer WHERE vehicle_id = 2;
CALL pr_refresh_service_alerts();
SELECT * FROM service_alerts ORDER BY vehicle_id; -- only vehicle 3 remains

-- Schedule with pg_cron: every Monday at 06:00
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_service_alerts_weekly', '0 6 * * 1',
                     $$CALL pr_refresh_service_alerts()$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
