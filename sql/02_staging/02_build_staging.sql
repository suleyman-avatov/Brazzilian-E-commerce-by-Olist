CREATE SCHEMA IF NOT EXISTS staging;

DROP TABLE IF EXISTS staging.stg_geo;

-- Геолокация: одна строка на почтовый префикс (медиана координат)
CREATE OR REPLACE TABLE staging.stg_geo AS
SELECT geolocation_zip_code_prefix AS zip_prefix,
       median(geolocation_lat) AS lat,
       median(geolocation_lng) AS lng
FROM raw.geolocation
GROUP BY 1;

-- Товары: категория на английском, пропуски в unknown, две категории переведены вручную
CREATE OR REPLACE TABLE staging.stg_products AS
SELECT p.product_id,
       CASE
         WHEN p.product_category_name IS NULL THEN 'unknown'
         WHEN p.product_category_name = 'pc_gamer' THEN 'pc_gamer'
         WHEN p.product_category_name = 'portateis_cozinha_e_preparadores_de_alimentos' THEN 'portable_kitchen_food_preparers'
         ELSE COALESCE(t.product_category_name_english, p.product_category_name)
       END AS category
FROM raw.products p
LEFT JOIN raw.category_translation t
  ON p.product_category_name = t.product_category_name;

-- Отзывы: один (последний по времени ответа) на заказ
CREATE OR REPLACE TABLE staging.stg_reviews AS
SELECT order_id, review_score
FROM (
  SELECT order_id, review_score,
         ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS rn
  FROM raw.order_reviews
)
WHERE rn = 1;

-- Стоимость заказа: агрегат по позициям до соединения с другими таблицами
CREATE OR REPLACE TABLE staging.stg_order_values AS
SELECT order_id,
       COUNT(*) AS n_items,
       SUM(price) AS items_price,
       SUM(freight_value) AS freight_value,
       SUM(price + freight_value) AS order_value
FROM raw.order_items
GROUP BY order_id;

-- Главная позиция заказа: самая дорогая (при равенстве меньший order_item_id)
CREATE OR REPLACE TABLE staging.stg_primary_item AS
SELECT order_id, product_id, seller_id
FROM (
  SELECT order_id, product_id, seller_id,
         ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY price DESC, order_item_id) AS rn
  FROM raw.order_items
)
WHERE rn = 1;

-- Основная таблица: один доставленный заказ на строку
CREATE OR REPLACE TABLE staging.stg_orders AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_unique_id,
  c.customer_state,
  o.order_purchase_timestamp,
  CAST(o.order_purchase_timestamp AS DATE) AS purchase_date,
  DATE_TRUNC('month', o.order_purchase_timestamp) AS purchase_month,
  CAST(o.order_delivered_customer_date AS DATE) AS delivered_date,
  CAST(o.order_estimated_delivery_date AS DATE) AS estimated_date,
  date_diff('day', CAST(o.order_purchase_timestamp AS DATE), CAST(o.order_delivered_customer_date AS DATE)) AS delivery_days,
  date_diff('day', CAST(o.order_estimated_delivery_date AS DATE), CAST(o.order_delivered_customer_date AS DATE)) AS delay_days,
  CAST(o.order_delivered_customer_date AS DATE) > CAST(o.order_estimated_delivery_date AS DATE) AS is_late,
  COALESCE(o.order_delivered_customer_date < o.order_delivered_carrier_date, FALSE) AS date_anomaly,
  r.review_score,
  v.n_items,
  v.order_value,
  v.freight_value,
  pr.category,
  pit.seller_id,
  s.seller_state,
  CASE WHEN gc.lat IS NULL OR gs.lat IS NULL THEN NULL
      ELSE ROUND(6371 * 2 * asin(LEAST(1.0, sqrt(
        pow(sin(radians(gs.lat - gc.lat) / 2), 2) +
        cos(radians(gc.lat)) * cos(radians(gs.lat)) * pow(sin(radians(gs.lng - gc.lng) / 2), 2)
      ))), 1)
  END AS distance_km
FROM raw.orders o
JOIN raw.customers c ON o.customer_id = c.customer_id
LEFT JOIN staging.stg_reviews r ON o.order_id = r.order_id
LEFT JOIN staging.stg_order_values v ON o.order_id = v.order_id
LEFT JOIN staging.stg_primary_item pit ON o.order_id = pit.order_id
LEFT JOIN staging.stg_products pr ON pit.product_id = pr.product_id
LEFT JOIN raw.sellers s ON pit.seller_id = s.seller_id
LEFT JOIN staging.stg_geo gc ON c.customer_zip_code_prefix = gc.zip_prefix
LEFT JOIN staging.stg_geo gs ON s.seller_zip_code_prefix = gs.zip_prefix
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

UPDATE staging.stg_orders SET distance_km = NULL WHERE distance_km > 4500;