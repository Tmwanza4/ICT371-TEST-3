# Question 1: Pharmacy Stock and Daily Sales

Solution: [`q01_solution.sql`](q01_solution.sql)

## (f) Index
```sql
CREATE INDEX idx_sales_medicine_sold_on ON sales (medicine_id, sold_on);
```

**Justification:** The query looks for one medicine within a range of dates. I put medicine_id first because it is matched exactly, and sold_on second because it is a range. This way the database goes straight to that medicine's sales and reads only the dates needed, instead of scanning the whole sales table.

## (f) EXPLAIN
```
Index Scan using idx_sales_medicine_sold_on on sales  (cost=0.14..8.19 rows=2 width=17)
  Index Cond: ((medicine_id = 1) AND (sold_on >= (CURRENT_DATE - 7)) AND (sold_on <= CURRENT_DATE))
```
