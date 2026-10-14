import numpy as np
import pandas as pd
from scipy import stats
from scipy.optimize import brentq


def wilson(x, n, alpha=0.05):
    """Доверительный интервал Уилсона для доли x/n."""
    z = stats.norm.ppf(1 - alpha / 2)
    p = x / n
    denom = 1 + z**2 / n
    center = (p + z**2 / (2 * n)) / denom
    half = z * np.sqrt(p * (1 - p) / n + z**2 / (4 * n**2)) / denom
    return center - half, center + half


def compare_props(x1, n1, x2, n2, alpha=0.05):
    """Сравнение двух долей (группа 1 минус группа 2).

    Возвращает доли, разность, доверительный интервал разности (метод Ньюкомба),
    z-статистику и двусторонний p-value (z-тест с объединённой дисперсией).
    """
    p1, p2 = x1 / n1, x2 / n2
    d = p1 - p2
    l1, u1 = wilson(x1, n1, alpha)
    l2, u2 = wilson(x2, n2, alpha)
    lo = d - np.sqrt((p1 - l1) ** 2 + (u2 - p2) ** 2)
    hi = d + np.sqrt((u1 - p1) ** 2 + (p2 - l2) ** 2)
    p_pool = (x1 + x2) / (n1 + n2)
    se_pool = np.sqrt(p_pool * (1 - p_pool) * (1 / n1 + 1 / n2))
    z = d / se_pool
    p_value = 2 * (1 - stats.norm.cdf(abs(z)))
    return {"p1": p1, "p2": p2, "diff": d, "ci_low": lo, "ci_high": hi,
            "z": z, "p_value": p_value}


def min_detectable_diff(p_base, n1, n2, alpha=0.05, power=0.8):
    """Минимальная разность долей, которую тест обнаруживает с заданной мощностью.

    p_base: доля в группе 1 (базовый уровень), n1 и n2: размеры групп.
    """
    z_a = stats.norm.ppf(1 - alpha / 2)
    z_b = stats.norm.ppf(power)

    def f(d):
        p2 = p_base - d
        se = np.sqrt(p_base * (1 - p_base) / n1 + p2 * (1 - p2) / n2)
        return d - (z_a + z_b) * se

    return brentq(f, 1e-6, p_base - 1e-6)


def repeat_flags(st, window=180, same_day=False, start_date="2017-01-01", end_date="2018-08-31"):
    """Первый заказ каждого клиента и признак повторной покупки в окне.

    st: заказы с колонками customer_unique_id, order_id, order_purchase_timestamp, purchase_date.
    window: окно наблюдения в днях после даты первого заказа.
    same_day: считать ли повторной покупкой заказ в тот же календарный день.
    Колонка in_cohort отмечает клиентов, у которых окно целиком укладывается в данные.
    """
    st = st.copy()
    st["purchase_date"] = pd.to_datetime(st["purchase_date"])
    st = st.sort_values(["customer_unique_id", "order_purchase_timestamp", "order_id"])
    st["rn"] = st.groupby("customer_unique_id").cumcount()
    first = st[st["rn"] == 0].set_index("customer_unique_id")
    later = st[st["rn"] > 0].join(first["purchase_date"].rename("first_date"), on="customer_unique_id")
    gap = (later["purchase_date"] - later["first_date"]).dt.days
    min_gap = 0 if same_day else 1
    repeaters = later.loc[(gap >= min_gap) & (gap <= window), "customer_unique_id"].unique()
    first["repeat"] = first.index.isin(repeaters)
    cutoff = pd.Timestamp(end_date) - pd.Timedelta(days=window)
    first["in_cohort"] = (first["purchase_date"] >= pd.Timestamp(start_date)) & (first["purchase_date"] <= cutoff)
    return first