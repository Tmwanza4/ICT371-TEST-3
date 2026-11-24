# Question 2: University Fee Payments

Solution: [`q02_solution.sql`](q02_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_payments_student_paid_on ON payments (student_id, paid_on) INCLUDE (amount);
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_payments_student_paid_on on payments  (cost=0.14..8.21 rows=3 width=13)
  Index Cond: ((student_id = 2) AND (paid_on >= (CURRENT_DATE - 30)) AND (paid_on <= CURRENT_DATE))
```
