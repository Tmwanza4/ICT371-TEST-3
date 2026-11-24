# Question 6: Monthly Payroll Processing

Solution: [`q06_solution.sql`](q06_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_payroll_pay_month ON payroll (pay_month);
```

**Justification:** The existing unique index starts with employee_id, so it cannot be used efficiently to find all employees for one month. A separate index on pay_month supports the monthly report directly. It is not a duplicate of the unique index because its first column is different.

## (f) EXPLAIN
```
Index Scan using idx_payroll_pay_month on payroll  (cost=0.14..8.22 rows=5 width=14)
  Index Cond: (pay_month = '2026-10-01'::date)
```
