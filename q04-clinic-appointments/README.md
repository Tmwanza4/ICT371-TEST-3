# Question 4: Clinic Appointment Scheduling

Solution: [`q04_solution.sql`](q04_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_appointments_day_doctor ON appointments (appointment_day, doctor_id);
```

**Justification:** Appointments are searched by day and doctor, for example one doctor's schedule on one date. An index on appointment_day and doctor_id lets the database go directly to those rows instead of reading every appointment. It is not unique because a doctor can have up to four appointments in a day.

## (f) EXPLAIN
```
Index Scan using idx_appointments_day_doctor on appointments  (cost=0.14..8.17 rows=2 width=24)
  Index Cond: ((appointment_day = CURRENT_DATE) AND (doctor_id = 1))
```
