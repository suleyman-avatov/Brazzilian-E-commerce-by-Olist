SELECT 'customers' AS tbl, COUNT(*) AS n FROM raw.customers
UNION ALL SELECT 'geolocation', COUNT(*) FROM raw.geolocation
UNION ALL SELECT 'order_items', COUNT(*) FROM raw.order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM raw.order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM raw.order_reviews
UNION ALL SELECT 'orders', COUNT(*) FROM raw.orders
UNION ALL SELECT 'products', COUNT(*) FROM raw.products
UNION ALL SELECT 'sellers', COUNT(*) FROM raw.sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM raw.category_translation;

SELECT 'orders.order_id' AS key, COUNT(*) - COUNT(DISTINCT order_id) AS duplicates FROM raw.orders
UNION ALL SELECT 'customers.customer_id', COUNT(*) - COUNT(DISTINCT customer_id) FROM raw.customers
UNION ALL SELECT 'products.product_id', COUNT(*) - COUNT(DISTINCT product_id) FROM raw.products
UNION ALL SELECT 'sellers.seller_id', COUNT(*) - COUNT(DISTINCT seller_id) FROM raw.sellers
UNION ALL SELECT 'order_items (order_id, order_item_id)',
  COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id FROM raw.order_items))
  FROM raw.order_items
UNION ALL SELECT 'order_payments (order_id, payment_sequential)',
  COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential FROM raw.order_payments))
  FROM raw.order_payments
UNION ALL SELECT 'order_reviews.review_id', COUNT(*) - COUNT(DISTINCT review_id) FROM raw.order_reviews;

SELECT 'orders -> customers' AS relation, COUNT(*) AS orphans
FROM raw.orders o LEFT JOIN raw.customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL SELECT 'order_items -> orders', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.orders o ON i.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'order_items -> products', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.products p ON i.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL SELECT 'order_items -> sellers', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.sellers s ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL
UNION ALL SELECT 'order_payments -> orders', COUNT(*)
FROM raw.order_payments p LEFT JOIN raw.orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'order_reviews -> orders', COUNT(*)
FROM raw.order_reviews r LEFT JOIN raw.orders o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL SELECT 'orders without items', COUNT(*)
FROM raw.orders o LEFT JOIN (SELECT DISTINCT order_id FROM raw.order_items) i ON o.order_id = i.order_id
WHERE i.order_id IS NULL;

SELECT COUNT(*) AS customer_ids, COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM raw.customers;

SELECT order_status, COUNT(*) AS orders
FROM raw.orders GROUP BY 1 ORDER BY 2 DESC;

SELECT DATE_TRUNC('month', order_purchase_timestamp) AS month, COUNT(*) AS orders
FROM raw.orders GROUP BY 1 ORDER BY 1;

SELECT reviews_per_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS reviews_per_order FROM raw.order_reviews GROUP BY 1)
GROUP BY 1 ORDER BY 1;