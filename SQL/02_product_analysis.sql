-- =====================================================================
-- TÌNH HUỐNG 2: ĐỊNH BIÊN & PHÂN LOẠI SẢN PHẨM KINH DOANH  (MySQL 8.x)
-- Nguồn: fact_sales, products, categories
--
-- Kỳ phân tích "4 tháng" = 4 tháng TRỌN VẸN 01/01/2018 -> 30/04/2018
-- (tháng 5 chỉ có 9 ngày dữ liệu nên không đưa vào xếp hạng tích luỹ).
-- =====================================================================

-- @exec
SET @p_start = '2018-01-01', @p_end = '2018-05-01';


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 2.1 - XẾP HẠNG SẢN PHẨM THEO DOANH THU TÍCH LUỸ 4 THÁNG
-- ---------------------------------------------------------------------

/* Bảng tạm: doanh thu tích luỹ từng sản phẩm trong 4 tháng.
   LEFT JOIN từ products để sản phẩm không bán được vẫn xuất hiện (doanh thu = 0). */
-- @exec
DROP TEMPORARY TABLE IF EXISTS tmp_product_4m;

-- @exec
CREATE TEMPORARY TABLE tmp_product_4m AS
SELECT
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    p.Class,
    p.Price                                AS ListPrice,
    COALESCE(a.NumTransactions, 0)         AS NumTransactions,
    COALESCE(a.TotalUnits, 0)              AS TotalUnits,
    COALESCE(a.GrossRevenue, 0)            AS GrossRevenue,
    COALESCE(a.NetRevenue, 0)              AS NetRevenue
FROM products p
JOIN categories c ON p.CategoryID = c.CategoryID
LEFT JOIN (
    SELECT ProductID,
           COUNT(*)          AS NumTransactions,
           SUM(Quantity)     AS TotalUnits,
           SUM(GrossRevenue) AS GrossRevenue,
           SUM(NetRevenue)   AS NetRevenue
    FROM fact_sales
    WHERE SalesDate >= @p_start AND SalesDate < @p_end
    GROUP BY ProductID
) a ON a.ProductID = p.ProductID;

/* (a) Xếp hạng toàn bộ 452 sản phẩm + Pareto + phân loại ABC
       A: nhóm tạo 80% doanh thu đầu tiên | B: 80-95% | C: 5% cuối */
-- @query: t2_1_product_ranking
WITH ranked AS (
    SELECT
        t.*,
        RANK()       OVER (ORDER BY NetRevenue DESC)                     AS RevenueRank,
        NetRevenue * 100 / SUM(NetRevenue) OVER ()                       AS SharePct,
        SUM(NetRevenue) OVER (ORDER BY NetRevenue DESC, ProductID
                              ROWS UNBOUNDED PRECEDING) * 100
            / SUM(NetRevenue) OVER ()                                    AS CumSharePct,
        NTILE(10)    OVER (ORDER BY NetRevenue DESC)                     AS RevenueDecile
    FROM tmp_product_4m t
)
SELECT
    RevenueRank, ProductID, ProductName, CategoryName, Class,
    ROUND(ListPrice, 4)   AS ListPrice,
    NumTransactions, TotalUnits,
    ROUND(NetRevenue, 2)  AS NetRevenue,
    ROUND(SharePct, 4)    AS SharePct,
    ROUND(CumSharePct, 2) AS CumSharePct,
    RevenueDecile,
    CASE WHEN CumSharePct - SharePct < 80 THEN 'A'
         WHEN CumSharePct - SharePct < 95 THEN 'B'
         ELSE 'C' END     AS ABC_Class
FROM ranked
ORDER BY RevenueRank;

/* (b) Top 5 best sellers & Bottom 5 products (theo doanh thu thực) */
-- @query: t2_1_top5_bottom5
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (ORDER BY NetRevenue DESC, ProductID) AS RankBest,
           ROW_NUMBER() OVER (ORDER BY NetRevenue ASC,  ProductID) AS RankWorst,
           NetRevenue * 100 / SUM(NetRevenue) OVER ()              AS SharePct,
           AVG(NetRevenue) OVER ()                                 AS AvgProductRevenue
    FROM tmp_product_4m t
)
SELECT
    CASE WHEN RankBest <= 5 THEN 'Top 5 best sellers'
         ELSE 'Bottom 5 products' END              AS GroupName,
    CASE WHEN RankBest <= 5 THEN RankBest
         ELSE RankWorst END                              AS GroupRank,
    ProductID, ProductName, CategoryName, Class,
    ROUND(ListPrice, 2)                                  AS ListPrice,
    TotalUnits,
    ROUND(NetRevenue, 2)                                 AS NetRevenue,
    ROUND(SharePct, 3)                                   AS SharePct,
    ROUND(NetRevenue / AvgProductRevenue * 100, 1)       AS IndexVsAvgProduct
FROM ranked
WHERE RankBest <= 5 OR RankWorst <= 5
ORDER BY GroupName DESC, GroupRank;

/* (c) Tổng hợp theo nhóm ABC */
-- @query: t2_1_abc_summary
WITH ranked AS (
    SELECT t.*,
           SUM(NetRevenue) OVER (ORDER BY NetRevenue DESC, ProductID ROWS UNBOUNDED PRECEDING) * 100
               / SUM(NetRevenue) OVER () AS CumSharePct,
           NetRevenue * 100 / SUM(NetRevenue) OVER () AS SharePct
    FROM tmp_product_4m t
),
abc AS (
    SELECT *, CASE WHEN CumSharePct - SharePct < 80 THEN 'A'
                   WHEN CumSharePct - SharePct < 95 THEN 'B' ELSE 'C' END AS ABC_Class
    FROM ranked
)
SELECT
    ABC_Class,
    COUNT(*)                                                   AS NumProducts,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)         AS PctProducts,
    SUM(TotalUnits)                                            AS TotalUnits,
    ROUND(SUM(TotalUnits) * 100.0 / SUM(SUM(TotalUnits)) OVER (), 2) AS PctUnits,
    ROUND(SUM(NetRevenue), 2)                                  AS NetRevenue,
    ROUND(SUM(NetRevenue) * 100 / SUM(SUM(NetRevenue)) OVER (), 2)   AS PctRevenue,
    ROUND(AVG(ListPrice), 2)                                   AS AvgListPrice
FROM abc
GROUP BY ABC_Class
ORDER BY ABC_Class;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 2.2 - TƯƠNG QUAN SỐ LƯỢNG BÁN (QUANTITY) & DOANH THU THỰC
--   Dữ liệu KHÔNG có giá vốn -> dùng "Doanh thu thực / đơn vị" (NetRevenuePerUnit)
--   làm proxy cho biên lợi nhuận đơn vị.
-- ---------------------------------------------------------------------

/* (a) Hệ số tương quan Pearson giữa các cặp chỉ số (cấp sản phẩm) */
-- @query: t2_2_correlation
WITH x AS (
    SELECT TotalUnits AS u, NetRevenue AS r, ListPrice AS p
    FROM tmp_product_4m
    WHERE TotalUnits > 0
)
SELECT
    COUNT(*) AS NumProducts,
    ROUND((COUNT(*) * SUM(u * r) - SUM(u) * SUM(r))
        / SQRT((COUNT(*) * SUM(u * u) - SUM(u) * SUM(u))
             * (COUNT(*) * SUM(r * r) - SUM(r) * SUM(r))), 4) AS Corr_Units_vs_NetRevenue,
    ROUND((COUNT(*) * SUM(p * r) - SUM(p) * SUM(r))
        / SQRT((COUNT(*) * SUM(p * p) - SUM(p) * SUM(p))
             * (COUNT(*) * SUM(r * r) - SUM(r) * SUM(r))), 4) AS Corr_Price_vs_NetRevenue,
    ROUND((COUNT(*) * SUM(p * u) - SUM(p) * SUM(u))
        / SQRT((COUNT(*) * SUM(p * p) - SUM(p) * SUM(p))
             * (COUNT(*) * SUM(u * u) - SUM(u) * SUM(u))), 4) AS Corr_Price_vs_Units,
    ROUND(MIN(u), 0) AS MinUnits, ROUND(MAX(u), 0) AS MaxUnits,
    ROUND(STDDEV_POP(u) * 100 / AVG(u), 2) AS CV_Units_Pct,
    ROUND(STDDEV_POP(r) * 100 / AVG(r), 2) AS CV_NetRevenue_Pct
FROM x;

/* (b) Ma trận Nhu cầu (Units) x Giá trị đơn vị (NetRevenuePerUnit) theo tứ phân vị */
-- @query: t2_2_demand_value_matrix
WITH base AS (
    SELECT t.*,
           NetRevenue / NULLIF(TotalUnits, 0)                       AS NetRevenuePerUnit,
           (GrossRevenue - NetRevenue) * 100 / NULLIF(GrossRevenue, 0) AS EffDiscountPct
    FROM tmp_product_4m t
),
q AS (
    SELECT base.*,
           NTILE(4) OVER (ORDER BY TotalUnits)        AS DemandQuartile,   -- 4 = nhu cầu cao nhất
           NTILE(4) OVER (ORDER BY NetRevenuePerUnit) AS ValueQuartile     -- 1 = giá trị/đơn vị thấp nhất
    FROM base
)
SELECT
    ProductID, ProductName, CategoryName, Class,
    TotalUnits,
    ROUND(NetRevenue, 2)          AS NetRevenue,
    ROUND(NetRevenuePerUnit, 4)   AS NetRevenuePerUnit,
    ROUND(EffDiscountPct, 2)      AS EffDiscountPct,
    DemandQuartile, ValueQuartile,
    CASE
        WHEN DemandQuartile = 4 AND ValueQuartile = 1 THEN '1. Very high demand - Low value (Traffic driver)'
        WHEN DemandQuartile >= 3 AND ValueQuartile >= 3 THEN '2. High demand - High value (Star)'
        WHEN DemandQuartile >= 3 AND ValueQuartile <= 2 THEN '3. High demand - Low value (Volume)'
        WHEN DemandQuartile <= 2 AND ValueQuartile >= 3 THEN '4. Low demand - High value (Niche premium)'
        ELSE '5. Low demand - Low value (Review / Delist)'
    END AS Quadrant
FROM q
ORDER BY DemandQuartile DESC, ValueQuartile, TotalUnits DESC;

/* (c) Danh sách trọng tâm: sản phẩm bán rất chạy (Top 25% số lượng)
       nhưng doanh thu/đơn vị thấp (Bottom 25%) */
-- @query: t2_2_high_demand_low_value
WITH base AS (
    SELECT t.*, NetRevenue / NULLIF(TotalUnits, 0) AS NetRevenuePerUnit
    FROM tmp_product_4m t
),
q AS (
    SELECT base.*,
           NTILE(4) OVER (ORDER BY TotalUnits)        AS DemandQuartile,
           NTILE(4) OVER (ORDER BY NetRevenuePerUnit) AS ValueQuartile,
           RANK()   OVER (ORDER BY TotalUnits DESC)   AS UnitsRank,
           RANK()   OVER (ORDER BY NetRevenue DESC)   AS RevenueRank,
           AVG(NetRevenue / NULLIF(TotalUnits, 0)) OVER () AS AvgRevPerUnit
    FROM base
)
SELECT
    ProductID, ProductName, CategoryName, Class,
    TotalUnits, UnitsRank,
    ROUND(NetRevenue, 2)        AS NetRevenue, RevenueRank,
    ROUND(NetRevenuePerUnit, 4) AS NetRevenuePerUnit,
    ROUND(NetRevenuePerUnit / AvgRevPerUnit * 100, 1) AS UnitValueIndex   -- 100 = trung bình
FROM q
WHERE DemandQuartile = 4 AND ValueQuartile = 1
ORDER BY TotalUnits DESC;

/* (d) Tổng hợp theo góc phần tư */
-- @query: t2_2_quadrant_summary
WITH base AS (
    SELECT t.*, NetRevenue / NULLIF(TotalUnits, 0) AS NetRevenuePerUnit
    FROM tmp_product_4m t
),
q AS (
    SELECT base.*,
           NTILE(4) OVER (ORDER BY TotalUnits)        AS DemandQuartile,
           NTILE(4) OVER (ORDER BY NetRevenuePerUnit) AS ValueQuartile
    FROM base
),
lab AS (
    SELECT q.*,
        CASE
            WHEN DemandQuartile = 4 AND ValueQuartile = 1 THEN '1. Very high demand - Low value (Traffic driver)'
            WHEN DemandQuartile >= 3 AND ValueQuartile >= 3 THEN '2. High demand - High value (Star)'
            WHEN DemandQuartile >= 3 AND ValueQuartile <= 2 THEN '3. High demand - Low value (Volume)'
            WHEN DemandQuartile <= 2 AND ValueQuartile >= 3 THEN '4. Low demand - High value (Niche premium)'
            ELSE '5. Low demand - Low value (Review / Delist)'
        END AS Quadrant
    FROM q
)
SELECT
    Quadrant,
    COUNT(*)                                                         AS NumProducts,
    SUM(TotalUnits)                                                  AS TotalUnits,
    ROUND(SUM(TotalUnits) * 100.0 / SUM(SUM(TotalUnits)) OVER (), 2) AS PctUnits,
    ROUND(SUM(NetRevenue), 2)                                        AS NetRevenue,
    ROUND(SUM(NetRevenue) * 100 / SUM(SUM(NetRevenue)) OVER (), 2)   AS PctRevenue,
    ROUND(SUM(NetRevenue) / SUM(TotalUnits), 2)                      AS NetRevenuePerUnit
FROM lab
GROUP BY Quadrant
ORDER BY Quadrant;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 2.3 - ẢNH HƯỞNG CỦA THUỘC TÍNH CLASS ĐẾN HIỆU SUẤT TIÊU THỤ
-- ---------------------------------------------------------------------

/* (a) Hiệu suất theo Class: so sánh tỷ trọng SKU vs tỷ trọng sản lượng vs tỷ trọng doanh thu */
-- @query: t2_3_class_performance
WITH cls AS (
    SELECT
        Class,
        COUNT(*)            AS NumProducts,
        SUM(NumTransactions) AS NumTransactions,
        SUM(TotalUnits)     AS TotalUnits,
        SUM(GrossRevenue)   AS GrossRevenue,
        SUM(NetRevenue)     AS NetRevenue,
        AVG(ListPrice)      AS AvgListPrice
    FROM tmp_product_4m
    GROUP BY Class
)
SELECT
    Class,
    NumProducts,
    ROUND(NumProducts * 100.0 / SUM(NumProducts) OVER (), 2)          AS PctProducts,
    TotalUnits,
    ROUND(TotalUnits * 100.0 / SUM(TotalUnits) OVER (), 2)            AS PctUnits,
    ROUND(NetRevenue, 2)                                              AS NetRevenue,
    ROUND(NetRevenue * 100 / SUM(NetRevenue) OVER (), 2)              AS PctRevenue,
    ROUND(AvgListPrice, 2)                                            AS AvgListPrice,
    ROUND(NetRevenue / TotalUnits, 2)                                 AS NetRevenuePerUnit,
    ROUND(TotalUnits / NumProducts, 0)                                AS UnitsPerProduct,
    ROUND(NetRevenue / NumProducts, 2)                                AS RevenuePerProduct,
    ROUND((GrossRevenue - NetRevenue) * 100 / GrossRevenue, 2)        AS EffDiscountPct,
    -- Chỉ số hiệu quả SKU: > 100 = Class tạo doanh thu vượt tỷ lệ số SKU nắm giữ
    ROUND((NetRevenue / SUM(NetRevenue) OVER ())
        / (NumProducts / SUM(NumProducts) OVER ()) * 100, 1)          AS RevenueEfficiencyIndex
FROM cls
ORDER BY NetRevenue DESC;

/* (b) Ma trận Class x Danh mục: tỷ trọng doanh thu của từng Class trong mỗi danh mục */
-- @query: t2_3_class_by_category
WITH cc AS (
    SELECT CategoryName, Class, COUNT(*) AS NumProducts,
           SUM(TotalUnits) AS TotalUnits, SUM(NetRevenue) AS NetRevenue
    FROM tmp_product_4m
    GROUP BY CategoryName, Class
)
SELECT
    CategoryName, Class, NumProducts, TotalUnits,
    ROUND(NetRevenue, 2)                                                          AS NetRevenue,
    ROUND(NetRevenue * 100 / SUM(NetRevenue) OVER (PARTITION BY CategoryName), 2) AS PctOfCategoryRevenue,
    ROUND(NetRevenue / NumProducts, 2)                                            AS RevenuePerProduct
FROM cc
ORDER BY CategoryName, Class;

/* (c) Độ ổn định ảnh hưởng của Class theo tháng (T1-T4) */
-- @query: t2_3_class_monthly_share
WITH m AS (
    SELECT SalesMonth, ProductClass AS Class, SUM(Quantity) AS Units, SUM(NetRevenue) AS Rev
    FROM fact_sales
    WHERE SalesDate >= @p_start AND SalesDate < @p_end
    GROUP BY SalesMonth, ProductClass
)
SELECT
    SalesMonth, Class, Units,
    ROUND(Rev, 2)                                                    AS NetRevenue,
    ROUND(Units * 100.0 / SUM(Units) OVER (PARTITION BY SalesMonth), 2) AS PctUnits,
    ROUND(Rev * 100 / SUM(Rev) OVER (PARTITION BY SalesMonth), 2)    AS PctRevenue
FROM m
ORDER BY SalesMonth, Class;
