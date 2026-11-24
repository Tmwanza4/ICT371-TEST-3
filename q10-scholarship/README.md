# Question 10: Scholarship Application Assessment

Solution: [`q10_solution.sql`](q10_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_applications_status_submitted ON applications (status, submitted_on);
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_applications_status_submitted on applications  (cost=0.14..12.25 rows=5 width=12)
  Index Cond: (((status)::text = 'PENDING'::text) AND (submitted_on >= (CURRENT_DATE - 30)) AND (submitted_on <= CURRENT_DATE))
```
