SELECT COUNT(*) AS n_rows, COUNT(DISTINCT order_id) AS unique_orders
FROM staging.stg_orders;

SELECT COUNT(*) FILTER(WHERE is_late) AS late_orders,
        ROUND(100.0 * COUNT(*) FILTER(WHERE is_late) / COUNT(*), 2) AS late_pct,
        COUNT(*) FILTER(WHERE date_anomaly) AS anomalies
FROM staging.stg_orders;

SELECT COUNT(*) FILTER(WHERE review_score IS NULL) AS no_review,
       COUNT(*) FILTER(WHERE order_value IS NULL) AS no_value,
       COUNT(*) FILTER(WHERE distance_km IS NULL) AS no_distance,
       COUNT(*) FILTER(WHERE category='unknown') AS unknown_category
FROM staging.stg_orders;

SELECT(SELECT ROUND(SUM(order_value), 2) FROM staging.stg_orders) AS staging_total,
      (SELECT ROUND(SUM(i.price + i.freight_value), 2) FROM raw.order_items i
      JOIN staging.stg_orders s ON i.order_id = s.order_id) AS raw_total;

SELECT MIN(distance_km) AS min_km,
        quantile_cont(distance_km, 0.5) AS median_km,
        quantile_cont(distance_km, 0.99) AS p99_km,
        MAX(distance_km) AS max_km
FROM staging.stg_orders;

SELECT is_late,
    COUNT(*) AS orders,
    ROUND(AVG(review_score), 2) AS avg_score,
    ROUND(100.0 * COUNT(*) FILTER(WHERE review_score <= 2) / COUNT(review_score), 1) AS bad_score_pct,
    ROUND(AVG(order_value), 1) AS avg_order_value
FROM staging.stg_orders
GROUP BY 1
ORDER BY 1;

-- 7. Подозрительные расстояния
SELECT COUNT(*) FILTER (WHERE distance_km IS NULL) AS no_distance,
       COUNT(*) FILTER (WHERE distance_km > 4500) AS over_4500_km
FROM staging.stg_orders;