# Question 8: Transport Fleet Maintenance

Solution: [`q08_solution.sql`](q08_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_trips_vehicle_trip_on ON trips (vehicle_id, trip_on);
```

**Justification:** The search is for one vehicle's trips within a date range. vehicle_id comes first because it is matched exactly and trip_on second because it is a range. All of one vehicle's trips are then together in date order, so the range is read in one go.

## (f) EXPLAIN
```
Index Scan using idx_trips_vehicle_trip_on on trips  (cost=0.14..8.19 rows=2 width=16)
  Index Cond: ((vehicle_id = 2) AND (trip_on >= (CURRENT_DATE - 30)) AND (trip_on <= CURRENT_DATE))
```
