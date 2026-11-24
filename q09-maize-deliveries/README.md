# Question 9: Farmer Cooperative Maize Deliveries

**Database:** PostgreSQL. Run `q09_solution.sql` top to bottom in an empty database.

## Files
- [`q09_solution.sql`](q09_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_deliveries_farmer_date ON deliveries (farmer_id, delivered_on);
```
A farmer's deliveries between two dates is an equality on `farmer_id` plus a range on `delivered_on`. The composite index with `farmer_id` first lets PostgreSQL go straight to that farmer's rows and read only the requested date range in order.

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
