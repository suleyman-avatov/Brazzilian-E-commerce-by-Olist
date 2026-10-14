import os
import sys

import duckdb
import pandas as pd

if os.path.basename(os.getcwd()) == "analysis":
    os.chdir("..")
sys.path.append("scripts")
from scripts.stats_helpers import compare_props, repeat_flags

con = duckdb.connect("data/olist.duckdb", read_only=True)
st = con.execute("""
    SELECT customer_unique_id, order_id, order_purchase_timestamp, purchase_date,
           purchase_month, is_late, delay_days, order_value
    FROM staging.stg_orders
""").df()
print("Заказов в staging:", len(st))


def pct(x):
    return f"{100 * x:.2f}%"


def report(label, f, group_col):
    """Сравнение доли повторных покупок: группа group_col=False (минус) группа group_col=True."""
    g = f.groupby(group_col)["repeat"].agg(["sum", "count"])
    x0, n0 = int(g.loc[False, "sum"]), int(g.loc[False, "count"])
    x1, n1 = int(g.loc[True, "sum"]), int(g.loc[True, "count"])
    r = compare_props(x0, n0, x1, n1)
    print(f"{label}")
    print(f"  без задержки: {x0} из {n0} ({pct(r['p1'])}); с задержкой: {x1} из {n1} ({pct(r['p2'])})")
    print(f"  разность: {pct(r['diff'])} (95% ДИ {pct(r['ci_low'])} ... {pct(r['ci_high'])}), p = {r['p_value']:.3f}")
    return r


print("\n=== Устойчивость H3 ===")
base = repeat_flags(st, window=180, same_day=False)
base["is_late"] = base["is_late"].astype(bool)
cohort = base[base["in_cohort"]].copy()

report("1. Основной вариант (окно 180 дней, заказ в другой день)", cohort, "is_late")

f90 = repeat_flags(st, window=90, same_day=False)
f90["is_late"] = f90["is_late"].astype(bool)
report("2. Окно 90 дней", f90[f90["in_cohort"]].copy(), "is_late")

fsd = repeat_flags(st, window=180, same_day=True)
fsd["is_late"] = fsd["is_late"].astype(bool)
report("3. Заказы того же дня считаются повторными", fsd[fsd["in_cohort"]].copy(), "is_late")

severe = cohort[(cohort["delay_days"] <= 0) | (cohort["delay_days"] >= 4)].copy()
severe["late4"] = severe["delay_days"] >= 4
report("4. Только тяжёлые задержки (4+ дня) против заказов вовремя", severe, "late4")

peak = ["2017-11", "2018-02", "2018-03"]
calm = cohort[~cohort["purchase_month"].astype(str).str[:7].isin(peak)].copy()
report("5. Без пиковых месяцев (ноябрь 2017, февраль и март 2018)", calm, "is_late")

repeat_rev = con.execute("""
    SELECT AVG(repeat_revenue_180) AS avg_rev
    FROM marts.customer_first_order
    WHERE in_h3_cohort AND has_repeat_180
""").df()["avg_rev"].iloc[0]
first_rev = con.execute("""
    SELECT SUM(first_order_value) AS rev
    FROM marts.customer_first_order
    WHERE in_h3_cohort
""").df()["rev"].iloc[0]

g = cohort.groupby("is_late")["repeat"].agg(["sum", "count"])
r = compare_props(int(g.loc[False, "sum"]), int(g.loc[False, "count"]),
                  int(g.loc[True, "sum"]), int(g.loc[True, "count"]))
n_late = int(g.loc[True, "count"])
lost = [n_late * r["ci_low"], n_late * r["diff"], n_late * r["ci_high"]]

print("\n=== Денежная оценка потери от пониженного возврата (180 дней) ===")
print(f"Средняя выручка повторных покупок на одного вернувшегося клиента: {repeat_rev:.0f}")
print(f"Недополучено повторных покупателей: {lost[1]:.0f} (интервал от {lost[0]:.0f} до {lost[2]:.0f})")
print(f"Недополученная выручка: {lost[1] * repeat_rev:,.0f} (интервал от {lost[0] * repeat_rev:,.0f} до {lost[2] * repeat_rev:,.0f})")
print(f"Для сравнения: выручка первых заказов когорты {first_rev:,.0f}, оценка потери составляет {100 * lost[1] * repeat_rev / first_rev:.2f}% от неё")