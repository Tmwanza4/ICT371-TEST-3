# Question 5: Hostel Room Allocation

Solution: [`q05_solution.sql`](q05_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_allocations_active_room ON allocations (room_id) WHERE status = 'ACTIVE';
```

**Justification:** Only ACTIVE allocations take up beds, and the capacity check counts ACTIVE rows for a room. I made the index partial (WHERE status = 'ACTIVE') so ENDED history, which keeps growing, is left out. That keeps the index small and makes counting a room's active students quick.

## (f) EXPLAIN
```
Index Scan using idx_allocations_active_room on allocations  (cost=0.13..12.17 rows=2 width=8)
  Index Cond: (room_id = 1)
```
