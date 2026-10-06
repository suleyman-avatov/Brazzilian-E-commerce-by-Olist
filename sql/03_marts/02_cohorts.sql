CREATE SCHEMA IF NOT EXISTS marts;

CREATE OR REPLACE TABLE marts.customer_first_order AS
WITH ranked AS (
  SELECT customer_unique_id, order_id, purchase_date, purchase_month,
         is_late, delay_days, review_score, order_value, customer_state, category,
         ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, order_id) AS rn
  FROM staging.stg_orders
),
first_orders AS (
  SELECT * FROM ranked WHERE rn = 1
),
repeats AS (
  SELECT f.customer_unique_id,
         COUNT(o.order_id) AS repeat_orders_180,
         MIN(o.purchase_date) AS second_purchase_date,
         SUM(o.order_value) AS repeat_revenue_180
  FROM first_orders f
  JOIN staging.stg_orders o
    ON o.customer_unique_id = f.customer_unique_id
   AND o.order_id <> f.order_id
   AND o.purchase_date > f.purchase_date
   AND o.purchase_date <= f.purchase_date + 180
  GROUP BY 1
)
SELECT f.customer_unique_id,
       f.order_id AS first_order_id,
       f.purchase_date AS first_purchase_date,
       f.purchase_month AS cohort_month,
       f.is_late,
       f.delay_days,
       f.review_score,
       f.order_value AS first_order_value,
       f.customer_state,
       f.category,
       COALESCE(r.repeat_orders_180, 0) AS repeat_orders_180,
       COALESCE(r.repeat_orders_180, 0) > 0 AS has_repeat_180,
       date_diff('day', f.purchase_date, r.second_purchase_date) AS days_to_repeat,
       COALESCE(r.repeat_revenue_180, 0) AS repeat_revenue_180,
       f.purchase_date BETWEEN DATE '2017-01-01' AND DATE '2018-03-04' AS in_h3_cohort
FROM first_orders f
LEFT JOIN repeats r ON f.customer_unique_id = r.customer_unique_id;

CREATE OR REPLACE TABLE marts.cohort_retention AS
WITH cohort AS (
  SELECT customer_unique_id, cohort_month
  FROM marts.customer_first_order
  WHERE first_purchase_date BETWEEN DATE '2017-01-01' AND DATE '2018-08-31'
),
sizes AS (
  SELECT cohort_month, COUNT(*) AS cohort_size
  FROM cohort
  GROUP BY 1
),
grid AS (
  SELECT s.cohort_month, s.cohort_size, g.month_offset
  FROM sizes s
  CROSS JOIN (SELECT UNNEST(range(7)) AS month_offset) g
  WHERE date_diff('month', CAST(s.cohort_month AS DATE), DATE '2018-08-01') >= g.month_offset
),
activity AS (
  SELECT DISTINCT c.cohort_month,
         date_diff('month', CAST(c.cohort_month AS DATE), CAST(o.purchase_month AS DATE)) AS month_offset,
         c.customer_unique_id
  FROM cohort c
  JOIN staging.stg_orders o ON o.customer_unique_id = c.customer_unique_id
)
SELECT g.cohort_month,
       g.month_offset,
       g.cohort_size,
       COUNT(a.customer_unique_id) AS active_customers,
       ROUND(100.0 * COUNT(a.customer_unique_id) / g.cohort_size, 2) AS retention_pct
FROM grid g
LEFT JOIN activity a
  ON a.cohort_month = g.cohort_month AND a.month_offset = g.month_offset
GROUP BY g.cohort_month, g.month_offset, g.cohort_size;

SELECT COUNT(*) AS customers,
       COUNT(*) FILTER (WHERE has_repeat_180) AS repeaters,
       ROUND(100.0 * COUNT(*) FILTER (WHERE has_repeat_180) / COUNT(*), 2) AS repeat_pct
FROM marts.customer_first_order
WHERE in_h3_cohort;

SELECT is_late,
       COUNT(*) AS customers,
       COUNT(*) FILTER (WHERE has_repeat_180) AS repeaters,
       ROUND(100.0 * COUNT(*) FILTER (WHERE has_repeat_180) / COUNT(*), 2) AS repeat_pct
FROM marts.customer_first_order
WHERE in_h3_cohort
GROUP BY 1
ORDER BY 1;

SELECT CASE WHEN review_score IS NULL THEN '0 нет отзыва'
            WHEN review_score <= 2 THEN '1 плохая (1-2)'
            WHEN review_score = 3 THEN '2 нейтральная (3)'
            ELSE '3 хорошая (4-5)' END AS review_group,
       COUNT(*) AS customers,
       COUNT(*) FILTER (WHERE has_repeat_180) AS repeaters,
       ROUND(100.0 * COUNT(*) FILTER (WHERE has_repeat_180) / COUNT(*), 2) AS repeat_pct
FROM marts.customer_first_order
WHERE in_h3_cohort
GROUP BY 1
ORDER BY 1;

SELECT COUNT(DISTINCT f.customer_unique_id) AS same_day_second_order
FROM marts.customer_first_order f
JOIN staging.stg_orders o
  ON o.customer_unique_id = f.customer_unique_id
 AND o.order_id <> f.first_order_id
 AND o.purchase_date = f.first_purchase_date
WHERE f.in_h3_cohort;

SELECT cohort_month,
       MAX(cohort_size) AS cohort_size,
       MAX(retention_pct) FILTER (WHERE month_offset = 1) AS m1,
       MAX(retention_pct) FILTER (WHERE month_offset = 2) AS m2,
       MAX(retention_pct) FILTER (WHERE month_offset = 3) AS m3,
       MAX(retention_pct) FILTER (WHERE month_offset = 4) AS m4,
       MAX(retention_pct) FILTER (WHERE month_offset = 5) AS m5,
       MAX(retention_pct) FILTER (WHERE month_offset = 6) AS m6
FROM marts.cohort_retention
GROUP BY 1
ORDER BY 1;