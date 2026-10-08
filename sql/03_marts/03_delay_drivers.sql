CREATE SCHEMA IF NOT EXISTS marts;

CREATE OR REPLACE VIEW marts.period_orders AS
SELECT *, date_diff('day', purchase_date, estimated_date) AS promised_days
FROM staging.stg_orders
WHERE purchase_date BETWEEN DATE '2017-01-01' AND DATE '2018-08-31';

CREATE OR REPLACE TABLE marts.delay_by_state AS
WITH s AS (
  SELECT customer_state,
         COUNT(*) AS orders,
         COUNT(*) FILTER (WHERE is_late) AS late_orders,
         AVG(delivery_days) AS avg_delivery_days,
         AVG(promised_days) AS avg_promised_days
  FROM marts.period_orders
  GROUP BY 1
)
SELECT customer_state, orders, late_orders,
       ROUND(100.0 * late_orders / orders, 2) AS late_pct,
       ROUND(avg_delivery_days, 1) AS avg_delivery_days,
       ROUND(avg_promised_days, 1) AS avg_promised_days,
       ROUND(100.0 * late_orders / SUM(late_orders) OVER (), 1) AS share_of_all_late_pct
FROM s;

CREATE OR REPLACE TABLE marts.delay_by_distance AS
WITH d AS (
  SELECT *, NTILE(5) OVER (ORDER BY distance_km) AS distance_quintile
  FROM marts.period_orders
  WHERE distance_km IS NOT NULL
)
SELECT distance_quintile,
       MIN(distance_km) AS from_km,
       MAX(distance_km) AS to_km,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(AVG(promised_days), 1) AS avg_promised_days
FROM d
GROUP BY 1;

CREATE OR REPLACE TABLE marts.promise_vs_actual AS
SELECT purchase_month,
       COUNT(*) AS orders,
       ROUND(AVG(promised_days), 1) AS avg_promised_days,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(AVG(promised_days - delivery_days), 1) AS avg_buffer_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct
FROM marts.period_orders
GROUP BY 1;

CREATE OR REPLACE TABLE marts.delay_severity AS
SELECT CASE WHEN delay_days <= -8 THEN '1 раньше срока на 8+ дней'
            WHEN delay_days <= -1 THEN '2 раньше срока на 1-7 дней'
            WHEN delay_days = 0 THEN '3 в день обещанной даты'
            WHEN delay_days <= 3 THEN '4 опоздание 1-3 дня'
            WHEN delay_days <= 7 THEN '5 опоздание 4-7 дней'
            WHEN delay_days <= 14 THEN '6 опоздание 8-14 дней'
            ELSE '7 опоздание 15+ дней' END AS delay_bucket,
       COUNT(*) AS orders,
       COUNT(review_score) AS reviews,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(review_score), 1) AS bad_score_pct
FROM marts.period_orders
GROUP BY 1;

CREATE OR REPLACE TABLE marts.delay_by_category AS
SELECT category,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(AVG(order_value), 1) AS avg_order_value
FROM marts.period_orders
GROUP BY 1
HAVING COUNT(*) >= 300;

CREATE OR REPLACE TABLE marts.delay_by_seller AS
SELECT seller_id,
       seller_state,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct
FROM marts.period_orders
WHERE seller_id IS NOT NULL
GROUP BY 1, 2;

-- Вывод 1: штаты клиента
SELECT * FROM marts.delay_by_state ORDER BY late_orders DESC;

-- Вывод 2: расстояние
SELECT * FROM marts.delay_by_distance ORDER BY distance_quintile;

-- Вывод 3: обещанный срок против фактического
SELECT * FROM marts.promise_vs_actual ORDER BY purchase_month;

-- Вывод 4: тяжесть задержки и оценка
SELECT * FROM marts.delay_severity ORDER BY delay_bucket;

-- Вывод 5: чем отличаются заказы с задержкой и без
SELECT is_late,
       COUNT(*) AS orders,
       ROUND(AVG(order_value), 1) AS avg_order_value,
       ROUND(AVG(freight_value), 1) AS avg_freight,
       ROUND(AVG(n_items), 2) AS avg_items,
       ROUND(quantile_cont(distance_km, 0.5), 0) AS median_km,
       ROUND(AVG(promised_days), 1) AS avg_promised_days,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days
FROM marts.period_orders
GROUP BY 1
ORDER BY 1;

-- Вывод 6: десять категорий с наибольшей долей задержек
SELECT * FROM marts.delay_by_category ORDER BY late_pct DESC LIMIT 10;

-- Вывод 7: концентрация задержек у продавцов (50 и более заказов)
SELECT COUNT(*) AS sellers_50plus,
       COUNT(*) FILTER (WHERE late_pct >= 15) AS sellers_late_15plus,
       SUM(late_orders) FILTER (WHERE late_pct >= 15) AS late_orders_in_them
FROM marts.delay_by_seller
WHERE orders >= 50;

-- Вывод 8: доля десяти продавцов с наибольшим числом опоздавших заказов
SELECT SUM(late_orders) AS late_in_top10,
       ROUND(100.0 * SUM(late_orders) / (SELECT COUNT(*) FILTER (WHERE is_late) FROM marts.period_orders), 1) AS share_of_all_late_pct
FROM (SELECT late_orders FROM marts.delay_by_seller ORDER BY late_orders DESC LIMIT 10);