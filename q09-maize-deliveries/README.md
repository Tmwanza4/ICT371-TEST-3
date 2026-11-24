# Question 9: Farmer Cooperative Maize Deliveries

Solution: [`q09_solution.sql`](q09_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_deliveries_farmer_date ON deliveries (farmer_id, delivered_on);
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_deliveries_farmer_date on deliveries  (cost=0.14..8.21 rows=3 width=16)
  Index Cond: ((farmer_id = 1) AND (delivered_on >= (CURRENT_DATE - 7)) AND (delivered_on <= CURRENT_DATE))
```
