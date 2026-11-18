"""
SQL performance benchmark: does a covering index speed up the two slowest
steps of the pipeline?

  1. Customer metrics  (03_customer_behavior.sql, ~120 s in the first run)
     GROUP BY CustomerID over 6.7M rows of fact_sales.
  2. Category x month  (01_revenue_timeline.sql, ~30 s per query)
     GROUP BY SalesMonth, CategoryID.

For each case the script
  - drops the test index if it exists and times the query (best of N runs),
  - records the execution plan (EXPLAIN FORMAT=TREE),
  - creates a covering index (timing the build),
  - times the query again and records the new plan.

Results go to outputs/tables/t7_sql_benchmark.csv.

Usage:
    python python/benchmark_sql.py              # keep the new indexes afterwards
    python python/benchmark_sql.py --drop-after # remove them again when done
    python python/benchmark_sql.py --runs 3     # best of 3 runs instead of 2

Note: building each index on 6.7M rows takes a few minutes and uses a few
hundred MB of disk. Run it when nothing else is using the database.
"""

import argparse
import time
from pathlib import Path

import pandas as pd
from sqlalchemy import text

from run_analysis import get_engine  # same .env / connection settings as the pipeline

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "tables" / "t7_sql_benchmark.csv"

CASES = [
    {
        "name": "Customer metrics (GROUP BY CustomerID)",
        "index": "idx_fact_cust_cover",
        "columns": "CustomerID, SalesDay, SalesMonth, ProductID, Quantity, NetRevenue",
        "sql": """
            SELECT CustomerID,
                   COUNT(*), SUM(NetRevenue), SUM(Quantity),
                   COUNT(DISTINCT SalesDay),
                   COUNT(DISTINCT CASE WHEN SalesMonth BETWEEN '2018-01' AND '2018-04'
                                       THEN SalesMonth END),
                   COUNT(DISTINCT ProductID),
                   MIN(SalesDay), MAX(SalesDay)
            FROM fact_sales
            GROUP BY CustomerID
        """,
    },
    {
        "name": "Category x month (GROUP BY SalesMonth, CategoryID)",
        "index": "idx_fact_month_cat_cover",
        "columns": "SalesMonth, CategoryID, SalesDay, Quantity, NetRevenue",
        "sql": """
            SELECT SalesMonth, CategoryID,
                   COUNT(DISTINCT SalesDay), SUM(Quantity), SUM(NetRevenue)
            FROM fact_sales
            WHERE SalesMonth IS NOT NULL
            GROUP BY SalesMonth, CategoryID
        """,
    },
]


def index_exists(conn, name):
    q = text("""SELECT COUNT(*) FROM information_schema.statistics
                WHERE table_schema = DATABASE() AND table_name = 'fact_sales'
                  AND index_name = :n""")
    return conn.execute(q, {"n": name}).scalar() > 0


def drop_index(conn, name):
    if index_exists(conn, name):
        conn.execute(text(f"DROP INDEX {name} ON fact_sales"))
        conn.commit()


def time_query(conn, sql, runs):
    """Best wall-clock time of `runs` executions. The outer COUNT(*) forces the
    full aggregation on the server without sending 100k rows to Python."""
    wrapped = text(f"SELECT COUNT(*) FROM ({sql}) AS t")
    best = None
    for _ in range(runs):
        t0 = time.perf_counter()
        conn.execute(wrapped).scalar()
        elapsed = time.perf_counter() - t0
        best = elapsed if best is None else min(best, elapsed)
    return round(best, 2)


def plan(conn, sql):
    row = conn.execute(text(f"EXPLAIN FORMAT=TREE {sql}")).fetchone()
    first_lines = str(row[0]).strip().splitlines()[:3]
    return " | ".join(line.strip() for line in first_lines)[:300]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=2, help="timed runs per measurement (best is kept)")
    ap.add_argument("--drop-after", action="store_true", help="remove the test indexes at the end")
    args = ap.parse_args()

    results = []
    with get_engine().connect() as conn:
        for c in CASES:
            print(f"\n=== {c['name']} ===")
            drop_index(conn, c["index"])

            before = time_query(conn, c["sql"], args.runs)
            plan_before = plan(conn, c["sql"])
            print(f"  before index : {before:8.2f} s")

            t0 = time.perf_counter()
            conn.execute(text(f"CREATE INDEX {c['index']} ON fact_sales ({c['columns']})"))
            conn.commit()
            build = round(time.perf_counter() - t0, 1)
            print(f"  index build  : {build:8.1f} s  ({c['index']})")

            after = time_query(conn, c["sql"], args.runs)
            plan_after = plan(conn, c["sql"])
            print(f"  after index  : {after:8.2f} s  -> {before / after:.1f}x")

            results.append({
                "Query": c["name"],
                "Index": f"{c['index']} ({c['columns']})",
                "Before_s": before,
                "After_s": after,
                "Speedup_x": round(before / after, 1) if after else None,
                "IndexBuild_s": build,
                "PlanBefore": plan_before,
                "PlanAfter": plan_after,
            })

            if args.drop_after:
                drop_index(conn, c["index"])

    df = pd.DataFrame(results)
    df.to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"\nSaved {OUT}")
    print(df[["Query", "Before_s", "After_s", "Speedup_x"]].to_string(index=False))


if __name__ == "__main__":
    main()
