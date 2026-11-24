# Question 4: Clinic Appointment Scheduling

Solution: [`q04_solution.sql`](q04_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_appointments_day_doctor ON appointments (appointment_day, doctor_id);
```

**Justification:** (write 2-3 sentences here in your own words)

## (f) EXPLAIN
```
Index Scan using idx_appointments_day_doctor on appointments  (cost=0.14..8.17 rows=2 width=24)
  Index Cond: ((appointment_day = CURRENT_DATE) AND (doctor_id = 1))
```
