# Question 7: Water Meter Readings and Billing

**Database:** PostgreSQL. Run `q07_solution.sql` top to bottom in an empty database.

## Files
- [`q07_solution.sql`](q07_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_bills_unpaid_due_on ON bills (due_on) WHERE amount_paid < charge;
```
Overdue searches only care about bills that are not fully paid and have an early `due_on`. A partial index holds only the unpaid bills, sorted by due date, so "due before today" reads a small slice. Paid bills (the majority over time) are not in the index at all. The query must repeat `amount_paid < charge`.

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
