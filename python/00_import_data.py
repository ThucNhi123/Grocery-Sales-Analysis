"""
Import the 7 Grocery Sales CSV files into MySQL.
Run SQL/00_create_schema.sql first (it creates the tables and foreign keys).

Usage (from the project root):
    python python/00_import_data.py            # import into empty tables
    python python/00_import_data.py --reset    # empty all tables first, then import

Connection settings are read from python/.env (see python/.env.example).
"""

import argparse
import os
import sys
import time
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

# =====================================================
# 1. CẤU HÌNH KẾT NỐI (đọc từ python/.env)
# =====================================================
ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "raw"          # thư mục chứa 7 file CSV gốc
load_dotenv(ROOT / "python" / ".env")

DB_USER = os.getenv("DB_USER") or "root"
DB_PASSWORD = quote_plus(os.getenv("DB_PASSWORD") or "")   # quote_plus: mật khẩu có ký tự đặc biệt như '@'
DB_HOST = os.getenv("DB_HOST") or "localhost"
DB_PORT = os.getenv("DB_PORT") or "3306"
DB_NAME = os.getenv("DB_NAME") or "grocery_sales_db"

engine = create_engine(f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}")


def check_connection():
    """Kết nối thật sự tới MySQL; dừng ngay với thông báo rõ ràng nếu thất bại."""
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as e:
        sys.exit(f"Cannot connect to MySQL ({DB_HOST}:{DB_PORT}/{DB_NAME}): {e}")
    print(f"Connected to {DB_NAME} on {DB_HOST}:{DB_PORT}")


# =====================================================
# 2. THỨ TỰ IMPORT - PHẢI đúng thứ tự này vì có FK constraint
#    (bảng cha trước, bảng con sau)
# =====================================================
IMPORT_ORDER = [
    "countries",
    "categories",
    "cities",
    "customers",
    "employees",
    "products",
    "sales",
]

# Map tên bảng -> tên file csv (chỉnh lại nếu tên file bạn khác)
FILE_MAP = {
    "countries": "countries.csv",
    "categories": "categories.csv",
    "cities": "cities.csv",
    "customers": "customers.csv",
    "employees": "employees.csv",
    "products": "products.csv",
    "sales": "sales.csv",
}

# Bảng sales rất lớn (~7 triệu dòng) -> import theo chunk để đỡ tốn RAM
CHUNK_SIZE = 50_000


def import_table(table_name: str, file_name: str):
    file_path = DATA_DIR / file_name
    print(f"\n--- Đang import '{table_name}' từ {file_path} ---")
    start = time.time()

    if table_name == "sales":
        # Import theo chunk cho bảng lớn
        total_rows = 0
        for chunk in pd.read_csv(file_path, chunksize=CHUNK_SIZE):
            chunk = clean_dataframe(chunk)
            chunk.to_sql(table_name, con=engine, if_exists="append", index=False)
            total_rows += len(chunk)
            print(f"  Đã import {total_rows:,} dòng...", end="\r")
        print(f"\n  Hoàn tất: {total_rows:,} dòng.")
    else:
        df = pd.read_csv(file_path)
        df = clean_dataframe(df)
        df.to_sql(table_name, con=engine, if_exists="append", index=False)
        print(f"  Hoàn tất: {len(df):,} dòng.")

    elapsed = time.time() - start
    print(f"  Thời gian: {elapsed:.1f}s")


def clean_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """Xử lý cơ bản trước khi insert: bỏ khoảng trắng thừa ở tên cột,
    convert cột ngày tháng nếu có, xử lý giá trị rỗng."""
    df.columns = [c.strip() for c in df.columns]

    date_cols = ["BirthDate", "HireDate", "ModifyDate", "SalesDate"]
    for col in date_cols:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")

    return df


def reset_tables():
    """Xoá dữ liệu mọi bảng (bảng con trước, bảng cha sau) để có thể import lại."""
    with engine.begin() as conn:
        for table in reversed(IMPORT_ORDER):
            conn.execute(text(f"DELETE FROM {table}"))
    print("All tables emptied.")


def validate_import():
    """Check nhanh sau khi import: đếm số dòng mỗi bảng."""
    print("\n=== KIỂM TRA SAU IMPORT ===")
    with engine.connect() as conn:
        for table in IMPORT_ORDER:
            result = conn.exec_driver_sql(f"SELECT COUNT(*) FROM {table}")
            count = result.scalar()
            print(f"  {table:12s}: {count:,} dòng")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Import the Grocery Sales CSV files into MySQL.")
    ap.add_argument("--reset", action="store_true", help="empty all tables before importing")
    args = ap.parse_args()

    print("IMPORTING GROCERY SALES DATA")
    print("=" * 50)
    check_connection()
    if args.reset:
        reset_tables()

    for table in IMPORT_ORDER:
        import_table(table, FILE_MAP[table])

    validate_import()
    print("\nImport finished.")
