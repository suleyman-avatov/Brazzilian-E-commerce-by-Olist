import os
import sys

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

if os.path.basename(os.getcwd()) == "analysis":
    os.chdir("..")
sys.path.append("scripts")

project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, project_root)

import scripts
from scripts.stats_helpers import compare_props, repeat_flags

os.makedirs("assets", exist_ok=True)
con = duckdb.connect("data/olist.duckdb", read_only=True)
plt.rcParams.update({"font.size": 11, "axes.spines.top": False, "axes.spines.right": False})
RED, BLUE, GRAY = "#c0392b", "#2e6da4", "#8a8f98"


def save(fig, name):
    fig.tight_layout()
    fig.savefig(f"assets/{name}", dpi=150)
    plt.close(fig)
    print("сохранён assets/" + name)

def diff_ci(f, group_col):
    g = f.groupby(group_col)["repeat"].agg(["sum", "count"])
    r = compare_props(int(g.loc[False, "sum"]), int(g.loc[False, "count"]),
                      int(g.loc[True, "sum"]), int(g.loc[True, "count"]))
    return 100 * r["diff"], 100 * r["ci_low"], 100 * r["ci_high"]


sev = con.execute("SELECT * FROM marts.delay_severity ORDER BY delay_bucket").df()
sev["label"] = sev["delay_bucket"].str[2:]
colors = [BLUE if i < 3 else RED for i in range(len(sev))]

fig, ax = plt.subplots(figsize=(9, 4.8))
bars = ax.barh(sev["label"], sev["avg_score"], color=colors)
ax.invert_yaxis()
ax.set_xlim(0, 6.8)
ax.set_xlabel("Средняя оценка заказа (1-5)")
ax.set_title("Оценка падает с первых дней опоздания и резко после 4 дней")
for bar, score, bad in zip(bars, sev["avg_score"], sev["bad_score_pct"]):
    ax.text(score + 0.06, bar.get_y() + bar.get_height() / 2,
            f"{score:.2f}  ({bad:.0f}% плохих оценок)", va="center", fontsize=10)
save(fig, "fig1_score_by_delay.png")
plt.show()

pm = con.execute("SELECT * FROM marts.promise_vs_actual ORDER BY purchase_month").df()
pm["month"] = pd.to_datetime(pm["purchase_month"]).dt.strftime("%Y-%m")

fig, ax = plt.subplots(figsize=(10, 4.8))
ax2 = ax.twinx()
ax2.bar(pm["month"], pm["late_pct"], color=RED, alpha=0.25, label="Доля задержек, % (правая ось)")
ax2.set_ylabel("Доля задержек, %")
ax2.set_ylim(0, 32)
ax2.spines["right"].set_visible(True)
ax.plot(pm["month"], pm["avg_promised_days"], color=BLUE, marker="o", label="Обещанный срок, дней")
ax.plot(pm["month"], pm["avg_delivery_days"], color="black", marker="o", label="Фактический срок, дней")
ax.set_ylabel("Дней")
ax.set_zorder(ax2.get_zorder() + 1)
ax.patch.set_visible(False)
ax.set_title("Задержки растут, когда доставка замедляется или запас обещания сокращается")
ax.tick_params(axis="x", rotation=60)
h1, l1 = ax.get_legend_handles_labels()
h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper right", fontsize=9, frameon=False)
save(fig, "fig2_promise_vs_actual.png")
plt.show()

dist = con.execute("""
    WITH q AS (
      SELECT *, NTILE(5) OVER (ORDER BY distance_km) AS distance_quintile
      FROM marts.period_orders
      WHERE distance_km IS NOT NULL
    ),
    g AS (
      SELECT *,
             CASE WHEN purchase_month BETWEEN DATE '2017-05-01' AND DATE '2017-10-01' THEN '1 Спокойный период (май-окт 2017)'
                  WHEN purchase_month = DATE '2017-11-01' THEN '2 Ноябрь 2017'
                  WHEN purchase_month BETWEEN DATE '2018-02-01' AND DATE '2018-03-01' THEN '3 Февраль-март 2018'
                  WHEN purchase_month = DATE '2018-08-01' THEN '4 Август 2018'
             END AS period_group
      FROM q
    )
    SELECT period_group, distance_quintile,
           100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*) AS late_pct
    FROM g
    WHERE period_group IS NOT NULL
    GROUP BY 1, 2
    ORDER BY 1, 2
""").df()
styles = {"1": (GRAY, "-"), "2": (RED, "-"), "3": ("#e67e22", "-"), "4": (BLUE, "--")}

fig, ax = plt.subplots(figsize=(9, 4.8))
for grp, d in dist.groupby("period_group"):
    color, ls = styles[grp[0]]
    ax.plot(d["distance_quintile"], d["late_pct"], marker="o", color=color, linestyle=ls, label=grp[2:])
ax.set_xticks([1, 2, 3, 4, 5])
ax.set_xticklabels(["1\n(ближние)", "2", "3", "4", "5\n(дальние)"])
ax.set_xlabel("Квинтиль расстояния между продавцом и покупателем")
ax.set_ylabel("Доля задержек, %")
ax.set_ylim(bottom=0)
ax.set_title("В пики страдают маршруты дальше 116 км, в августе 2018 ближние")
ax.legend(frameon=False, fontsize=9)
save(fig, "fig3_late_by_distance.png")
plt.show()

st = con.execute("""
    SELECT customer_unique_id, order_id, order_purchase_timestamp, purchase_date,
           purchase_month, is_late, delay_days, order_value
    FROM staging.stg_orders
""").df()

rows = []
base = repeat_flags(st, 180, False)
base["is_late"] = base["is_late"].astype(bool)
cohort = base[base["in_cohort"]].copy()
rows.append(("Основной вариант (180 дней)", *diff_ci(cohort, "is_late")))

f90 = repeat_flags(st, 90, False)
f90["is_late"] = f90["is_late"].astype(bool)
rows.append(("Окно 90 дней", *diff_ci(f90[f90["in_cohort"]].copy(), "is_late")))

fsd = repeat_flags(st, 180, True)
fsd["is_late"] = fsd["is_late"].astype(bool)
rows.append(("Заказы того же дня как повторные", *diff_ci(fsd[fsd["in_cohort"]].copy(), "is_late")))

severe = cohort[(cohort["delay_days"] <= 0) | (cohort["delay_days"] >= 4)].copy()
severe["late4"] = severe["delay_days"] >= 4
rows.append(("Только задержки 4+ дня", *diff_ci(severe, "late4")))

peak = ["2017-11", "2018-02", "2018-03"]
calm = cohort[~cohort["purchase_month"].astype(str).str[:7].isin(peak)].copy()
rows.append(("Без пиковых месяцев", *diff_ci(calm, "is_late")))

fo = pd.DataFrame(rows, columns=["label", "diff", "lo", "hi"])
fig, ax = plt.subplots(figsize=(10, 4.6))
ypos = range(len(fo))
ax.errorbar(fo["diff"], list(ypos), xerr=[fo["diff"] - fo["lo"], fo["hi"] - fo["diff"]],
            fmt="o", color=BLUE, ecolor=BLUE, capsize=4)
ax.axvline(0, color=RED, linestyle="--", linewidth=1)
ax.set_yticks(list(ypos))
ax.set_yticklabels(fo["label"])
ax.invert_yaxis()
ax.set_xlabel("Разность доли повторных покупок, п.п.\n(вовремя минус с задержкой, 95% ДИ)")
ax.set_title("Эффект на возврат клиентов небольшой,\nстатистически не подтверждён")
save(fig, "fig4_h3_robustness.png")
plt.show()