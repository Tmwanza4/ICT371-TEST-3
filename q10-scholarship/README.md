# Question 10: Scholarship Application Assessment

**Database:** PostgreSQL. Run `q10_solution.sql` top to bottom in an empty database.

## Files
- [`q10_solution.sql`](q10_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_applications_status_submitted ON applications (status, submitted_on);
```
The search is `status = ?` (equality) within a `submitted_on` range. Equality column first, range column second, so PostgreSQL finds all rows of one status already sorted by date and reads only the range. This also serves the weekly job's lookup of PENDING applications.

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
