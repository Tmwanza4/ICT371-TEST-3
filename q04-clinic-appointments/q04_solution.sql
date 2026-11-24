-- ICT371 Question 4: Clinic Appointment Scheduling (PostgreSQL)

DROP TABLE IF EXISTS clinic_summary, appointments, doctors, patients CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE patients (
    patient_id SERIAL PRIMARY KEY,
    full_name  VARCHAR(100) NOT NULL
);

CREATE TABLE doctors (
    doctor_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE appointments (
    appointment_id  SERIAL PRIMARY KEY,
    patient_id      INTEGER     NOT NULL REFERENCES patients(patient_id),
    doctor_id       INTEGER     NOT NULL REFERENCES doctors(doctor_id),
    appointment_day DATE        NOT NULL,
    slot_time       TIME        NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'BOOKED',
    CONSTRAINT ck_status CHECK (status IN ('BOOKED', 'ATTENDED', 'CANCELLED')),
    CONSTRAINT ck_slot   CHECK (slot_time IN ('09:00', '10:00', '11:00', '12:00'))
);

CREATE TABLE clinic_summary (
    summary_date    DATE PRIMARY KEY,
    booked_count    INTEGER NOT NULL,
    attended_count  INTEGER NOT NULL,
    cancelled_count INTEGER NOT NULL
);

INSERT INTO patients (full_name) VALUES ('Chanda Mulenga'), ('Mwila Banda'), ('Temba Phiri');
INSERT INTO doctors  (full_name) VALUES ('Dr. Zulu'), ('Dr. Tembo'), ('Dr. Lungu');

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id INTEGER, p_day DATE)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    PERFORM 1 FROM doctors WHERE doctor_id = p_doctor_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown doctor_id %', p_doctor_id;
    END IF;

    SELECT COUNT(*) INTO v_count          -- COUNT returns 0 when there are no rows
    FROM appointments
    WHERE doctor_id = p_doctor_id
      AND appointment_day = p_day
      AND status <> 'CANCELLED';

    RETURN v_count;
END;
$$;

-- =====================================================================
-- (d) Trigger (created before the procedure and the seed appointments)
-- Rejects a clash with another non-cancelled appointment.
-- On UPDATE the row being changed is excluded from the clash search.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_check_slot_clash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status <> 'CANCELLED' THEN
        IF EXISTS (
            SELECT 1
            FROM appointments a
            WHERE a.doctor_id       = NEW.doctor_id
              AND a.appointment_day = NEW.appointment_day
              AND a.slot_time       = NEW.slot_time
              AND a.status         <> 'CANCELLED'
              AND a.appointment_id IS DISTINCT FROM NEW.appointment_id   -- exclude itself on UPDATE
        ) THEN
            RAISE EXCEPTION 'Doctor % already has an appointment on % at %',
                NEW.doctor_id, NEW.appointment_day, NEW.slot_time;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_slot_clash
BEFORE INSERT OR UPDATE ON appointments
FOR EACH ROW
EXECUTE FUNCTION trg_fn_check_slot_clash();

-- =====================================================================
-- (c) Procedure
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_book_appointment(p_patient_id INTEGER, p_doctor_id INTEGER,
                                                p_day DATE, p_slot TIME)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM 1 FROM patients WHERE patient_id = p_patient_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown patient_id %', p_patient_id;
    END IF;

    PERFORM 1 FROM doctors WHERE doctor_id = p_doctor_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown doctor_id %', p_doctor_id;
    END IF;

    IF p_day IS NULL OR p_day < CURRENT_DATE THEN
        RAISE EXCEPTION 'Appointment date must not be in the past (got %)', p_day;
    END IF;

    IF p_slot IS NULL OR p_slot NOT IN ('09:00', '10:00', '11:00', '12:00') THEN
        RAISE EXCEPTION 'Unsupported slot % (use 09:00, 10:00, 11:00 or 12:00)', p_slot;
    END IF;

    -- The trigger rejects a clash with another non-cancelled appointment.
    INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status)
    VALUES (p_patient_id, p_doctor_id, p_day, p_slot, 'BOOKED');
END;
$$;

-- (a, continued) Six appointments, none breaking the slot rule.
-- Past ones are inserted directly (the procedure refuses past dates).
INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES
    (1, 1, CURRENT_DATE - 1, '09:00', 'ATTENDED'),
    (2, 1, CURRENT_DATE - 1, '10:00', 'CANCELLED'),
    (3, 2, CURRENT_DATE - 1, '09:00', 'ATTENDED');
CALL pr_book_appointment(1, 1, CURRENT_DATE, '09:00');
CALL pr_book_appointment(2, 2, CURRENT_DATE, '10:00');
CALL pr_book_appointment(3, 1, CURRENT_DATE + 1, '11:00');

SELECT * FROM appointments ORDER BY appointment_id;

-- Tests for (b)
SELECT fn_daily_load(1, CURRENT_DATE - 1) AS doctor1_yesterday;     -- 1 (cancelled one not counted)
SELECT fn_daily_load(3, CURRENT_DATE)     AS doctor3_today_no_bookings;   -- 0
DO $$ BEGIN PERFORM fn_daily_load(999, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error: %', SQLERRM; END $$;

-- Tests for (c) and (d)
DO $$ BEGIN CALL pr_book_appointment(1, 1, CURRENT_DATE, '09:00');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (clash): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_book_appointment(1, 1, CURRENT_DATE - 1, '11:00');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (past date): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_book_appointment(1, 1, CURRENT_DATE + 2, '13:00');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (bad slot): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_book_appointment(99, 1, CURRENT_DATE + 2, '09:00');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown patient): %', SQLERRM; END $$;
-- UPDATE of a row to itself must NOT clash with itself:
UPDATE appointments SET status = 'ATTENDED' WHERE appointment_id = 4;
-- A cancelled slot can be rebooked:
UPDATE appointments SET status = 'CANCELLED' WHERE appointment_id = 5;
CALL pr_book_appointment(1, 2, CURRENT_DATE, '10:00');
-- Un-cancelling into an occupied slot must be rejected on UPDATE:
DO $$ BEGIN UPDATE appointments SET status = 'BOOKED' WHERE appointment_id = 5;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (update clash): %', SQLERRM; END $$;

-- =====================================================================
-- (e) View: only today's BOOKED appointments, no unrelated patient data
-- =====================================================================
CREATE OR REPLACE VIEW v_today_appointments AS
SELECT p.full_name AS patient_name,
       d.full_name AS doctor_name,
       a.slot_time
FROM appointments a
JOIN patients p ON p.patient_id = a.patient_id
JOIN doctors  d ON d.doctor_id  = a.doctor_id
WHERE a.appointment_day = CURRENT_DATE
  AND a.status = 'BOOKED';

SELECT * FROM v_today_appointments ORDER BY slot_time;

-- =====================================================================
-- (f) Index
-- Non-unique composite index. appointment_day first (the date filter is the
-- most selective for a day's schedule), then doctor_id, so "this doctor on
-- this day" is a direct index lookup.
-- =====================================================================
CREATE INDEX idx_appointments_day_doctor ON appointments (appointment_day, doctor_id);

ANALYZE appointments;
SET enable_seqscan = off;
EXPLAIN
SELECT appointment_id, patient_id, slot_time, status
FROM appointments
WHERE appointment_day = CURRENT_DATE
  AND doctor_id = 1;
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO clinic_summary (summary_date, booked_count, attended_count, cancelled_count)
    SELECT p_day,
           COUNT(*) FILTER (WHERE status = 'BOOKED'),
           COUNT(*) FILTER (WHERE status = 'ATTENDED'),
           COUNT(*) FILTER (WHERE status = 'CANCELLED')
    FROM appointments
    WHERE appointment_day = p_day
    ON CONFLICT (summary_date) DO UPDATE
    SET booked_count    = EXCLUDED.booked_count,
        attended_count  = EXCLUDED.attended_count,
        cancelled_count = EXCLUDED.cancelled_count;
END;
$$;

CALL pr_refresh_clinic_summary(CURRENT_DATE - 1);
CALL pr_refresh_clinic_summary(CURRENT_DATE - 1);    -- rerun replaces the row
SELECT * FROM clinic_summary;

-- Schedule with pg_cron: daily at 01:00 for the previous day
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_clinic_summary_daily', '0 1 * * *',
                     $$CALL pr_refresh_clinic_summary(CURRENT_DATE - 1)$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
