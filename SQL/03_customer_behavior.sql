-- =====================================================================
-- TÌNH HUỐNG 3: HÀNH VI & CHÂN DUNG KHÁCH HÀNG  (MySQL 8.x)
-- Nguồn: fact_sales, customers, cities
--
-- Định nghĩa:
--   * 1 đơn hàng / hoá đơn = 1 TransactionNumber.
--     (Kiểm tra dữ liệu: TransactionNumber là DUY NHẤT trên từng dòng sales
--      -> mỗi hoá đơn chỉ có 1 dòng sản phẩm.)
--   * Vì vậy bổ sung định nghĩa "giỏ hàng mở rộng" (Shopping trip)
--     = tất cả giao dịch của 1 khách trong cùng 1 ngày (CustomerID + SalesDay).
--   * Frequency  = số hoá đơn của khách trong kỳ
--     Monetary   = tổng doanh thu thực (NetRevenue) khách mang lại
-- =====================================================================


-- ---------------------------------------------------------------------
-- Bảng trung gian: chỉ số cấp khách hàng (dùng lại cho 3.1, 3.2, 3.3)
-- ---------------------------------------------------------------------
-- @exec
DROP TABLE IF EXISTS customer_metrics;

-- @exec
CREATE TABLE customer_metrics AS
SELECT
    f.CustomerID,
    COUNT(*)                                                      AS Frequency,
    SUM(f.NetRevenue)                                             AS Monetary,
    SUM(f.Quantity)                                               AS TotalUnits,
    COUNT(DISTINCT f.SalesDay)                                    AS ShoppingDays,
    COUNT(DISTINCT CASE WHEN f.SalesMonth BETWEEN '2018-01' AND '2018-04'
                        THEN f.SalesMonth END)                    AS ActiveFullMonths,
    COUNT(DISTINCT f.ProductID)                                   AS DistinctProducts,
    MIN(f.SalesDay)                                               AS FirstPurchase,
    MAX(f.SalesDay)                                               AS LastPurchase
FROM fact_sales f
GROUP BY f.CustomerID;

-- @exec
ALTER TABLE customer_metrics ADD PRIMARY KEY (CustomerID);


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 3.1 - PHÂN KHÚC KHÁCH HÀNG THEO FREQUENCY x MONETARY
--   F_Score, M_Score = tứ phân vị (1 thấp nhất -> 4 cao nhất)
-- ---------------------------------------------------------------------
-- @exec
DROP TABLE IF EXISTS customer_segments;

-- @exec
CREATE TABLE customer_segments AS
WITH scored AS (
    SELECT
        cm.*,
        NTILE(4) OVER (ORDER BY Frequency, Monetary) AS F_Score,
        NTILE(4) OVER (ORDER BY Monetary, Frequency) AS M_Score
    FROM customer_metrics cm
)
SELECT
    s.CustomerID,
    CONCAT(cu.FirstName, ' ', cu.LastName) AS CustomerName,
    ci.CityName,
    s.Frequency,
    ROUND(s.Monetary, 2)                   AS Monetary,
    ROUND(s.Monetary / s.Frequency, 2)     AS AvgOrderValue,
    s.TotalUnits,
    s.ShoppingDays,
    s.ActiveFullMonths,
    s.F_Score,
    s.M_Score,
    CASE
        WHEN s.F_Score = 4 AND s.M_Score = 4 THEN '1. VIP'
        WHEN s.F_Score >= 3 AND s.M_Score >= 3 THEN '2. Loyal'
        WHEN s.F_Score <= 2 AND s.M_Score >= 3 THEN '3. Big Spender - Infrequent'
        WHEN s.F_Score >= 3 AND s.M_Score <= 2 THEN '4. Frequent - Low Spend'
        WHEN s.F_Score = 1 AND s.M_Score = 1 THEN '6. Hibernating'
        ELSE '5. Low Engagement'
    END AS Segment
FROM scored s
JOIN customers cu ON s.CustomerID = cu.CustomerID
JOIN cities    ci ON cu.CityID    = ci.CityID;

/* (a) Tổng hợp phân khúc: quy mô, đóng góp doanh thu, hành vi trung bình */
-- @query: t3_1_segment_summary
SELECT
    Segment,
    COUNT(*)                                                    AS NumCustomers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)          AS PctCustomers,
    ROUND(SUM(Monetary), 2)                                     AS NetRevenue,
    ROUND(SUM(Monetary) * 100 / SUM(SUM(Monetary)) OVER (), 2)  AS PctRevenue,
    ROUND(AVG(Frequency), 1)                                    AS AvgFrequency,
    MIN(Frequency)                                              AS MinFrequency,
    MAX(Frequency)                                              AS MaxFrequency,
    ROUND(AVG(Monetary), 2)                                     AS AvgMonetary,
    ROUND(MIN(Monetary), 2)                                     AS MinMonetary,
    ROUND(MAX(Monetary), 2)                                     AS MaxMonetary,
    ROUND(SUM(Monetary) / SUM(Frequency), 2)                    AS AvgOrderValue
FROM customer_segments
GROUP BY Segment
ORDER BY Segment;

/* (b) Lưới F_Score x M_Score (số khách & doanh thu từng ô) - dùng vẽ heatmap */
-- @query: t3_1_fm_grid
SELECT
    F_Score, M_Score,
    COUNT(*)                                                    AS NumCustomers,
    ROUND(SUM(Monetary), 2)                                     AS NetRevenue,
    ROUND(SUM(Monetary) * 100 / SUM(SUM(Monetary)) OVER (), 2)  AS PctRevenue
FROM customer_segments
GROUP BY F_Score, M_Score
ORDER BY F_Score DESC, M_Score DESC;

/* (c) Ngưỡng (cut-off) của từng điểm F / M để Marketing áp dụng quy tắc */
-- @query: t3_1_score_thresholds
SELECT 'Frequency' AS Metric, F_Score AS Score,
       MIN(Frequency) AS MinValue, MAX(Frequency) AS `MaxValue`, COUNT(*) AS NumCustomers
FROM customer_segments GROUP BY F_Score
UNION ALL
SELECT 'Monetary', M_Score, ROUND(MIN(Monetary), 2), ROUND(MAX(Monetary), 2), COUNT(*)
FROM customer_segments GROUP BY M_Score
ORDER BY Metric, Score;

/* (d) Danh sách chi tiết từng khách hàng (xuất cho CRM / BI) */
-- @query: t3_1_customer_segments_detail
SELECT * FROM customer_segments ORDER BY Monetary DESC;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 3.2 - REPEAT CUSTOMERS vs ONE-TIME BUYERS
-- ---------------------------------------------------------------------

/* (a) Theo số hoá đơn (định nghĩa chuẩn) và theo số ngày mua hàng (định nghĩa chặt) */
-- @query: t3_2_repeat_vs_onetime
WITH base AS (
    SELECT 'By invoice (TransactionNumber)' AS Basis,
           CASE WHEN Frequency = 1 THEN 'One-time Buyer' ELSE 'Repeat Customer' END AS CustomerType,
           Monetary
    FROM customer_metrics
    UNION ALL
    SELECT 'By distinct shopping days',
           CASE WHEN ShoppingDays <= 1 THEN 'One-time Buyer' ELSE 'Repeat Customer' END,
           Monetary
    FROM customer_metrics
)
SELECT
    Basis, CustomerType,
    COUNT(*)                                                                    AS NumCustomers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY Basis), 2)        AS PctCustomers,
    ROUND(SUM(Monetary), 2)                                                     AS NetRevenue,
    ROUND(SUM(Monetary) * 100 / SUM(SUM(Monetary)) OVER (PARTITION BY Basis), 2) AS PctRevenue
FROM base
GROUP BY Basis, CustomerType
ORDER BY Basis, CustomerType DESC;

/* (b) Độ sâu trung thành: khách hoạt động bao nhiêu tháng trong 4 tháng trọn vẹn */
-- @query: t3_2_active_months_distribution
SELECT
    ActiveFullMonths,
    COUNT(*)                                                    AS NumCustomers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)          AS PctCustomers,
    ROUND(AVG(Frequency), 1)                                    AS AvgFrequency,
    ROUND(AVG(Monetary), 2)                                     AS AvgMonetary
FROM customer_metrics
GROUP BY ActiveFullMonths
ORDER BY ActiveFullMonths DESC;

/* (c) Phân phối tần suất mua hàng (số hoá đơn / khách) */
-- @query: t3_2_frequency_distribution
SELECT
    CONCAT(LPAD(FLOOR(Frequency / 10) * 10, 3, '0'), '-',
           LPAD(FLOOR(Frequency / 10) * 10 + 9, 3, '0'))       AS FrequencyBucket,
    COUNT(*)                                                    AS NumCustomers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)          AS PctCustomers,
    ROUND(AVG(Monetary), 2)                                     AS AvgMonetary
FROM customer_metrics
GROUP BY FrequencyBucket
ORDER BY FrequencyBucket;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 3.3 - AOV & BASKET SIZE
-- ---------------------------------------------------------------------

/* (a) Hai cấp độ: theo hoá đơn và theo "chuyến mua sắm" (khách + ngày) */
-- @query: t3_3_aov_basket
WITH txn AS (
    SELECT
        'Per invoice (TransactionNumber)' AS Level,
        COUNT(*)                           AS NumBaskets,
        SUM(NetRevenue)                    AS NetRevenue,
        SUM(Quantity)                      AS TotalUnits,
        COUNT(*)                           AS TotalLines
    FROM fact_sales
),
trip AS (
    SELECT CustomerID, SalesDay,
           SUM(NetRevenue) AS NetRevenue, SUM(Quantity) AS Units,
           COUNT(*) AS NumLines, COUNT(DISTINCT ProductID) AS DistinctProducts
    FROM fact_sales
    WHERE SalesDay IS NOT NULL
    GROUP BY CustomerID, SalesDay
)
SELECT Level, NumBaskets,
       ROUND(NetRevenue / NumBaskets, 2)  AS AOV,
       ROUND(TotalUnits / NumBaskets, 2)  AS AvgUnitsPerBasket,
       ROUND(TotalLines / NumBaskets, 2)  AS AvgLinesPerBasket,
       ROUND(TotalLines / NumBaskets, 2)  AS AvgDistinctProductsPerBasket
FROM txn
UNION ALL
SELECT 'Per shopping trip (Customer + Day)',
       COUNT(*),
       ROUND(AVG(NetRevenue), 2),
       ROUND(AVG(Units), 2),
       ROUND(AVG(NumLines), 2),
       ROUND(AVG(DistinctProducts), 2)
FROM trip;

/* (b) Phân phối Basket Size (số đơn vị / hoá đơn) */
-- @query: t3_3_basket_size_distribution
SELECT
    Quantity                                                    AS UnitsPerTransaction,
    COUNT(*)                                                    AS NumTransactions,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)          AS PctTransactions,
    ROUND(AVG(NetRevenue), 2)                                   AS AvgOrderValue
FROM fact_sales
GROUP BY Quantity
ORDER BY Quantity;

/* (c) AOV & Basket Size theo tháng */
-- @query: t3_3_aov_by_month
SELECT
    SalesMonth,
    COUNT(*)                                AS NumTransactions,
    COUNT(DISTINCT CustomerID)              AS ActiveCustomers,
    ROUND(SUM(NetRevenue) / COUNT(*), 2)    AS AOV,
    ROUND(SUM(Quantity) / COUNT(*), 2)      AS AvgUnitsPerTransaction,
    ROUND(COUNT(*) / COUNT(DISTINCT CustomerID), 2) AS TransactionsPerActiveCustomer
FROM fact_sales
WHERE SalesMonth IS NOT NULL
GROUP BY SalesMonth
ORDER BY SalesMonth;

/* (d) AOV theo phân khúc khách hàng */
-- @query: t3_3_aov_by_segment
SELECT
    Segment,
    ROUND(SUM(Monetary) / SUM(Frequency), 2)  AS AOV,
    ROUND(SUM(TotalUnits) / SUM(Frequency), 2) AS AvgUnitsPerTransaction,
    ROUND(AVG(Frequency) * 30 / 129, 2)        AS AvgTransactionsPer30Days  -- kỳ dữ liệu = 129 ngày (01/01-09/05)
FROM customer_segments
GROUP BY Segment
ORDER BY Segment;
