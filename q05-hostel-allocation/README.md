# Question 5: Hostel Room Allocation

**Database:** PostgreSQL. Run `q05_solution.sql` top to bottom in an empty database.

## Files
- [`q05_solution.sql`](q05_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_allocations_active_room ON allocations (room_id) WHERE status = 'ACTIVE';
```
Only ACTIVE allocations occupy beds, and every capacity check and occupancy report asks "how many ACTIVE rows does this room have?". ENDED rows are permanent history and keep growing, so a partial index on ACTIVE rows stays small and is much faster for these checks. The query must include `status = 'ACTIVE'` to use it.

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
