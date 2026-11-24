# Question 6: Monthly Payroll Processing

Solution: [`q06_solution.sql`](q06_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_payroll_pay_month ON payroll (pay_month);
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_payroll_pay_month on payroll  (cost=0.14..8.22 rows=5 width=14)
  Index Cond: (pay_month = '2026-10-01'::date)
```
