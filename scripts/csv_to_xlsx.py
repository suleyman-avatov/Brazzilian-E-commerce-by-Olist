import pandas as pd

FILES = {
    "orders": ["purchase_date", "purchase_month"],
    "cohort_retention": ["cohort_month"],
    "order_funnel": [],
    "delay_by_lane": []
}

for name, dates in FILES.items():
    df = pd.read_csv(f"dashboard/data/{name}.csv", parse_dates=dates)
    df.to_excel(f"dashboard/data/{name}.xlsx", index=False)
    print(f"{name}.xlsx: {len(df)} строк")