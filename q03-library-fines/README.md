# Question 3: Library Returns and Overdue Fines

Solution: [`q03_solution.sql`](q03_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_loans_unreturned_by_book ON loans (book_id) WHERE returned_on IS NULL;
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_loans_unreturned_by_book on loans  (cost=0.13..8.15 rows=1 width=20)
  Index Cond: (book_id = 1)
```
