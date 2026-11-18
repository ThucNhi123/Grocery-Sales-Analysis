-- =====================================================================
-- TÌNH HUỐNG 1: HIỆU SUẤT DOANH THU THEO DÒNG THỜI GIAN  (MySQL 8.x)
-- Nguồn: bảng fact_sales (xem 00_build_fact_sales.sql)
--
-- Lưu ý dữ liệu:
--   * sales.TotalPrice = 0 ở mọi dòng -> Doanh thu thực tế = NetRevenue
--     = Quantity * Price * (1 - Discount).
--   * Dữ liệu chạy từ 01/01/2018 đến 09/05/2018: Tháng 1-4 trọn vẹn,
--     Tháng 5 chỉ có 9 ngày -> so sánh MoM phải dùng doanh thu BÌNH QUÂN NGÀY.
--   * ~1% dòng có SalesDate = NULL: vẫn tính vào tổng doanh thu,
--     nhưng không thể phân bổ vào tháng.
-- =====================================================================


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 1.1 - TỔNG DOANH THU THỰC TẾ (SAU CHIẾT KHẤU)
-- ---------------------------------------------------------------------

/* (a) Tổng quan toàn kỳ: doanh thu niêm yết, chiết khấu, doanh thu thực */
-- @query: t1_1_total_revenue_summary
SELECT
    COUNT(*)                                                   AS NumTransactions,
    SUM(Quantity)                                              AS TotalUnits,
    ROUND(SUM(GrossRevenue), 2)                                AS GrossRevenue,
    ROUND(SUM(DiscountAmount), 2)                              AS DiscountAmount,
    ROUND(SUM(NetRevenue), 2)                                  AS NetRevenue,
    ROUND(SUM(DiscountAmount) * 100 / SUM(GrossRevenue), 2)    AS EffectiveDiscountPct,
    ROUND(SUM(Discount > 0) * 100.0 / COUNT(*), 2)             AS PctTransactionsDiscounted,
    ROUND(SUM(CASE WHEN SalesDate IS NULL THEN NetRevenue END), 2) AS NetRevenue_UnknownDate,
    ROUND(SUM(CASE WHEN SalesDate IS NULL THEN NetRevenue END) * 100
          / SUM(NetRevenue), 2)                                AS PctRevenue_UnknownDate
FROM fact_sales;

/* (b) Doanh thu theo tháng + tăng trưởng MoM (thô & chuẩn hoá theo ngày) */
-- @query: t1_1_monthly_revenue
WITH monthly AS (
    SELECT
        SalesMonth,
        COUNT(DISTINCT SalesDay)  AS DaysWithData,
        COUNT(*)                  AS NumTransactions,
        SUM(Quantity)             AS TotalUnits,
        SUM(GrossRevenue)         AS GrossRevenue,
        SUM(DiscountAmount)       AS DiscountAmount,
        SUM(NetRevenue)           AS NetRevenue
    FROM fact_sales
    WHERE SalesMonth IS NOT NULL
    GROUP BY SalesMonth
)
SELECT
    SalesMonth,
    CASE WHEN DaysWithData >= 28 THEN 'Full' ELSE 'Partial' END          AS MonthStatus,
    DaysWithData,
    NumTransactions,
    TotalUnits,
    ROUND(GrossRevenue, 2)                                               AS GrossRevenue,
    ROUND(DiscountAmount, 2)                                             AS DiscountAmount,
    ROUND(NetRevenue, 2)                                                 AS NetRevenue,
    ROUND(NetRevenue / DaysWithData, 2)                                  AS AvgDailyNetRevenue,
    ROUND(NetRevenue * 100 / SUM(NetRevenue) OVER (), 2)                 AS PctOfDatedRevenue,
    ROUND(SUM(NetRevenue) OVER (ORDER BY SalesMonth), 2)                 AS CumulativeNetRevenue,
    ROUND((NetRevenue - LAG(NetRevenue) OVER w)
          * 100 / NULLIF(LAG(NetRevenue) OVER w, 0), 2)                  AS MoM_GrowthPct_Raw,
    ROUND((NetRevenue / DaysWithData - LAG(NetRevenue / DaysWithData) OVER w)
          * 100 / NULLIF(LAG(NetRevenue / DaysWithData) OVER w, 0), 2)   AS MoM_GrowthPct_DailyAvg
FROM monthly
WINDOW w AS (ORDER BY SalesMonth)
ORDER BY SalesMonth;

/* (c) Chuỗi doanh thu theo ngày + trung bình trượt 7 ngày (phát hiện đột biến) */
-- @query: t1_1_daily_revenue
WITH daily AS (
    SELECT SalesDay, COUNT(*) AS NumTransactions, SUM(NetRevenue) AS NetRevenue
    FROM fact_sales
    WHERE SalesDay IS NOT NULL
    GROUP BY SalesDay
)
SELECT
    SalesDay,
    DAYNAME(SalesDay)                                                     AS WeekdayName,
    NumTransactions,
    ROUND(NetRevenue, 2)                                                  AS NetRevenue,
    ROUND(AVG(NetRevenue) OVER (ORDER BY SalesDay
          ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2)                   AS MA7_NetRevenue,
    ROUND((NetRevenue - AVG(NetRevenue) OVER ())
          / STDDEV_POP(NetRevenue) OVER (), 2)                            AS ZScore
FROM daily
ORDER BY SalesDay;

/* (d) Mô hình theo thứ trong tuần (doanh thu bình quân/ngày) */
-- @query: t1_1_weekday_pattern
WITH daily AS (
    SELECT SalesDay, SUM(NetRevenue) AS NetRevenue
    FROM fact_sales
    WHERE SalesDay IS NOT NULL
    GROUP BY SalesDay
)
SELECT
    WEEKDAY(SalesDay) + 1                                          AS WeekdayNo,   -- 1 = Monday
    DAYNAME(SalesDay)                                              AS WeekdayName,
    COUNT(*)                                                       AS NumDays,
    ROUND(AVG(NetRevenue), 2)                                      AS AvgDailyNetRevenue,
    ROUND((AVG(NetRevenue) / (SELECT AVG(NetRevenue) FROM daily) - 1) * 100, 2) AS PctVsOverallAvg
FROM daily
GROUP BY WEEKDAY(SalesDay) + 1, DAYNAME(SalesDay)
ORDER BY WeekdayNo;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 1.2 - TỶ TRỌNG ĐÓNG GÓP DOANH THU THEO DANH MỤC QUA TỪNG THÁNG
-- ---------------------------------------------------------------------

/* (a) Dạng dài (long format - phù hợp import vào Power BI / Tableau) */
-- @query: t1_2_category_monthly_share
WITH mcr AS (
    SELECT
        f.SalesMonth,
        c.CategoryName,
        COUNT(DISTINCT f.SalesDay) AS DaysWithData,
        SUM(f.Quantity)            AS TotalUnits,
        SUM(f.NetRevenue)          AS CategoryRevenue
    FROM fact_sales f
    JOIN categories c ON f.CategoryID = c.CategoryID
    WHERE f.SalesMonth IS NOT NULL
    GROUP BY f.SalesMonth, c.CategoryName
),
with_share AS (
    SELECT
        mcr.*,
        CategoryRevenue * 100 / SUM(CategoryRevenue) OVER (PARTITION BY SalesMonth) AS SharePct
    FROM mcr
)
SELECT
    SalesMonth,
    CategoryName,
    TotalUnits,
    ROUND(CategoryRevenue, 2)                                              AS CategoryRevenue,
    ROUND(CategoryRevenue / DaysWithData, 2)                               AS AvgDailyRevenue,
    ROUND(SharePct, 3)                                                     AS SharePct,
    RANK() OVER (PARTITION BY SalesMonth ORDER BY CategoryRevenue DESC)    AS RankInMonth,
    ROUND(SharePct - LAG(SharePct) OVER w, 3)                              AS ShareChange_pp,
    ROUND((CategoryRevenue / DaysWithData - LAG(CategoryRevenue / DaysWithData) OVER w)
          * 100 / NULLIF(LAG(CategoryRevenue / DaysWithData) OVER w, 0), 2) AS MoM_GrowthPct_DailyAvg
FROM with_share
WINDOW w AS (PARTITION BY CategoryName ORDER BY SalesMonth)
ORDER BY SalesMonth, CategoryRevenue DESC;

/* (b) Ma trận tỷ trọng (pivot) Danh mục x Tháng, % */
-- @query: t1_2_category_share_pivot
WITH mcr AS (
    SELECT f.SalesMonth, c.CategoryName, SUM(f.NetRevenue) AS Rev
    FROM fact_sales f
    JOIN categories c ON f.CategoryID = c.CategoryID
    WHERE f.SalesMonth IS NOT NULL
    GROUP BY f.SalesMonth, c.CategoryName
),
share AS (
    SELECT SalesMonth, CategoryName,
           Rev * 100 / SUM(Rev) OVER (PARTITION BY SalesMonth) AS SharePct
    FROM mcr
)
SELECT
    CategoryName,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-01' THEN SharePct END), 2) AS `2018-01`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-02' THEN SharePct END), 2) AS `2018-02`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-03' THEN SharePct END), 2) AS `2018-03`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-04' THEN SharePct END), 2) AS `2018-04`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-05' THEN SharePct END), 2) AS `2018-05 (partial)`
FROM share
GROUP BY CategoryName
ORDER BY `2018-01` DESC;

/* (c) Độ ổn định tỷ trọng của từng danh mục (4 tháng trọn vẹn T1-T4) */
-- @query: t1_2_category_share_stability
WITH mcr AS (
    SELECT f.SalesMonth, c.CategoryName,
           SUM(f.NetRevenue) AS Rev,
           SUM(f.NetRevenue) / COUNT(DISTINCT f.SalesDay) AS DailyRev
    FROM fact_sales f
    JOIN categories c ON f.CategoryID = c.CategoryID
    WHERE f.SalesMonth BETWEEN '2018-01' AND '2018-04'
    GROUP BY f.SalesMonth, c.CategoryName
),
share AS (
    SELECT mcr.*, Rev * 100 / SUM(Rev) OVER (PARTITION BY SalesMonth) AS SharePct
    FROM mcr
)
SELECT
    CategoryName,
    ROUND(SUM(Rev), 2)                                                     AS NetRevenue_JanApr,
    ROUND(SUM(Rev) * 100 / SUM(SUM(Rev)) OVER (), 2)                       AS OverallSharePct,
    ROUND(MIN(SharePct), 3)                                                AS MinMonthlySharePct,
    ROUND(MAX(SharePct), 3)                                                AS MaxMonthlySharePct,
    ROUND(MAX(SharePct) - MIN(SharePct), 3)                                AS ShareRange_pp,
    ROUND(STDDEV_POP(SharePct), 3)                                         AS ShareStdDev_pp,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-04' THEN SharePct END)
        - MAX(CASE WHEN SalesMonth = '2018-01' THEN SharePct END), 3)      AS ShareChange_JanToApr_pp,
    ROUND((MAX(CASE WHEN SalesMonth = '2018-04' THEN DailyRev END)
         / MAX(CASE WHEN SalesMonth = '2018-01' THEN DailyRev END) - 1) * 100, 2) AS DailyRevGrowth_JanToApr_Pct
FROM share
GROUP BY CategoryName
ORDER BY NetRevenue_JanApr DESC;
