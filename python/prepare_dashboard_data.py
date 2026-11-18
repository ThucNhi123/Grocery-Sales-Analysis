"""
Build clean, English-only CSV extracts for the Tableau Public dashboard.

Reads outputs/tables/ (produced by run_analysis.py) and writes dashboard/data/.
Run after run_analysis.py:
    python python/prepare_dashboard_data.py
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
TBL = ROOT / "outputs" / "tables"
OUT = ROOT / "dashboard" / "data"
OUT.mkdir(parents=True, exist_ok=True)

QUADRANT_EN = {
    "1": "Traffic driver (very high demand, low value)",
    "2": "Star (high demand, high value)",
    "3": "Volume (high demand, low value)",
    "4": "Niche premium (low demand, high value)",
    "5": "Review / Delist (low demand, low value)",
}
STRATEGY_EN = {
    "Star": "Star - Invest to expand",
    "Cash Cow": "Cash Cow - Maintain & optimize",
    "Rising": "Rising - Accelerate growth",
    "Watchlist": "Watchlist - Re-evaluate",
    "Core": "Core - Stable",
}
STABILITY_EN = {"Ổn định cao": "High", "Ổn định trung bình": "Medium", "Biến động cao": "Volatile"}
TREND_EN = {"Tăng": "Up", "Giảm": "Down", "Đi ngang": "Flat"}

# City name in the data -> (name a map can geocode, US state).
# Names such as "Colorado", "Jersey", "Kansas", "Oklahoma" are read as the
# obvious large city; ambiguous ones (Glendale, Aurora, ...) use the largest.
CITY_STATE = {
    "Akron": ("Akron", "OH"), "Albuquerque": ("Albuquerque", "NM"), "Anaheim": ("Anaheim", "CA"),
    "Anchorage": ("Anchorage", "AK"), "Arlington": ("Arlington", "TX"), "Atlanta": ("Atlanta", "GA"),
    "Aurora": ("Aurora", "CO"), "Austin": ("Austin", "TX"), "Bakersfield": ("Bakersfield", "CA"),
    "Baltimore": ("Baltimore", "MD"), "Baton Rouge": ("Baton Rouge", "LA"), "Birmingham": ("Birmingham", "AL"),
    "Boston": ("Boston", "MA"), "Buffalo": ("Buffalo", "NY"), "Charlotte": ("Charlotte", "NC"),
    "Chicago": ("Chicago", "IL"), "Cincinnati": ("Cincinnati", "OH"), "Cleveland": ("Cleveland", "OH"),
    "Colorado": ("Colorado Springs", "CO"), "Columbus": ("Columbus", "OH"),
    "Corpus Christi": ("Corpus Christi", "TX"), "Dallas": ("Dallas", "TX"), "Dayton": ("Dayton", "OH"),
    "Denver": ("Denver", "CO"), "Des Moines": ("Des Moines", "IA"), "Detroit": ("Detroit", "MI"),
    "El Paso": ("El Paso", "TX"), "Fort Wayne": ("Fort Wayne", "IN"), "Fort Worth": ("Fort Worth", "TX"),
    "Fremont": ("Fremont", "CA"), "Fresno": ("Fresno", "CA"), "Garland": ("Garland", "TX"),
    "Glendale": ("Glendale", "AZ"), "Grand Rapids": ("Grand Rapids", "MI"), "Greensboro": ("Greensboro", "NC"),
    "Hialeah": ("Hialeah", "FL"), "Honolulu": ("Honolulu", "HI"), "Houston": ("Houston", "TX"),
    "Indianapolis": ("Indianapolis", "IN"), "Jackson": ("Jackson", "MS"), "Jacksonville": ("Jacksonville", "FL"),
    "Jersey": ("Jersey City", "NJ"), "Kansas": ("Kansas City", "MO"), "Las Vegas": ("Las Vegas", "NV"),
    "Lincoln": ("Lincoln", "NE"), "Little Rock": ("Little Rock", "AR"), "Long Beach": ("Long Beach", "CA"),
    "Los Angeles": ("Los Angeles", "CA"), "Louisville": ("Louisville", "KY"), "Lubbock": ("Lubbock", "TX"),
    "Madison": ("Madison", "WI"), "Memphis": ("Memphis", "TN"), "Mesa": ("Mesa", "AZ"),
    "Miami": ("Miami", "FL"), "Milwaukee": ("Milwaukee", "WI"), "Minneapolis": ("Minneapolis", "MN"),
    "Mobile": ("Mobile", "AL"), "Montgomery": ("Montgomery", "AL"), "Nashville": ("Nashville", "TN"),
    "New Orleans": ("New Orleans", "LA"), "New York": ("New York", "NY"), "Newark": ("Newark", "NJ"),
    "Norfolk": ("Norfolk", "VA"), "Oakland": ("Oakland", "CA"), "Oklahoma": ("Oklahoma City", "OK"),
    "Omaha": ("Omaha", "NE"), "Philadelphia": ("Philadelphia", "PA"), "Phoenix": ("Phoenix", "AZ"),
    "Pittsburgh": ("Pittsburgh", "PA"), "Portland": ("Portland", "OR"), "Raleigh": ("Raleigh", "NC"),
    "Richmond": ("Richmond", "VA"), "Riverside": ("Riverside", "CA"), "Rochester": ("Rochester", "NY"),
    "Sacramento": ("Sacramento", "CA"), "San Antonio": ("San Antonio", "TX"), "San Diego": ("San Diego", "CA"),
    "San Francisco": ("San Francisco", "CA"), "San Jose": ("San Jose", "CA"), "Santa Ana": ("Santa Ana", "CA"),
    "Seattle": ("Seattle", "WA"), "Shreveport": ("Shreveport", "LA"), "Spokane": ("Spokane", "WA"),
    "St. Louis": ("St. Louis", "MO"), "St. Paul": ("St. Paul", "MN"), "St. Petersburg": ("St. Petersburg", "FL"),
    "Stockton": ("Stockton", "CA"), "Tacoma": ("Tacoma", "WA"), "Tampa": ("Tampa", "FL"),
    "Toledo": ("Toledo", "OH"), "Tucson": ("Tucson", "AZ"), "Tulsa": ("Tulsa", "OK"),
    "Virginia Beach": ("Virginia Beach", "VA"), "Washington": ("Washington", "DC"),
    "Wichita": ("Wichita", "KS"), "Yonkers": ("Yonkers", "NY"),
}


def t(name):
    return pd.read_csv(TBL / f"{name}.csv")


def save(df, name):
    df.to_csv(OUT / f"{name}.csv", index=False, encoding="utf-8")
    print(f"  {name}.csv  ({len(df):,} rows)")


def main():
    m = t("t1_1_monthly_revenue")
    save(pd.DataFrame({
        "Month": m.SalesMonth, "MonthStatus": m.MonthStatus, "DaysWithData": m.DaysWithData,
        "Transactions": m.NumTransactions, "Units": m.TotalUnits, "NetRevenue": m.NetRevenue,
        "AvgDailyRevenue": m.AvgDailyNetRevenue, "MoM_Growth_DailyAvg_Pct": m.MoM_GrowthPct_DailyAvg,
    }), "monthly")

    d = t("t1_1_daily_revenue")
    save(pd.DataFrame({
        "Date": d.SalesDay, "Weekday": d.WeekdayName, "Transactions": d.NumTransactions,
        "NetRevenue": d.NetRevenue, "MA7_Revenue": d.MA7_NetRevenue, "ZScore": d.ZScore,
        "IsOutlier": d.ZScore.abs() >= 2,
    }), "daily")

    c = t("t1_2_category_monthly_share")
    save(c.rename(columns={"SalesMonth": "Month", "CategoryName": "Category", "TotalUnits": "Units",
                           "CategoryRevenue": "NetRevenue"})[
        ["Month", "Category", "Units", "NetRevenue", "SharePct"]], "category_month")

    p = t("t2_1_product_ranking")
    q = t("t2_2_demand_value_matrix")[["ProductID", "NetRevenuePerUnit", "Quadrant"]].copy()
    q["Quadrant"] = q.Quadrant.str[0].map(QUADRANT_EN)
    p = p.merge(q, on="ProductID", how="left")
    save(p.rename(columns={"CategoryName": "Category", "TotalUnits": "Units", "ABC_Class": "ABC",
                           "CumSharePct": "CumulativeSharePct", "RevenueRank": "Rank"})[
        ["Rank", "ProductID", "ProductName", "Category", "Class", "ListPrice", "Units", "NetRevenue",
         "NetRevenuePerUnit", "SharePct", "CumulativeSharePct", "ABC", "Quadrant"]], "products")

    s = t("t3_1_segment_summary").merge(t("t3_3_aov_by_segment")[["Segment", "AvgTransactionsPer30Days"]],
                                         on="Segment")
    save(s[["Segment", "NumCustomers", "PctCustomers", "NetRevenue", "PctRevenue", "AvgFrequency",
            "AvgMonetary", "AvgOrderValue", "AvgTransactionsPer30Days"]], "customer_segments")

    save(t("t3_1_fm_grid")[["F_Score", "M_Score", "NumCustomers", "NetRevenue", "PctRevenue"]], "fm_grid")

    e = t("t4_2_performance_tiers").merge(
        t("t4_3_employee_stability")[["SalesPersonID", "CV_Pct", "StabilityGroup", "TrendDirection",
                                      "BestMonthlyRank", "WorstMonthlyRank"]], on="SalesPersonID")
    e["StabilityGroup"] = e.StabilityGroup.replace(STABILITY_EN)  # also accepts English labels
    e["TrendDirection"] = e.TrendDirection.replace(TREND_EN)
    save(e.rename(columns={"SalesPersonID": "EmployeeID", "RevenuePctVsTeamAvg": "PctVsTeamAvg"})[
        ["CompositeRank", "EmployeeID", "EmployeeName", "BaseCity", "TenureYears", "NetRevenue",
         "NumInvoices", "AvgInvoiceValue", "PctVsTeamAvg", "CompositeScore", "PerformanceTier",
         "CV_Pct", "StabilityGroup", "TrendDirection", "BestMonthlyRank", "WorstMonthlyRank"]], "employees")

    sc = t("t5_3_market_scorecard").merge(t("t5_1_city_ranking")[["CityName", "ActiveCustomers", "TotalUnits"]],
                                          on="CityName")
    sc["StrategicGroup"] = sc.StrategicGroup.str.split(" - ").str[0].map(STRATEGY_EN)
    sc["MapCity"] = sc.CityName.map(lambda x: CITY_STATE[x][0])
    sc["State"] = sc.CityName.map(lambda x: CITY_STATE[x][1])
    sc["Country"] = "United States"
    save(sc.rename(columns={"GrowthPct_MarApr_vs_JanFeb": "GrowthPct", "TotalUnits": "Units"})[
        ["RevenueRank", "CityName", "MapCity", "State", "Country", "NetRevenue", "MarketSharePct", "Units",
         "ActiveCustomers", "RevenuePerCustomer", "AOV", "GrowthPct", "EmployeesBased", "StrategicGroup"]],
        "cities")

    print(f"Saved to {OUT}")


if __name__ == "__main__":
    main()
