import os
import duckdb
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

if os.path.basename(os.getcwd()) == "analysis":
    os.chdir('..')

con = duckdb.connect("data/olist.duckdb", read_only=True)
orders = con.execute("SELECT * FROM marts.period_orders").df()
cohort = con.execute("""
    SELECT c.*, o.distance_km
    FROM marts.customer_first_order c
    JOIN staging.stg_orders o ON c.first_order_id = o.order_id
    WHERE c.in_h3_cohort
""").df()

def or_ci(res, name):
    ci = res.conf_int().loc[name]
    return np.exp(res.params[name]), np.exp(ci[0]), np.exp(ci[1])

o = orders.dropna(subset=['review_score', 'distance_km', 'order_value'])
o['bad_score'] = (o['review_score'] <= 2).astype(int)
o['late_days'] = o['delay_days'].clip(lower=0).astype(int) 
o['is_late'] = (o['late_days'] > 0).astype(int)
o['month'] = o['purchase_month'].astype(str).str[:7]
o['dist100'] = o['distance_km'] / 100
o['log_value'] = np.log(o["order_value"])

print(f"Заказов в моделях H1: {len(o)}")

m_a = smf.logit("bad_score ~ is_late + C(month) + dist100 + C(customer_state) + log_value", data=o).fit(disp=0, cov_type='HC1', method='bfgs', maxiter=5000)
orr, lo, hi = or_ci(m_a, "is_late")
p1 = m_a.predict(o.assign(is_late=1)).mean()
p0 = m_a.predict(o.assign(is_late=0)).mean()

print("\nМодель А: вероятность плохой оценки (1-2)")
print(f"Отношение шансов для задержки: {orr:.1f} (95% ДИ {lo:.1f} .. {hi:.1f})")
print(f"Скорректированная доля плохих оценок: если все заказы с задержкой {100 * p1:.1f}%, если все вовремя {100 * p0:.1f}%")

m_1 = smf.ols('review_score ~ delivery_days', data=o).fit()
m_2 = smf.ols('review_score ~ late_days', data=o).fit()
m_3 = smf.ols('review_score ~ delivery_days + late_days', data=o).fit(cov_type='HC1')

print("\nМодель B: срок доставки или опоздание")
print(f"R^2 только срок доставки: {m_1.rsquared:.3f}")
print(f"R^2 только дни опоздания: {m_2.rsquared:.3f}")
print(f"R^2 срок доставки и дни опоздания: {m_3.rsquared:.3f}")
print(f"Срок доставки: {m_3.params['delivery_days']:.4f} (p = {m_3.pvalues['delivery_days']:.3g})")

c = cohort.dropna(subset=['distance_km', 'first_order_value']).copy()
c["is_late"] = c["is_late"].astype(int)
c['repeat'] = c['has_repeat_180'].astype(int)
c['month'] = c['cohort_month'].astype(str).str[:7]
c['dist100'] = c['distance_km'] / 100
c['log_value'] = np.log(c["first_order_value"])
print(f"\nКлиентов в моделях H3: {len(c)} | вернулись: {int(c['repeat'].sum())}")

m_c = smf.logit("repeat ~ is_late + C(month) + dist100 + C(customer_state) + log_value", data=c).fit(disp=0, cov_type='HC1', method='bfgs', maxiter=5000)
orr, lo, hi = or_ci(m_c, "is_late")
p1 = m_c.predict(c.assign(is_late=1)).mean()
p0 = m_c.predict(c.assign(is_late=0)).mean()

print("\nМодель C: повторная покупка за 180 дней")
print(f"Отношение шансов задержек: {orr:.2f} (95% ДИ {lo:.2f} ... {hi:.2f}), p = {m_c.pvalues['is_late']:.4f}")
print(f"Скорректированная доля вернувшихся: если все с задержкой {100 * p1:.2f}%, если все вовремя {100 * p0:.2f}%")
print(f"Скорректированная разность: {100 * (p0 - p1):.2f} п.п.")

o['speed_bin'] = pd.cut(o['delivery_days'], [-1, 7, 14, 21, 30, 400], labels=["0-7", "8-14", "15-21", "22-30", "31+"])
tab=(o.groupby(["speed_bin", "is_late"], observed=True)["review_score"].agg(["count", "mean"]).round(2).unstack("is_late"))
print(f"\n{tab}")