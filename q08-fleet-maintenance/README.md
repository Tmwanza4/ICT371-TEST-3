# Question 8: Transport Fleet Maintenance

**Database:** PostgreSQL. Run `q08_solution.sql` top to bottom in an empty database.

## Files
- [`q08_solution.sql`](q08_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_trips_vehicle_trip_on ON trips (vehicle_id, trip_on);
```
One vehicle's trips in a date range means equality on `vehicle_id` and a range on `trip_on`. With `vehicle_id` first, all of one vehicle's trips are together in the index, and within them the dates are in order, so the date range is one contiguous slice.

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
