# Question 1: Pharmacy Stock and Daily Sales

**Database:** PostgreSQL. Run `q01_solution.sql` top to bottom in an empty database.

## Files
- [`q01_solution.sql`](q01_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_sales_medicine_sold_on ON sales (medicine_id, sold_on);
```
The query filters one medicine by equality (`medicine_id = ?`) and a range of dates (`sold_on BETWEEN ...`). Putting the equality column first and the range column second lets PostgreSQL jump straight to that medicine's entries and read only the dates in range, in order. Without it, PostgreSQL scans every row in `sales`, which gets slower as sales history grows.

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
