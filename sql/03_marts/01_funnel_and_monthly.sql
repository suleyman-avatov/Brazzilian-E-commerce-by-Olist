CREATE SCHEMA IF NOT EXISTS marts;

CREATE OR REPLACE TABLE marts.order_funnel AS
WITH base AS (
    SELECT * FROM raw.orders WHERE CAST(order_purchase_timestamp AS DATE) BETWEEN DATE '2017-01-01' AND '2018-08-31'
),
stages AS (
SELECT 1 AS step, 'Оформлен заказ' AS stage, COUNT(*) AS orders FROM base
  UNION ALL
  SELECT 2, 'Заказ подтверждён', COUNT(*) FILTER (WHERE order_approved_at IS NOT NULL) FROM base
  UNION ALL
  SELECT 3, 'Передан перевозчику', COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NOT NULL) FROM base
  UNION ALL
  SELECT 4, 'Доставлен клиенту',
         COUNT(*) FILTER (WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL) FROM base
  UNION ALL
  SELECT 5, 'Оставлен отзыв',
     COUNT(*) FILTER (WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
                        AND order_id IN (SELECT order_id FROM staging.stg_reviews)) FROM base
)

SELECT step, stage, orders,
        ROUND(100.0 * orders / FIRST_VALUE(orders) OVER(ORDER BY step), 1) AS pct_of_start,
        ROUND(100.0 * orders / LAG(orders) OVER(ORDER BY step), 1) AS pct_of_prev
FROM stages;

CREATE OR REPLACE TABLE marts.monthly_metrics AS 
SELECT purchase_month,
        COUNT(*) AS delivered_orders,
        COUNT(DISTINCT customer_unique_id) AS customers,
        ROUND(SUM(order_value), 0) AS revenue,
        ROUND(AVG(order_value), 1) AS avg_order_value,
        COUNT(*) FILTER(WHERE is_late) AS late_orders,
        ROUND(100.0 * COUNT(*) FILTER(WHERE is_late) / COUNT(*), 2) AS late_pct,
        ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
        ROUND(AVG(review_score), 2) AS avg_score,
        ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(review_score), 1) AS bad_score_pct
FROM staging.stg_orders
WHERE purchase_date BETWEEN DATE '2017-01-01' AND DATE '2018-08-31'
GROUP BY 1;

SELECT * FROM marts.order_funnel ORDER BY STEP;
SELECT * FROM marts.monthly_metrics ORDER BY purchase_month;