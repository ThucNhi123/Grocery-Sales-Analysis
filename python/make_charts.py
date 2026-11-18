"""
Generate report charts from the CSV files in outputs/tables/.
Run after run_analysis.py:
    python python/make_charts.py
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
TBL = ROOT / "outputs" / "tables"
OUT = ROOT / "outputs" / "charts"
OUT.mkdir(parents=True, exist_ok=True)

plt.rcParams.update({
    "figure.dpi": 110, "savefig.dpi": 140, "font.size": 10,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.titleweight": "bold", "axes.titlesize": 12,
})
C_MAIN, C_ACC, C_NEG, C_GREY = "#2563eb", "#f59e0b", "#dc2626", "#9ca3af"

# English labels for categories that the SQL outputs in Vietnamese
QUADRANT_EN = {
    "1": "1. Very high demand - Low value (Traffic driver)",
    "2": "2. High demand - High value (Star)",
    "3": "3. High demand - Low value (Volume)",
    "4": "4. Low demand - High value (Niche premium)",
    "5": "5. Low demand - Low value (Review / Delist)",
}
STRATEGY_EN = {
    "Star": "Star - Invest to expand",
    "Cash Cow": "Cash Cow - Maintain & optimize",
    "Rising": "Rising - Accelerate growth",
    "Watchlist": "Watchlist - Re-evaluate",
    "Core": "Core - Stable",
}


def t(name):
    return pd.read_csv(TBL / f"{name}.csv")


def millions(x, _=None):
    return f"{x / 1e6:,.0f}M"


def save(fig, name):
    fig.tight_layout()
    fig.savefig(OUT / f"{name}.png", bbox_inches="tight")
    plt.close(fig)
    print("  saved", name)


# ---------------- Case 1: Revenue over time ----------------
def ch_monthly_revenue():
    df = t("t1_1_monthly_revenue")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    colors = [C_MAIN if s == "Full" else C_GREY for s in df.MonthStatus]
    bars = ax.bar(df.SalesMonth, df.NetRevenue, color=colors)
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(millions))
    ax.set_ylabel("Net revenue (USD)")
    for b, v in zip(bars, df.NetRevenue):
        ax.text(b.get_x() + b.get_width() / 2, v, f"{v / 1e6:,.1f}M", ha="center", va="bottom", fontsize=9)
    ax2 = ax.twinx()
    ax2.plot(df.SalesMonth, df.AvgDailyNetRevenue, color=C_ACC, marker="o", lw=2, label="Avg daily net revenue")
    ax2.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.2f}M"))
    ax2.set_ylim(df.AvgDailyNetRevenue.min() * 0.97, df.AvgDailyNetRevenue.max() * 1.03)
    ax2.spines["right"].set_visible(True)
    ax2.legend(loc="lower left")
    ax.set_title("Monthly net revenue (May has only 9 days of data - grey)")
    save(fig, "01_monthly_revenue")


def ch_daily_revenue():
    df = t("t1_1_daily_revenue")
    df["SalesDay"] = pd.to_datetime(df.SalesDay)
    fig, ax = plt.subplots(figsize=(11, 4))
    ax.plot(df.SalesDay, df.NetRevenue, color=C_GREY, lw=1, label="Daily net revenue")
    ax.plot(df.SalesDay, df.MA7_NetRevenue, color=C_MAIN, lw=2.2, label="7-day moving average")
    out = df[df.ZScore.abs() >= 2]
    ax.scatter(out.SalesDay, out.NetRevenue, color=C_NEG, zorder=3, label="Outlier days (|z| ≥ 2)")
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.1f}M"))
    ax.legend(loc="lower left")
    ax.set_title("Daily net revenue, 01 Jan - 09 May 2018")
    save(fig, "02_daily_revenue")


def ch_category_share():
    df = t("t1_2_category_monthly_share")
    pv = df.pivot(index="SalesMonth", columns="CategoryName", values="SharePct")
    pv = pv[pv.mean().sort_values(ascending=False).index]
    fig, axes = plt.subplots(1, 2, figsize=(13, 4.8), gridspec_kw={"width_ratios": [1.1, 1]})
    cmap = plt.get_cmap("tab20")
    bottom = np.zeros(len(pv))
    for i, c in enumerate(pv.columns):
        axes[0].bar(pv.index, pv[c], bottom=bottom, label=c, color=cmap(i))
        bottom += pv[c].values
    axes[0].set_ylim(0, 100)
    axes[0].yaxis.set_major_formatter(mtick.PercentFormatter())
    axes[0].legend(bbox_to_anchor=(1.0, 1), loc="upper left", fontsize=8)
    axes[0].set_title("Revenue mix by category (%)")
    for i, c in enumerate(pv.columns):
        axes[1].plot(pv.index, pv[c], marker="o", color=cmap(i), lw=1.6)
        axes[1].text(len(pv) - 1 + 0.08, pv[c].iloc[-1], c, fontsize=7, va="center", color=cmap(i))
    axes[1].yaxis.set_major_formatter(mtick.PercentFormatter())
    axes[1].set_title("Category share over time")
    axes[1].set_xlim(-0.2, len(pv) - 0.2 + 0.9)
    save(fig, "03_category_share")


# ---------------- Case 2: Products ----------------
def ch_top_bottom():
    df = t("t2_1_top5_bottom5")
    df["Label"] = df.ProductName.str.slice(0, 32)
    is_bottom = df.GroupName.str.contains("kém|Bottom", case=False)
    top = df[~is_bottom].iloc[::-1]
    bot = df[is_bottom].iloc[::-1]
    fig, axes = plt.subplots(1, 2, figsize=(13, 4.2))
    axes[0].barh(top.Label, top.NetRevenue, color=C_MAIN)
    axes[0].set_title("Top 5 products by net revenue (Jan-Apr)")
    axes[1].barh(bot.Label, bot.NetRevenue, color=C_NEG)
    axes[1].set_title("Bottom 5 products by net revenue (Jan-Apr)")
    for ax, d in ((axes[0], top), (axes[1], bot)):
        ax.xaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.1f}M" if x >= 1e6 else f"{x / 1e3:,.0f}K"))
        for y, (v, p) in enumerate(zip(d.NetRevenue, d.ListPrice)):
            ax.text(v, y, f"  price {p:,.2f}", va="center", fontsize=8)
    save(fig, "04_top_bottom_products")


def ch_pareto():
    df = t("t2_1_product_ranking")
    fig, ax = plt.subplots(figsize=(10, 4.2))
    colors = df.ABC_Class.map({"A": C_MAIN, "B": C_ACC, "C": C_NEG})
    ax.bar(df.RevenueRank, df.NetRevenue, color=colors, width=1.0)
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.1f}M"))
    ax2 = ax.twinx()
    ax2.plot(df.RevenueRank, df.CumSharePct, color="black", lw=1.5)
    ax2.axhline(80, ls="--", color=C_GREY)
    ax2.yaxis.set_major_formatter(mtick.PercentFormatter())
    ax2.spines["right"].set_visible(True)
    ax.set_xlabel("Product rank")
    ax.set_title("Revenue Pareto of 452 products - class A (blue) / B (orange) / C (red)")
    save(fig, "05_product_pareto")


def ch_demand_value():
    df = t("t2_2_demand_value_matrix")
    df["Quadrant"] = df.Quadrant.str[0].map(QUADRANT_EN)
    fig, ax = plt.subplots(figsize=(9.5, 6))
    palette = {q: c for q, c in zip(sorted(df.Quadrant.unique()), [C_NEG, "#16a34a", C_ACC, C_MAIN, C_GREY])}
    for q, d in df.groupby("Quadrant"):
        ax.scatter(d.TotalUnits, d.NetRevenuePerUnit, s=18, alpha=0.75, color=palette[q], label=q)
    ax.axvline(df.TotalUnits.median(), ls="--", color=C_GREY)
    ax.axhline(df.NetRevenuePerUnit.median(), ls="--", color=C_GREY)
    ax.set_xlabel("Total units sold (Jan-Apr)")
    ax.set_ylabel("Net revenue per unit (USD)")
    ax.legend(fontsize=8, loc="upper left", bbox_to_anchor=(1, 1))
    ax.set_title("Demand x Unit value matrix (each dot = 1 product)")
    save(fig, "06_demand_value_matrix")


def ch_class():
    df = t("t2_3_class_performance").set_index("Class").loc[["High", "Medium", "Low"]]
    x = np.arange(len(df))
    w = 0.26
    fig, ax = plt.subplots(figsize=(8, 4.2))
    for i, (col, lab, c) in enumerate([("PctProducts", "% of SKUs", C_GREY),
                                       ("PctUnits", "% of units", C_ACC),
                                       ("PctRevenue", "% of revenue", C_MAIN)]):
        b = ax.bar(x + (i - 1) * w, df[col], w, label=lab, color=c)
        ax.bar_label(b, fmt="%.1f", fontsize=8)
    ax.set_xticks(x, df.index)
    ax.yaxis.set_major_formatter(mtick.PercentFormatter())
    ax.legend()
    ax.set_title("Impact of product Class: share of SKUs vs units vs revenue")
    save(fig, "07_class_performance")


# ---------------- Case 3: Customers ----------------
def ch_segments():
    df = t("t3_1_segment_summary")
    x = np.arange(len(df))
    fig, ax = plt.subplots(figsize=(10, 4.3))
    b1 = ax.bar(x - 0.2, df.PctCustomers, 0.4, label="% of customers", color=C_GREY)
    b2 = ax.bar(x + 0.2, df.PctRevenue, 0.4, label="% of revenue", color=C_MAIN)
    ax.bar_label(b1, fmt="%.1f", fontsize=8)
    ax.bar_label(b2, fmt="%.1f", fontsize=8)
    ax.set_xticks(x, df.Segment, rotation=12, ha="right")
    ax.yaxis.set_major_formatter(mtick.PercentFormatter())
    ax.legend()
    ax.set_title("Customer segments (Frequency x Monetary)")
    save(fig, "08_customer_segments")


def ch_fm_grid():
    df = t("t3_1_fm_grid")
    pv = df.pivot(index="F_Score", columns="M_Score", values="NumCustomers").sort_index(ascending=False)
    fig, ax = plt.subplots(figsize=(5.8, 4.6))
    im = ax.imshow(pv.values, cmap="Blues")
    ax.set_xticks(range(4), [f"M{c}" for c in pv.columns])
    ax.set_yticks(range(4), [f"F{r}" for r in pv.index])
    for i in range(4):
        for j in range(4):
            ax.text(j, i, f"{pv.values[i, j]:,}", ha="center", va="center",
                    color="white" if pv.values[i, j] > pv.values.max() * 0.6 else "black", fontsize=9)
    fig.colorbar(im, ax=ax, shrink=0.8)
    ax.set_title("Number of customers by F x M score")
    save(fig, "09_fm_grid")


# ---------------- Case 4: Employees ----------------
def ch_employee():
    df = t("t4_2_performance_tiers").sort_values("NetRevenue")
    cmap = {"Top Performer": "#16a34a", "Meets Expectation": C_GREY, "Underperformer": C_NEG}
    fig, ax = plt.subplots(figsize=(10, 6.5))
    ax.barh(df.EmployeeName + " (#" + df.SalesPersonID.astype(str) + ")", df.NetRevenue,
            color=df.PerformanceTier.map(cmap))
    avg = df.NetRevenue.mean()
    ax.axvline(avg, ls="--", color="black", lw=1)
    ax.text(avg, len(df) - 0.3, " Team avg", fontsize=8)
    lo = df.NetRevenue.min() * 0.985
    ax.set_xlim(lo, df.NetRevenue.max() * 1.006)
    ax.xaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.1f}M"))
    for y, (v, p) in enumerate(zip(df.NetRevenue, df.RevenuePctVsTeamAvg)):
        ax.text(v, y, f" {p:+.2f}%", va="center", fontsize=8)
    handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in cmap.values()]
    ax.legend(handles, cmap.keys(), loc="lower right")
    ax.set_title("Net revenue by employee & performance tier (x-axis does not start at 0)")
    save(fig, "10_employee_performance")


def ch_employee_heatmap():
    df = t("t4_3_employee_month_pivot").set_index("SalesPersonID")
    cols = ["2018-01", "2018-02", "2018-03", "2018-04"]
    m = df[cols]
    idx = m.div(m.mean(axis=0), axis=1) * 100 - 100   # % difference vs team average in that month
    fig, ax = plt.subplots(figsize=(6.5, 8))
    lim = np.nanmax(np.abs(idx.values))
    im = ax.imshow(idx.values, cmap="RdYlGn", vmin=-lim, vmax=lim, aspect="auto")
    ax.set_xticks(range(len(cols)), cols)
    ax.set_yticks(range(len(idx)), [f"#{i} {n}" for i, n in zip(idx.index, df.EmployeeName)], fontsize=8)
    for i in range(idx.shape[0]):
        for j in range(idx.shape[1]):
            ax.text(j, i, f"{idx.values[i, j]:+.1f}", ha="center", va="center", fontsize=7)
    fig.colorbar(im, ax=ax, shrink=0.6, label="% vs team average (avg daily revenue)")
    ax.set_title("Monthly employee performance vs team average")
    save(fig, "11_employee_monthly_heatmap")


# ---------------- Case 5: Geography ----------------
def ch_cities():
    df = t("t5_1_city_ranking")
    top = df.head(15).iloc[::-1]
    bot = df.tail(10).iloc[::-1]
    fig, axes = plt.subplots(1, 2, figsize=(13, 5.2))
    axes[0].barh(top.CityName, top.NetRevenue, color=C_MAIN)
    axes[0].set_title("Top 15 cities by net revenue")
    axes[1].barh(bot.CityName, bot.NetRevenue, color=C_NEG)
    axes[1].set_title("Bottom 10 cities by net revenue")
    for ax in axes:
        ax.xaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.0f}M"))
        ax.set_xlim(df.NetRevenue.min() * 0.9, df.NetRevenue.max() * 1.03)
    save(fig, "12_city_revenue")


def ch_volume_index():
    df = t("t5_2_volume_comparison").sort_values("VolumeIndex")
    fig, ax = plt.subplots(figsize=(13, 4.3))
    colors = np.where(df.VolumeIndex >= 100, C_MAIN, C_NEG)
    ax.bar(df.CityName, df.VolumeIndex - 100, color=colors)
    ax.axhline(0, color="black", lw=0.8)
    ax.set_ylabel("Volume index - 100 (pp vs average)")
    ax.tick_params(axis="x", rotation=90, labelsize=6.5)
    ax.set_title(f"Units sold vs the average of {len(df)} cities")
    save(fig, "13_city_volume_index")


def ch_scorecard():
    df = t("t5_3_market_scorecard")
    df["StrategicGroup"] = df.StrategicGroup.str.split(" - ").str[0].map(STRATEGY_EN)
    pal = {g: c for g, c in zip(sorted(df.StrategicGroup.unique()),
                                ["#16a34a", C_MAIN, C_ACC, "#7c3aed", C_NEG])}
    fig, ax = plt.subplots(figsize=(10, 6))
    for g, d in df.groupby("StrategicGroup"):
        ax.scatter(d.NetRevenue, d.GrowthPct_MarApr_vs_JanFeb, s=d.ActivationRatePct * 0 + 40,
                   color=pal[g], label=g, alpha=0.85)
    for _, r in df[(df.RevenueRank <= 5) | (df.RevenueRank >= len(df) - 2)].iterrows():
        ax.annotate(r.CityName, (r.NetRevenue, r.GrowthPct_MarApr_vs_JanFeb), fontsize=7,
                    xytext=(3, 3), textcoords="offset points")
    ax.axhline(df.GrowthPct_MarApr_vs_JanFeb.median(), ls="--", color=C_GREY)
    ax.axvline(df.NetRevenue.quantile(0.75), ls="--", color=C_GREY)
    ax.xaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"{x / 1e6:,.0f}M"))
    ax.set_xlabel("Market size (net revenue)")
    ax.set_ylabel("Avg daily revenue growth, Mar-Apr vs Jan-Feb (%)")
    ax.legend(fontsize=8)
    ax.set_title("Market strategy matrix: Size x Momentum\n(relative positions only - all 96 cities sit in a narrow band)")
    save(fig, "14_market_strategy_matrix")


if __name__ == "__main__":
    for fn in [ch_monthly_revenue, ch_daily_revenue, ch_category_share, ch_top_bottom, ch_pareto,
               ch_demand_value, ch_class, ch_segments, ch_fm_grid, ch_employee, ch_employee_heatmap,
               ch_cities, ch_volume_index, ch_scorecard]:
        try:
            fn()
        except FileNotFoundError as e:  # one failing chart must not block the others
            print(f"  [SKIP] {fn.__name__}: missing table {Path(e.filename).name} - run run_analysis.py first")
        except Exception as e:
            print(f"  [WARN] {fn.__name__}: {type(e).__name__}: {e}")
