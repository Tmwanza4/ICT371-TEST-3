# Question 7: Water Meter Readings and Billing

Solution: [`q07_solution.sql`](q07_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_bills_unpaid_due_on ON bills (due_on) WHERE amount_paid < charge;
```

**Justification:** Overdue searches only look at bills that are not fully paid, ordered by due date. I made the index partial (WHERE amount_paid < charge) on due_on, so paid bills are not included. The overdue query then reads a small index instead of the whole bills table.

## (f) EXPLAIN
```
Index Scan using idx_bills_unpaid_due_on on bills  (cost=0.13..8.15 rows=1 width=40)
  Index Cond: (due_on < CURRENT_DATE)
```
