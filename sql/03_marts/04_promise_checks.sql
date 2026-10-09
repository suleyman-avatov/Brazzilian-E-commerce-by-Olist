WITH q AS (
  SELECT *, NTILE(5) OVER (ORDER BY distance_km) AS distance_quintile
  FROM marts.period_orders
  WHERE distance_km IS NOT NULL
),
g AS (
  SELECT *,
         CASE WHEN purchase_month BETWEEN DATE '2017-05-01' AND DATE '2017-10-01' THEN '1 спокойный (май-окт 2017)'
              WHEN purchase_month = DATE '2017-11-01' THEN '2 ноябрь 2017'
              WHEN purchase_month = DATE '2017-12-01' THEN '3 декабрь 2017'
              WHEN purchase_month BETWEEN DATE '2018-02-01' AND DATE '2018-03-01' THEN '4 февраль-март 2018'
              WHEN purchase_month = DATE '2018-08-01' THEN '5 август 2018'
         END AS period_group
  FROM q
)
SELECT distance_quintile,
       period_group,
       COUNT(*) AS orders,
       ROUND(AVG(promised_days), 1) AS avg_promised_days,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct
FROM g
WHERE period_group IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT o.is_late,
       COUNT(*) AS orders,
       ROUND(AVG(date_diff('day', o.purchase_date, CAST(r.order_delivered_carrier_date AS DATE))), 1) AS days_to_carrier,
       ROUND(AVG(date_diff('day', CAST(r.order_delivered_carrier_date AS DATE), o.delivered_date)), 1) AS days_in_transit
FROM marts.period_orders o
JOIN raw.orders r ON o.order_id = r.order_id
WHERE r.order_delivered_carrier_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

WITH lim AS (
  SELECT order_id, MAX(shipping_limit_date) AS shipping_limit
  FROM raw.order_items
  GROUP BY 1
)
SELECT o.is_late,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.order_delivered_carrier_date > l.shipping_limit) / COUNT(*), 1) AS seller_missed_limit_pct
FROM marts.period_orders o
JOIN raw.orders r ON o.order_id = r.order_id
JOIN lim l ON o.order_id = l.order_id
WHERE r.order_delivered_carrier_date IS NOT NULL
GROUP BY 1
ORDER BY 1;