"""
Impact sizing for the report's recommendations.

Reads the result tables in outputs/tables/ (produced by run_analysis.py) and
estimates how much revenue each recommendation could add or protect, under a
low / base / high assumption. Writes outputs/tables/t6_impact_scenarios.csv.

Run after run_analysis.py:
    python python/impact_scenarios.py

All figures are illustrative what-if estimates of the method, not forecasts:
the dataset appears simulated (see README, Data validation). Each scenario states
its assumption so a reader can challenge it.
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
TBL = ROOT / "outputs" / "tables"

LOW, BASE, HIGH = 0.05, 0.10, 0.15


def t(name):
    return pd.read_csv(TBL / f"{name}.csv")


def main():
    total = t("t1_1_total_revenue_summary").NetRevenue.iloc[0]

    seg = t("t3_1_segment_summary").set_index("Segment")
    low_spend = seg.loc["4. Frequent - Low Spend", "NetRevenue"]

    abc = t("t2_1_abc_summary").set_index("ABC_Class")
    class_c = abc.loc["C", "NetRevenue"]
    total_jan_apr = abc.NetRevenue.sum()

    # No retention scenario: every customer bought in every full month
    # (t3_2_active_months_distribution), so there is no churn to size.
    rows = [
        {
            "Rec": 1,
            "Recommendation": "Upsell the Frequent - Low Spend segment",
            "Type": "Revenue added",
            "Lever": "Average order value of the segment",
            "Assumption": "AOV rises 5% / 10% / 15% at the same order frequency",
            "BaseRevenue": low_spend,
            "PeriodTotal": total,
        },
        {
            "Rec": 2,
            "Recommendation": "Customer acquisition in all cities",
            "Type": "Revenue added",
            "Lever": "Number of customers",
            "Assumption": ("Customer base grows 5% / 10% / 15% at current revenue per customer "
                           "(city revenue follows customer count, r = 0.84)"),
            "BaseRevenue": total,
            "PeriodTotal": total,
        },
        {
            "Rec": 3,
            "Recommendation": "Review pricing of ABC class C (lowest-revenue) products, A/B test first",
            "Type": "Revenue added",
            "Lever": "List price of ABC class C products",
            "Assumption": ("Price +5% / +10% / +15% with units unchanged. Untested: each product "
                           "has a single price, so price elasticity cannot be measured."),
            "BaseRevenue": class_c,
            "PeriodTotal": total_jan_apr,
        },
    ]

    df = pd.DataFrame(rows)
    for label, pct in (("Low", LOW), ("Base", BASE), ("High", HIGH)):
        df[f"Impact_{label}_USD_M"] = (df.BaseRevenue * pct / 1e6).round(0).astype(int)
    # % of total revenue in the same period as the base (Jan-Apr for products)
    df["Impact_Base_PctOfTotal"] = (df.BaseRevenue * BASE * 100 / df.PeriodTotal).round(1)
    df["BaseRevenue_USD_M"] = (df.BaseRevenue / 1e6).round(0).astype(int)
    df = df.drop(columns=["BaseRevenue", "PeriodTotal"])

    out = TBL / "t6_impact_scenarios.csv"
    df.to_csv(out, index=False, encoding="utf-8-sig")

    pd.set_option("display.width", 200, "display.max_colwidth", 60)
    print(df[["Rec", "Recommendation", "BaseRevenue_USD_M", "Impact_Low_USD_M",
              "Impact_Base_USD_M", "Impact_High_USD_M", "Impact_Base_PctOfTotal"]].to_string(index=False))
    print(f"\nTotal net revenue in the period: USD {total / 1e6:,.1f}M")
    print(f"Saved {out}")


if __name__ == "__main__":
    main()
