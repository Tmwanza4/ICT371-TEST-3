-- ICT371 Question 5: Hostel Room Allocation (PostgreSQL)

DROP TABLE IF EXISTS occupancy_snapshot, allocations, rooms, students CASCADE;

-- =====================================================================
-- (a) Database and seed data
-- =====================================================================
CREATE TABLE students (
    student_id     SERIAL PRIMARY KEY,
    student_number VARCHAR(20)  NOT NULL UNIQUE,
    full_name      VARCHAR(100) NOT NULL
);

CREATE TABLE rooms (
    room_id     SERIAL PRIMARY KEY,
    room_number VARCHAR(10) NOT NULL UNIQUE,
    capacity    INTEGER     NOT NULL CHECK (capacity > 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_id    INTEGER     NOT NULL REFERENCES students(student_id),
    room_id       INTEGER     NOT NULL REFERENCES rooms(room_id),
    allocated_on  DATE        NOT NULL,
    released_on   DATE        NULL,
    status        VARCHAR(10) NOT NULL,
    CONSTRAINT ck_alloc_status CHECK (status IN ('ACTIVE', 'ENDED')),
    -- ACTIVE requires released_on NULL; ENDED requires a release date
    CONSTRAINT ck_alloc_release CHECK (
        (status = 'ACTIVE' AND released_on IS NULL) OR
        (status = 'ENDED'  AND released_on IS NOT NULL)
    )
);

CREATE TABLE occupancy_snapshot (
    snapshot_date DATE    NOT NULL,
    room_id       INTEGER NOT NULL REFERENCES rooms(room_id),
    occupied_beds INTEGER NOT NULL,
    free_beds     INTEGER NOT NULL,
    PRIMARY KEY (snapshot_date, room_id)
);

INSERT INTO students (student_number, full_name) VALUES
    ('202405001', 'Chanda Mulenga'),
    ('202405002', 'Mwila Banda'),
    ('202405003', 'Temba Phiri'),
    ('202405004', 'Natasha Zulu'),
    ('202405005', 'Bwalya Tembo'),
    ('202405006', 'Kabwe Lungu');

INSERT INTO rooms (room_number, capacity) VALUES
    ('A101', 2),    -- will be FULL
    ('A102', 3),    -- will be PARTLY occupied
    ('A103', 2);    -- will be EMPTY (only ended history)

-- =====================================================================
-- (b) Function
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INTEGER;
    v_active   INTEGER;
BEGIN
    SELECT capacity INTO v_capacity FROM rooms WHERE room_id = p_room_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown room_id %', p_room_id;
    END IF;

    SELECT COUNT(*) INTO v_active
    FROM allocations
    WHERE room_id = p_room_id
      AND status = 'ACTIVE';           -- ENDED allocations do not occupy beds

    RETURN v_capacity - v_active;
END;
$$;

-- =====================================================================
-- (d) Trigger: enforces the rules for direct SQL changes too
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_fn_allocation_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INTEGER;
    v_others   INTEGER;
BEGIN
    IF NEW.status = 'ACTIVE' THEN
        -- Lock the room row so concurrent inserts for the same room queue up.
        SELECT capacity INTO v_capacity FROM rooms WHERE room_id = NEW.room_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown room_id %', NEW.room_id;
        END IF;

        -- One ACTIVE allocation per student (exclude the row being updated)
        IF EXISTS (
            SELECT 1 FROM allocations a
            WHERE a.student_id = NEW.student_id
              AND a.status = 'ACTIVE'
              AND a.allocation_id IS DISTINCT FROM NEW.allocation_id
        ) THEN
            RAISE EXCEPTION 'Student % already has an ACTIVE allocation', NEW.student_id;
        END IF;

        -- Capacity: other ACTIVE rows in the room must leave at least one bed
        SELECT COUNT(*) INTO v_others
        FROM allocations a
        WHERE a.room_id = NEW.room_id
          AND a.status = 'ACTIVE'
          AND a.allocation_id IS DISTINCT FROM NEW.allocation_id;

        IF v_others >= v_capacity THEN
            RAISE EXCEPTION 'Room % is full (capacity %)', NEW.room_id, v_capacity;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_allocation_rules
BEFORE INSERT OR UPDATE ON allocations
FOR EACH ROW
EXECUTE FUNCTION trg_fn_allocation_rules();

-- =====================================================================
-- (c) Procedure
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INTEGER, p_room_id INTEGER, p_allocated_on DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM 1 FROM students WHERE student_id = p_student_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown student_id %', p_student_id;
    END IF;

    -- Lock the room so availability cannot change between the check and the insert.
    PERFORM 1 FROM rooms WHERE room_id = p_room_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown room_id %', p_room_id;
    END IF;

    IF p_allocated_on IS NULL THEN
        RAISE EXCEPTION 'Allocation date must not be NULL';
    END IF;

    IF EXISTS (SELECT 1 FROM allocations
               WHERE student_id = p_student_id AND status = 'ACTIVE') THEN
        RAISE EXCEPTION 'Student % already has an ACTIVE allocation', p_student_id;
    END IF;

    IF fn_free_beds(p_room_id) <= 0 THEN
        RAISE EXCEPTION 'Room % has no free beds', p_room_id;
    END IF;

    INSERT INTO allocations (student_id, room_id, allocated_on, released_on, status)
    VALUES (p_student_id, p_room_id, p_allocated_on, NULL, 'ACTIVE');
END;
$$;

-- (a, continued) Allocations: room A101 full, A102 partly occupied, A103 empty
CALL pr_allocate_room(1, 1, CURRENT_DATE - 30);
CALL pr_allocate_room(2, 1, CURRENT_DATE - 30);
CALL pr_allocate_room(3, 2, CURRENT_DATE - 10);
-- Ended allocation: history only, does not occupy a bed
INSERT INTO allocations (student_id, room_id, allocated_on, released_on, status)
VALUES (4, 3, CURRENT_DATE - 200, CURRENT_DATE - 60, 'ENDED');

SELECT * FROM allocations ORDER BY allocation_id;

-- Tests for (b)
SELECT room_id, fn_free_beds(room_id) AS free_beds FROM rooms ORDER BY room_id;   -- 0, 2, 2
DO $$ BEGIN PERFORM fn_free_beds(999);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error: %', SQLERRM; END $$;

-- Tests for (c)
DO $$ BEGIN CALL pr_allocate_room(5, 1, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (full room): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_allocate_room(3, 2, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (already ACTIVE): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_allocate_room(99, 2, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (unknown student): %', SQLERRM; END $$;

-- Tests for (d): direct SQL must follow the same rules
DO $$ BEGIN INSERT INTO allocations (student_id, room_id, allocated_on, status) VALUES (5, 1, CURRENT_DATE, 'ACTIVE');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (direct insert, full): %', SQLERRM; END $$;
DO $$ BEGIN INSERT INTO allocations (student_id, room_id, allocated_on, status) VALUES (3, 3, CURRENT_DATE, 'ACTIVE');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Expected error (direct insert, 2nd ACTIVE): %', SQLERRM; END $$;
-- Updating a row without changing it must not count itself as "another" allocation:
UPDATE allocations SET allocated_on = allocated_on WHERE allocation_id = 1;
-- Ending an allocation frees the bed:
UPDATE allocations SET status = 'ENDED', released_on = CURRENT_DATE WHERE allocation_id = 2;
SELECT fn_free_beds(1) AS room1_free_after_release;   -- 1
UPDATE allocations SET status = 'ACTIVE', released_on = NULL WHERE allocation_id = 2;   -- back again

-- =====================================================================
-- (e) View: every room, including rooms with no allocations
-- =====================================================================
CREATE OR REPLACE VIEW v_room_occupancy AS
SELECT r.room_id,
       r.room_number,
       r.capacity,
       COUNT(a.allocation_id)              AS occupied_beds,
       r.capacity - COUNT(a.allocation_id) AS free_beds
FROM rooms r
LEFT JOIN allocations a
       ON a.room_id = r.room_id
      AND a.status = 'ACTIVE'              -- condition in ON keeps rooms with 0 matches
GROUP BY r.room_id, r.room_number, r.capacity;

SELECT * FROM v_room_occupancy ORDER BY room_id;

-- =====================================================================
-- (f) Index
-- Partial index on ACTIVE rows only: ENDED history grows forever, but only
-- ACTIVE rows occupy beds, so the index stays small and serves every
-- capacity check.
-- =====================================================================
CREATE INDEX idx_allocations_active_room ON allocations (room_id) WHERE status = 'ACTIVE';

ANALYZE allocations;
SET enable_seqscan = off;
EXPLAIN
SELECT allocation_id, student_id
FROM allocations
WHERE room_id = 1
  AND status = 'ACTIVE';
RESET enable_seqscan;

-- =====================================================================
-- (g) Scheduled job: one row per date and room, replaced on rerun
-- =====================================================================
CREATE OR REPLACE PROCEDURE pr_refresh_occupancy()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO occupancy_snapshot (snapshot_date, room_id, occupied_beds, free_beds)
    SELECT CURRENT_DATE,
           r.room_id,
           COUNT(a.allocation_id),
           r.capacity - COUNT(a.allocation_id)
    FROM rooms r
    LEFT JOIN allocations a
           ON a.room_id = r.room_id AND a.status = 'ACTIVE'
    GROUP BY r.room_id, r.capacity
    ON CONFLICT (snapshot_date, room_id) DO UPDATE
    SET occupied_beds = EXCLUDED.occupied_beds,
        free_beds     = EXCLUDED.free_beds;
END;
$$;

CALL pr_refresh_occupancy();
CALL pr_refresh_occupancy();     -- rerun replaces values
SELECT * FROM occupancy_snapshot ORDER BY room_id;     -- 3 rows, not 6

-- Schedule with pg_cron: daily at 23:55
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('pr_refresh_occupancy_daily', '55 23 * * *',
                     $$CALL pr_refresh_occupancy()$$);
SELECT jobid, jobname, schedule, command FROM cron.job;
