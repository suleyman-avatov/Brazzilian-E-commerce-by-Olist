import os
import sys

print("PYTHON: ", sys.executable)
print("VERSION: ", sys.version)
 
import duckdb
import numpy as np
import pandas as pd
from scipy import stats

if os.path.basename(os.getcwd()) == "analysis":
    os.chdir("..")
sys.path.append("scripts")
from scripts.stats_helpers import compare_props, min_detectable_diff
 
con = duckdb.connect("data/olist.duckdb", read_only=True)
orders = con.execute("SELECT * FROM marts.period_orders").df()
cohort = con.execute("SELECT * FROM marts.customer_first_order WHERE in_h3_cohort").df()
print("Заказов в периоде:", len(orders), "| клиентов в когорте H3:", len(cohort))

def pct(x):
    return f"{100 * x:.2f}%"

rev = orders.dropna(subset=['review_score'])
is_late = rev['is_late'].astype(bool)
late = rev.loc[is_late, "review_score"]
ontime = rev.loc[~is_late, "review_score"]

diff = late.mean() - ontime.mean()
se = np.sqrt(late.var(ddof=1) / len(late) + ontime.var(ddof=1) / len(ontime))
mw = stats.mannwhitneyu(late, ontime, alternative='two-sided')
prob_lower = 1 - mw.statistic / (len(late) * len(ontime))

print("H1: оценка при задержке и без")
print(f"Заказов с оценкой: с задержкой {len(late)}, вовремя {len(ontime)}")
print(f"Средняя оценка: с задержкой {late.mean():.2f}, вовремя {ontime.mean():.2f}")
print(f"Разность средних: {diff:.2f} (95% ДИ {diff - 1.96 * se:.2f} ... {diff + 1.96 * se:.2f})")
print(f"Тест Манна-Уитни: p = {mw.pvalue:.3g}")
print(f"Вероятность, что случайный опоздавший заказ получит оценку ниже вовремя доставленного: {prob_lower:.3g}")

bad_l, bad_o = int((late <= 2).sum()), int((ontime <= 2).sum())
r = compare_props(bad_l, len(late), bad_o, len(ontime))
print(f"Доля плохих оценок (1-2): с задержкой {pct(r['p1'])}, вовремя {pct(r['p2'])}")
print(f"Разность: {pct(r['diff'])} (95% ДИ {pct(r['ci_low'])}...{pct(r['ci_high'])}), p = {r['p_value']:.3g}")

g = cohort.assign(is_late=cohort["is_late"].astype(bool)).groupby("is_late")["has_repeat_180"].agg(["sum", "count"])
x_on, n_on = int(g.loc[False, "sum"]), int(g.loc[False, "count"])
x_late, n_late = int(g.loc[True, "sum"]), int(g.loc[True, "count"])
r = compare_props(x_on, n_on, x_late, n_late)
mde = min_detectable_diff(x_on / n_on, n_on, n_late)

print("\nH3: Повторная покупка за 180 дней")
print(f"Вовремя {x_on} из {n_on} ({pct(r['p1'])}); с задержкой: {x_late} из {n_late} ({pct(r['p2'])})")
print(f"Разность (вовремя минус с задержкой): {pct(r['ci_high'])}")
print(f"z = {r['z']:.2f}, p = {r['p_value']:.4f}")
print(f"Недостаточно мощности" if r['diff'] < mde else "Мощности достаточно", "для наблюдаемой разности")
print(f"Недополучено повторных покупателей: около {n_late * r['diff']:.0f}")

cohort['review_score'] = pd.to_numeric(cohort['review_score'], errors='coerce')
bad = cohort[cohort['review_score'] <= 2]
good = cohort[cohort['review_score'] >= 4]
r = compare_props(int(good['has_repeat_180'].sum()), len(good), int(bad['has_repeat_180'].sum()), len(bad))

print("\nH2: Повторная покупка по оценке первого заказа")
print(f"Хорошая оценка (4-5): {pct(r['p1'])} из {len(good)}; плохая (1-2): {pct(r['p2'])} из {len(bad)}")
print(f"Разность: {pct(r['p1'])} (95% ДИ {pct(r['ci_low'])} ... {pct(r['ci_high'])}), p = {r['p_value']:.4f}")