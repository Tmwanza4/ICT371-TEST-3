# Question 10: Scholarship Application Assessment

Solution: [`q10_solution.sql`](q10_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_applications_status_submitted ON applications (status, submitted_on);
```

**Justification:** The search filters by status and a submitted_on range. status is first because it is matched exactly, and submitted_on second because it is a range. This lets the database find all applications with one status already in date order, and it also helps the weekly job that looks for PENDING applications.

## (f) EXPLAIN
```
Index Scan using idx_applications_status_submitted on applications  (cost=0.14..12.25 rows=5 width=12)
  Index Cond: (((status)::text = 'PENDING'::text) AND (submitted_on >= (CURRENT_DATE - 30)) AND (submitted_on <= CURRENT_DATE))
```
