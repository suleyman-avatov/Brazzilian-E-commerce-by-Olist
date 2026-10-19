import os
import duckdb

OUT_DIR = 'dashboard/data'
os.makedirs(OUT_DIR, exist_ok=True)
con = duckdb.connect("data/olist.duckdb", read_only=True)

Exports = { 
    "orders.csv": """
         SELECT order_id,
               CAST(purchase_date AS DATE) AS purchase_date,
               CAST(purchase_month AS DATE) AS purchase_month,
               customer_state,
               seller_state,
               category,
               CAST(is_late AS INTEGER) AS is_late,
               CAST(delay_days >= 4 AS INTEGER) AS is_severe_late,
               delay_days,
               delivery_days,
               promised_days,
               review_score,
               CAST(review_score <= 2 AS INTEGER) AS is_bad_score,
               order_value,
               freight_value,
               distance_km,
               CASE WHEN delay_days <= -8 THEN '1 раньше срока на 8+ дней'
                    WHEN delay_days <= -1 THEN '2 раньше срока на 1-7 дней'
                    WHEN delay_days = 0 THEN '3 в день обещанной даты'
                    WHEN delay_days <= 3 THEN '4 опоздание 1-3 дня'
                    WHEN delay_days <= 7 THEN '5 опоздание 4-7 дней'
                    WHEN delay_days <= 14 THEN '6 опоздание 8-14 дней'
                    ELSE '7 опоздание 15+ дней' END AS delay_bucket
        FROM marts.period_orders
    """,
     "cohort_retention.csv": """
        SELECT CAST(cohort_month AS DATE) AS cohort_month, month_offset,
               cohort_size, active_customers, retention_pct
        FROM marts.cohort_retention
        ORDER BY 1, 2
    """,
    "order_funnel.csv": "SELECT * FROM marts.order_funnel ORDER BY step",
    "delay_by_lane.csv": "SELECT * FROM marts.delay_by_lane ORDER BY late_orders DESC",
}

for name, sql in Exports.items():
    df = con.execute(sql).df()
    path = os.path.join(OUT_DIR, name)
    df.to_csv(path, index=False, encoding='UTF-8')
    size_mb = os.path.getsize(path) / 1024 / 1024
    print(f"{path}: {len(df)} строк, {size_mb:.1f} МБ")