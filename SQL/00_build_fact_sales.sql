-- =====================================================================
-- GROCERY SALES - BUILD FACT TABLE (MySQL 8.x)
-- Chạy SAU 00_create_schema.sql + import dữ liệu + 00_validate_import.sql
--
-- Vì sao cần bảng fact_sales?
--   * Cột sales.TotalPrice trong dữ liệu gốc = 0 ở 100% dòng
--     -> doanh thu phải tự tính: Quantity * Price * (1 - Discount).
--   * Mọi tình huống phân tích đều JOIN sales (6,7 triệu dòng) với
--     products / customers / employees. Vật chất hoá (materialize) 1 lần
--     giúp các truy vấn sau chỉ cần quét 1 bảng phẳng -> nhanh hơn nhiều.
--
-- Quy ước chỉ số:
--   GrossRevenue   = Quantity * Price                (doanh thu niêm yết)
--   DiscountAmount = Quantity * Price * Discount     (tiền chiết khấu)
--   NetRevenue     = Quantity * Price * (1-Discount) (doanh thu thực tế)
--
-- Ghi chú cho runner (python/run_analysis.py):
--   "-- @exec"          : câu lệnh thực thi, không xuất kết quả
--   "-- @query: <name>" : câu SELECT, kết quả lưu ra outputs/tables/<name>.csv
-- =====================================================================

-- @exec
DROP TABLE IF EXISTS fact_sales;

-- @exec
CREATE TABLE fact_sales (
    SalesID           INT PRIMARY KEY,
    TransactionNumber VARCHAR(25),
    SalesDate         DATETIME NULL,
    SalesDay          DATE     NULL,
    SalesMonth        CHAR(7)  NULL,          -- 'YYYY-MM'
    SalesPersonID     INT,
    CustomerID        INT,
    ProductID         INT,
    CategoryID        INT,
    ProductClass      VARCHAR(20),
    CustomerCityID    INT,                    -- thành phố của khách hàng (thị trường)
    EmployeeCityID    INT,                    -- thành phố nơi nhân viên làm việc (văn phòng)
    Quantity          INT,
    UnitPrice         DECIMAL(10,4),
    Discount          DECIMAL(4,2),
    GrossRevenue      DECIMAL(16,4),
    DiscountAmount    DECIMAL(16,4),
    NetRevenue        DECIMAL(16,4)
) ENGINE = InnoDB;

-- @exec
INSERT INTO fact_sales
SELECT
    s.SalesID,
    s.TransactionNumber,
    s.SalesDate,
    DATE(s.SalesDate),
    DATE_FORMAT(s.SalesDate, '%Y-%m'),
    s.SalesPersonID,
    s.CustomerID,
    s.ProductID,
    p.CategoryID,
    p.Class,
    cu.CityID,
    e.CityID,
    s.Quantity,
    p.Price,
    s.Discount,
    s.Quantity * p.Price,
    s.Quantity * p.Price * s.Discount,
    s.Quantity * p.Price * (1 - s.Discount)
FROM sales s
JOIN products  p  ON s.ProductID     = p.ProductID
JOIN customers cu ON s.CustomerID    = cu.CustomerID
JOIN employees e  ON s.SalesPersonID = e.EmployeeID;

-- Index phục vụ các truy vấn lọc theo thời gian / nhóm theo khách hàng
-- @exec
CREATE INDEX idx_fact_month    ON fact_sales (SalesMonth);

-- @exec
CREATE INDEX idx_fact_customer ON fact_sales (CustomerID);

-- =====================================================================
-- KIỂM TRA ĐỐI SOÁT: fact_sales phải khớp 100% số dòng với sales
-- và không có dòng nào bị rơi khi JOIN.
-- =====================================================================
-- @query: t0_fact_reconciliation
SELECT
    (SELECT COUNT(*) FROM sales)                         AS RawSalesRows,
    COUNT(*)                                             AS FactRows,
    (SELECT COUNT(*) FROM sales) - COUNT(*)              AS DroppedRows,
    SUM(SalesDate IS NULL)                               AS RowsWithNullDate,
    ROUND(SUM(SalesDate IS NULL) * 100.0 / COUNT(*), 2)  AS PctNullDate,
    COUNT(DISTINCT TransactionNumber)                    AS DistinctTransactions,
    MIN(SalesDate)                                       AS FirstSalesDate,
    MAX(SalesDate)                                       AS LastSalesDate,
    (SELECT SUM(TotalPrice) FROM sales)                  AS Raw_TotalPrice_Sum,
    ROUND(SUM(NetRevenue), 2)                            AS Computed_NetRevenue
FROM fact_sales;

-- Số ngày có dữ liệu trong từng tháng (May chỉ có dữ liệu 1-9/5 -> tháng không trọn vẹn)
-- @query: t0_data_coverage_by_month
SELECT
    COALESCE(SalesMonth, '(NULL date)') AS SalesMonth,
    COUNT(*)                            AS NumLines,
    COUNT(DISTINCT SalesDay)            AS DaysWithData,
    MIN(SalesDay)                       AS FirstDay,
    MAX(SalesDay)                       AS LastDay
FROM fact_sales
GROUP BY SalesMonth
ORDER BY SalesMonth;
