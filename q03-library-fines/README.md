# Question 3: Library Returns and Overdue Fines

**Database:** PostgreSQL. Run `q03_solution.sql` top to bottom in an empty database.

## Files
- [`q03_solution.sql`](q03_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_loans_unreturned_by_book ON loans (book_id) WHERE returned_on IS NULL;
```
The search is "unreturned loans for one book". A partial index contains only rows where `returned_on IS NULL`. Returned loans pile up over time and are never part of this search, so leaving them out keeps the index small and fast. The query must include `returned_on IS NULL` so PostgreSQL can use it.

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
