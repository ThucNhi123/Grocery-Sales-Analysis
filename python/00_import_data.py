"""
Import dữ liệu Grocery Sales (7 file CSV) vào database.
Yêu cầu: đã chạy 00_create_schema.sql trước để tạo sẵn bảng + FK constraints.

Cài đặt thư viện cần thiết:
    pip install pandas sqlalchemy pymysql          # nếu dùng MySQL
    pip install pandas sqlalchemy psycopg2-binary   # nếu dùng PostgreSQL
    pip install pandas sqlalchemy pyodbc            # nếu dùng SQL Server
"""

import os
from urllib.parse import quote_plus
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine
import time

# =====================================================
# 1. CẤU HÌNH KẾT NỐI - chỉnh lại theo DBMS bạn dùng
# =====================================================

# --- MySQL ---
load_dotenv()

DB_USER = os.getenv("DB_USER") or "root"
DB_PASSWORD = quote_plus(os.getenv("DB_PASSWORD") or "")
DB_HOST = os.getenv("DB_HOST") or "localhost"
DB_PORT = os.getenv("DB_PORT") or "3306"
DB_NAME = os.getenv("DB_NAME") or "grocery_sales"

# Tạo engine an toàn
connection_string = f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
engine = create_engine(connection_string)

print("Kết nối database thành công bằng biến môi trường!")

# Thư mục chứa 7 file CSV gốc
DATA_DIR = "./data/raw"

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
    file_path = f"{DATA_DIR}/{file_name}"
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


def validate_import():
    """Check nhanh sau khi import: đếm số dòng mỗi bảng."""
    print("\n=== KIỂM TRA SAU IMPORT ===")
    with engine.connect() as conn:
        for table in IMPORT_ORDER:
            result = conn.exec_driver_sql(f"SELECT COUNT(*) FROM {table}")
            count = result.scalar()
            print(f"  {table:12s}: {count:,} dòng")


if __name__ == "__main__":
    print("BẮT ĐẦU IMPORT DỮ LIỆU GROCERY SALES")
    print("=" * 50)

    for table in IMPORT_ORDER:
        import_table(table, FILE_MAP[table])

    validate_import()
    print("\n✅ Import hoàn tất!")