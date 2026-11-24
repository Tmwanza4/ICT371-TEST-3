# Question 7: Water Meter Readings and Billing

Solution: [`q07_solution.sql`](q07_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_bills_unpaid_due_on ON bills (due_on) WHERE amount_paid < charge;
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_bills_unpaid_due_on on bills  (cost=0.13..8.15 rows=1 width=40)
  Index Cond: (due_on < CURRENT_DATE)
```
