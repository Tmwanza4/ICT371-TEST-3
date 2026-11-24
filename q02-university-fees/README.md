# Question 2: University Fee Payments

**Database:** PostgreSQL. Run `q02_solution.sql` top to bottom in an empty database.

## Files
- [`q02_solution.sql`](q02_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_payments_student_paid_on ON payments (student_id, paid_on) INCLUDE (amount);
```
Payments are filtered by `student_id` (equality) and a `paid_on` range, so the composite index has `student_id` first and `paid_on` second. `INCLUDE (amount)` stores the amount in the index, so balance and statement queries can be answered from the index alone without visiting the table.

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
