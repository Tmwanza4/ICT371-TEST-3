# Question 5: Hostel Room Allocation

Solution: [`q05_solution.sql`](q05_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_allocations_active_room ON allocations (room_id) WHERE status = 'ACTIVE';
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_allocations_active_room on allocations  (cost=0.13..12.17 rows=2 width=8)
  Index Cond: (room_id = 1)
```
