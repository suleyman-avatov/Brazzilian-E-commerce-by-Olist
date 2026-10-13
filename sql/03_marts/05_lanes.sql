CREATE OR REPLACE TABLE marts.delay_by_lane AS
SELECT seller_state,
       customer_state,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(AVG(promised_days), 1) AS avg_promised_days
FROM marts.period_orders
WHERE seller_state IS NOT NULL
GROUP BY 1, 2
HAVING COUNT(*) >= 200;

-- Вывод 1: пятнадцать маршрутов с наибольшим числом опоздавших заказов
SELECT seller_state, customer_state, orders, late_orders, late_pct,
       avg_delivery_days, avg_promised_days,
       ROUND(100.0 * late_orders / (SELECT COUNT(*) FILTER (WHERE is_late) FROM marts.period_orders), 1) AS share_of_all_late_pct
FROM marts.delay_by_lane
ORDER BY late_orders DESC
LIMIT 15;

-- Вывод 2: внутри штата и между штатами
SELECT seller_state = customer_state AS same_state,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE is_late) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(AVG(promised_days), 1) AS avg_promised_days
FROM marts.period_orders
WHERE seller_state IS NOT NULL
GROUP BY 1
ORDER BY 1;

SELECT customer_state, COUNT(*) AS orders,
        ROUND(AVG(distance_km), 0) AS avg_km,
        ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_pct
FROM marts.period_orders
WHERE seller_state = 'SP' AND customer_state IN ('RJ', 'MG', 'ES', 'PR')
GROUP BY 1
ORDER BY 1;