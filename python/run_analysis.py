"""
Runner cho toàn bộ pipeline phân tích Grocery Sales.

Mỗi file SQL trong thư mục SQL/ được chia thành các khối bằng chỉ thị comment:
    -- @exec              -> câu lệnh DDL/DML/SET, chỉ thực thi
    -- @query: <name>     -> câu SELECT, kết quả được lưu ra outputs/tables/<name>.csv

Tất cả các khối trong cùng một lần chạy dùng chung 1 connection, nên biến
session MySQL (SET @p_start = ...) có hiệu lực xuyên suốt file.

Cách dùng:
    python python/run_analysis.py                 # chạy 01 -> 05 (cần fact_sales đã build)
    python python/run_analysis.py --build         # build lại fact_sales trước rồi chạy 01 -> 05
    python python/run_analysis.py 02 03           # chỉ chạy các file có tiền tố 02, 03
"""

import argparse
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "SQL"
OUT_DIR = ROOT / "outputs" / "tables"

BUILD_FILE = "00_build_fact_sales.sql"
ANALYSIS_FILES = [
    "01_revenue_timeline.sql",
    "02_product_analysis.sql",
    "03_customer_behavior.sql",
    "04_employee_kpi.sql",
    "05_geo_analysis.sql",
]

DIRECTIVE = re.compile(r"^--\s*@(exec|query)\s*(?::\s*(\w+))?\s*$", re.MULTILINE)


def get_engine():
    load_dotenv(ROOT / "python" / ".env")
    user = os.getenv("DB_USER") or "root"
    pwd = quote_plus(os.getenv("DB_PASSWORD") or "")
    host = os.getenv("DB_HOST") or "localhost"
    port = os.getenv("DB_PORT") or "3306"
    name = os.getenv("DB_NAME") or "grocery_sales_db"
    return create_engine(f"mysql+pymysql://{user}:{pwd}@{host}:{port}/{name}")


def parse_blocks(sql_text: str):
    """Trả về list (kind, name, sql) theo thứ tự xuất hiện trong file."""
    matches = list(DIRECTIVE.finditer(sql_text))
    blocks = []
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(sql_text)
        body = sql_text[start:end].strip()
        # bỏ các dòng comment đứng cuối khối (thuộc về khối kế tiếp) và dấu ';'
        lines = body.splitlines()
        while lines and (not lines[-1].strip() or lines[-1].strip().startswith("--")):
            lines.pop()
        body = "\n".join(lines).rstrip().rstrip(";")
        if body:
            blocks.append((m.group(1), m.group(2), body))
    return blocks


def run_file(conn, path: Path, failures: list):
    print(f"\n=== {path.name} ===")
    for kind, name, sql in parse_blocks(path.read_text(encoding="utf-8")):
        t0 = time.time()
        label = name if kind == "query" else sql.strip().splitlines()[0][:70]
        # Một khối lỗi không được làm dừng cả pipeline: ghi lại lỗi rồi chạy tiếp khối sau.
        try:
            # text(): SQLAlchemy tự escape '%' cho driver pymysql; '\:' để ':' không bị hiểu là bind param
            if kind == "exec":
                conn.execute(text(sql.replace(":", r"\:")))
                conn.commit()
                print(f"  [exec ] {label:<70s} {time.time() - t0:6.1f}s")
            else:
                df = pd.read_sql(text(sql.replace(":", r"\:")), conn)
                df.to_csv(OUT_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
                print(f"  [query] {label:<70s} {time.time() - t0:6.1f}s  ({len(df):,} rows)")
        except Exception as e:
            conn.rollback()
            msg = str(getattr(e, "orig", e)).splitlines()[0]
            print(f"  [ERROR] {label:<70s} -> {msg}")
            failures.append((path.name, label, msg))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prefixes", nargs="*", help="chỉ chạy file có tiền tố này (vd: 01 03)")
    ap.add_argument("--build", action="store_true", help="build lại bảng fact_sales trước")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files = ([BUILD_FILE] if args.build else []) + ANALYSIS_FILES
    if args.prefixes:
        files = [f for f in files if any(f.startswith(p) for p in args.prefixes)]

    engine = get_engine()
    t0 = time.time()
    failures = []
    with engine.connect() as conn:
        for f in files:
            run_file(conn, SQL_DIR / f, failures)
    print(f"\nHoàn tất trong {time.time() - t0:.1f}s. Kết quả: {OUT_DIR}")
    if failures:
        print(f"\n{len(failures)} khối bị lỗi:")
        for fname, label, msg in failures:
            print(f"  - {fname} | {label} -> {msg}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
