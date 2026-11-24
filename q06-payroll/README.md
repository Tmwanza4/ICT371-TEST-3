# Question 6: Monthly Payroll Processing

**Database:** PostgreSQL. Run `q06_solution.sql` top to bottom in an empty database.

## Files
- [`q06_solution.sql`](q06_solution.sql): full solution, parts (a) to (g) in order. It also contains the test calls (valid and invalid) for each part.

## (f) Index and justification
```sql
CREATE INDEX idx_payroll_pay_month ON payroll (pay_month);
```
The existing unique index is on `(employee_id, pay_month)`. It starts with `employee_id`, so it cannot efficiently answer "show every employee for one month". A separate index on `pay_month` alone fits that report. It does not duplicate the unique index, because the leading column is different.

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
