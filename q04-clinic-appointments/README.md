# Question 4: Clinic Appointment Scheduling

**Database:** PostgreSQL. Run `q04_solution.sql` top to bottom in an empty database.

## Files
- [`q04_solution.sql`](q04_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_appointments_day_doctor ON appointments (appointment_day, doctor_id);
```
Schedules are looked up by day and doctor ("Dr X on this date"). This non-unique composite index puts both columns in the search, so PostgreSQL goes directly to that doctor's rows for that day instead of scanning the whole appointments table. It is non-unique because a doctor has up to four appointments per day.

## (f) EXPLAIN output
> Paste the plan printed by your own run here (or a screenshot).
> The tables are tiny, so the file runs `SET enable_seqscan = off;` before the EXPLAIN to make PostgreSQL show the index. On a real, larger table it chooses the index by itself.

```
(paste EXPLAIN output here)
```

## Test results
> Add screenshots (or pasted output) of the test queries in the `.sql` file: the function results, the rejected calls (shown as `NOTICE: Expected error ...`), the trigger audit rows, the view, and the scheduled-job table after running it twice.

## Scheduled job
The job is scheduled with the **pg_cron** extension (`cron.schedule(...)` at the bottom of the SQL file). `SELECT * FROM cron.job;` shows the registered schedule.
