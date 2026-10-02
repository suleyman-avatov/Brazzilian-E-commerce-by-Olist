SELECT order_status, 
        COUNT(*) FILTER(WHERE order_approved_at IS NULL) AS no_approved,
        COUNT(*) FILTER(WHERE order_delivered_carrier_date IS NULL) AS no_carrier,
        COUNT(*) FILTER(WHERE order_delivered_customer_date IS NULL) AS no_delivered,
        COUNT(*) FILTER(WHERE order_estimated_delivery_date IS NULL) AS no_estimated
FROM raw.orders
GROUP BY 1
ORDER BY 2 DESC;

SELECT 
    COUNT(*) FILTER(WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL) AS delivered_no_date,
    COUNT(*) FILTER(WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL) AS date_but_not_delivered,
    COUNT(*) FILTER(WHERE order_delivered_customer_date < order_purchase_timestamp) AS delivered_before_purchase,
    COUNT(*) FILTER(WHERE order_delivered_customer_date < order_delivered_carrier_date) AS delivered_before_carrier,
    COUNT(*) FILTER(WHERE order_approved_at < order_purchase_timestamp) AS approved_before_purchase,
    COUNT(*) FILTER(WHERE order_estimated_delivery_date < order_purchase_timestamp) AS estimate_before_purchase
FROM raw.orders;

SELECT COUNT(*) AS total,
       COUNT(*) FILTER(WHERE order_estimated_delivery_date::TIME<>TIME '00:00:00') AS estimated_with_time
FROM raw.orders;

SELECT o.order_status, COUNT(*) AS orders_without_items
FROM raw.orders o
LEFT JOIN (SELECT DISTINCT order_id FROM raw.order_items) i ON o.order_id = i.order_id
WHERE i.order_id IS NULL
GROUP BY 1
ORDER BY 2 DESC;

SELECT review_score, COUNT(*) AS reviews
FROM raw.order_reviews
GROUP BY 1
ORDER BY 1;

SELECT COUNT(*) AS tied_orders
FROM (
    SELECT order_id, review_answer_timestamp
    FROM raw.order_reviews
    GROUP BY 1, 2
    HAVING COUNT(*) > 1
);

SELECT COUNT(*) AS products,
       COUNT(*) FILTER (WHERE p.product_category_name IS NULL) AS no_category,
       COUNT(*) FILTER (WHERE p.product_category_name IS NOT NULL AND t.product_category_name_english IS NULL) AS no_translation
FROM raw.products p
LEFT JOIN raw.category_translation t ON p.product_category_name = t.product_category_name;

SELECT p.product_category_name, COUNT(*) AS products
FROM raw.products p
LEFT JOIN raw.category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name_english IS NULL
GROUP BY 1
ORDER BY 2 DESC;

SELECT COUNT(*) AS n_rows, COUNT(DISTINCT geolocation_zip_code_prefix) AS zip_prefixes
FROM raw.geolocation;

SELECT
  (SELECT COUNT(*) FROM raw.customers c
   LEFT JOIN (SELECT DISTINCT geolocation_zip_code_prefix AS z FROM raw.geolocation) g
     ON c.customer_zip_code_prefix = g.z
   WHERE g.z IS NULL) AS customers_without_geo,
  (SELECT COUNT(*) FROM raw.sellers s
   LEFT JOIN (SELECT DISTINCT geolocation_zip_code_prefix AS z FROM raw.geolocation) g
     ON s.seller_zip_code_prefix = g.z
   WHERE g.z IS NULL) AS sellers_without_geo;

WITH d AS (
  SELECT date_diff('day', order_purchase_timestamp, order_delivered_customer_date) AS delivery_days,
         date_diff('day', order_estimated_delivery_date, order_delivered_customer_date) AS delay_days
  FROM raw.orders
  WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
)
SELECT COUNT(*) AS delivered_orders,
       MIN(delivery_days) AS min_days,
       quantile_cont(delivery_days, 0.5) AS median_days,
       quantile_cont(delivery_days, 0.99) AS p99_days,
       MAX(delivery_days) AS max_days,
       COUNT(*) FILTER (WHERE delay_days > 0) AS late_by_days
FROM d;

SELECT MIN(price) AS min_price,
       quantile_cont(price, 0.5) AS median_price,
       quantile_cont(price, 0.99) AS p99_price,
       MAX(price) AS max_price,
       COUNT(*) FILTER (WHERE price <= 0) AS nonpositive_price,
       MIN(freight_value) AS min_freight,
       quantile_cont(freight_value, 0.99) AS p99_freight,
       MAX(freight_value) AS max_freight
FROM raw.order_items;
