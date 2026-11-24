# Question 2: University Fee Payments

Solution: [`q02_solution.sql`](q02_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_payments_student_paid_on ON payments (student_id, paid_on) INCLUDE (amount);
```

**Justification:** Payments are searched by one student and a date range. The index has student_id first (exact match) and paid_on second (range), so the database jumps to that student's payments and reads only the dates in range. I added amount with INCLUDE so totals can be read from the index without opening the table.

## (f) EXPLAIN
```
Index Scan using idx_payments_student_paid_on on payments  (cost=0.14..8.21 rows=3 width=13)
  Index Cond: ((student_id = 2) AND (paid_on >= (CURRENT_DATE - 30)) AND (paid_on <= CURRENT_DATE))
```
