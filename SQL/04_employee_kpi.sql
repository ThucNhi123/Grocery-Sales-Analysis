-- =====================================================================
-- TÌNH HUỐNG 4: NĂNG LỰC THÚC ĐẨY DOANH SỐ CỦA NHÂN VIÊN  (MySQL 8.x)
-- Nguồn: fact_sales, employees, cities
--
-- * Doanh số = NetRevenue (sau chiết khấu); Hoá đơn = TransactionNumber.
-- * Xu hướng theo thời gian dùng DOANH SỐ BÌNH QUÂN NGÀY của từng tháng
--   để loại bỏ sai lệch do số ngày trong tháng khác nhau (T2 = 28 ngày,
--   T5 chỉ 9 ngày). Đánh giá độ ổn định dựa trên 4 tháng trọn vẹn T1-T4.
-- =====================================================================


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 4.1 - DOANH SỐ & SỐ HOÁ ĐƠN THEO TỪNG NHÂN VIÊN
-- ---------------------------------------------------------------------
-- @exec
DROP TABLE IF EXISTS employee_metrics;

-- @exec
CREATE TABLE employee_metrics AS
SELECT
    e.EmployeeID                                            AS SalesPersonID,
    CONCAT_WS(' ', e.FirstName, CONCAT(e.MiddleInitial, '.'), e.LastName) AS EmployeeName,
    e.Gender,
    ci.CityName                                             AS BaseCity,
    DATE(e.HireDate)                                        AS HireDate,
    ROUND(DATEDIFF('2018-05-09', e.HireDate) / 365.25, 1)   AS TenureYears,
    COUNT(f.SalesID)                                        AS NumInvoices,
    COALESCE(SUM(f.Quantity), 0)                            AS TotalUnits,
    COUNT(DISTINCT f.CustomerID)                            AS CustomersServed,
    COALESCE(SUM(f.GrossRevenue), 0)                        AS GrossRevenue,
    COALESCE(SUM(f.NetRevenue), 0)                          AS NetRevenue
FROM employees e
JOIN cities ci ON e.CityID = ci.CityID
LEFT JOIN fact_sales f ON f.SalesPersonID = e.EmployeeID
GROUP BY e.EmployeeID, e.FirstName, e.MiddleInitial, e.LastName, e.Gender, ci.CityName, e.HireDate;

-- @query: t4_1_employee_sales
SELECT
    RANK() OVER (ORDER BY NetRevenue DESC)                    AS RevenueRank,
    SalesPersonID, EmployeeName, Gender, BaseCity, HireDate, TenureYears,
    NumInvoices,
    RANK() OVER (ORDER BY NumInvoices DESC)                   AS InvoiceRank,
    TotalUnits,
    CustomersServed,
    ROUND(NetRevenue, 2)                                      AS NetRevenue,
    ROUND(NetRevenue * 100 / SUM(NetRevenue) OVER (), 3)      AS PctOfTotalRevenue,
    ROUND(NetRevenue / NumInvoices, 2)                        AS AvgInvoiceValue,
    ROUND(TotalUnits / NumInvoices, 2)                        AS AvgUnitsPerInvoice,
    ROUND((GrossRevenue - NetRevenue) * 100 / GrossRevenue, 2) AS EffDiscountPct
FROM employee_metrics
ORDER BY NetRevenue DESC;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 4.2 - TOP PERFORMERS vs UNDERPERFORMERS
--   Điểm tổng hợp (Composite) = trung bình Z-score của 3 KPI:
--     Doanh số (50%), Số hoá đơn (30%), Giá trị hoá đơn bình quân (20%)
--   Phân nhóm:
--     Top Performer   : Composite Z >= +1  HOẶC nằm trong Top 20% xếp hạng
--     Underperformer  : Composite Z <= -1  HOẶC nằm trong Bottom 20% xếp hạng
-- ---------------------------------------------------------------------
-- @query: t4_2_performance_tiers
WITH kpi AS (
    SELECT
        SalesPersonID, EmployeeName, BaseCity, TenureYears,
        NetRevenue, NumInvoices,
        NetRevenue / NumInvoices AS AvgInvoiceValue
    FROM employee_metrics
),
z AS (
    SELECT
        kpi.*,
        (NetRevenue      - AVG(NetRevenue)      OVER ()) / STDDEV_POP(NetRevenue)      OVER () AS Z_Revenue,
        (NumInvoices     - AVG(NumInvoices)     OVER ()) / STDDEV_POP(NumInvoices)     OVER () AS Z_Invoices,
        (AvgInvoiceValue - AVG(AvgInvoiceValue) OVER ()) / STDDEV_POP(AvgInvoiceValue) OVER () AS Z_AOV,
        (NetRevenue / AVG(NetRevenue) OVER () - 1) * 100                                        AS PctVsTeamAvg
    FROM kpi
),
scored AS (
    SELECT z.*,
           0.5 * Z_Revenue + 0.3 * Z_Invoices + 0.2 * Z_AOV AS CompositeScore
    FROM z
),
ranked AS (
    SELECT scored.*,
           RANK()         OVER (ORDER BY CompositeScore DESC) AS CompositeRank,
           PERCENT_RANK() OVER (ORDER BY CompositeScore DESC) AS PctRank
    FROM scored
)
SELECT
    CompositeRank, SalesPersonID, EmployeeName, BaseCity, TenureYears,
    ROUND(NetRevenue, 2)       AS NetRevenue,
    NumInvoices,
    ROUND(AvgInvoiceValue, 2)  AS AvgInvoiceValue,
    ROUND(PctVsTeamAvg, 2)     AS RevenuePctVsTeamAvg,
    ROUND(Z_Revenue, 2)        AS Z_Revenue,
    ROUND(Z_Invoices, 2)       AS Z_Invoices,
    ROUND(Z_AOV, 2)            AS Z_AOV,
    ROUND(CompositeScore, 2)   AS CompositeScore,
    CASE
        WHEN CompositeScore >= 1  OR PctRank <= 0.20 THEN 'Top Performer'
        WHEN CompositeScore <= -1 OR PctRank >= 0.80 THEN 'Underperformer'
        ELSE 'Meets Expectation'
    END AS PerformanceTier
FROM ranked
ORDER BY CompositeRank;

/* Tổng hợp theo nhóm hiệu suất + chênh lệch giữa 2 nhóm cực */
-- @query: t4_2_tier_summary
WITH kpi AS (
    SELECT SalesPersonID, NetRevenue, NumInvoices, NetRevenue / NumInvoices AS AOV
    FROM employee_metrics
),
scored AS (
    SELECT kpi.*,
           0.5 * (NetRevenue  - AVG(NetRevenue)  OVER ()) / STDDEV_POP(NetRevenue)  OVER ()
         + 0.3 * (NumInvoices - AVG(NumInvoices) OVER ()) / STDDEV_POP(NumInvoices) OVER ()
         + 0.2 * (AOV         - AVG(AOV)         OVER ()) / STDDEV_POP(AOV)         OVER () AS CompositeScore
    FROM kpi
),
tiered AS (
    SELECT scored.*,
           CASE
               WHEN CompositeScore >= 1  OR PERCENT_RANK() OVER (ORDER BY CompositeScore DESC) <= 0.20 THEN 'Top Performer'
               WHEN CompositeScore <= -1 OR PERCENT_RANK() OVER (ORDER BY CompositeScore DESC) >= 0.80 THEN 'Underperformer'
               ELSE 'Meets Expectation'
           END AS PerformanceTier
    FROM scored
)
SELECT
    PerformanceTier,
    COUNT(*)                                                     AS NumEmployees,
    ROUND(SUM(NetRevenue), 2)                                    AS NetRevenue,
    ROUND(SUM(NetRevenue) * 100 / SUM(SUM(NetRevenue)) OVER (), 2) AS PctRevenue,
    ROUND(AVG(NetRevenue), 2)                                    AS AvgRevenuePerEmployee,
    ROUND(AVG(NumInvoices), 0)                                   AS AvgInvoicesPerEmployee,
    ROUND(SUM(NetRevenue) / SUM(NumInvoices), 2)                 AS AOV,
    GROUP_CONCAT(SalesPersonID ORDER BY CompositeScore DESC)     AS EmployeeIDs
FROM tiered
GROUP BY PerformanceTier
ORDER BY AvgRevenuePerEmployee DESC;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 4.3 - XU HƯỚNG & ĐỘ ỔN ĐỊNH DOANH SỐ THEO THỜI GIAN
-- ---------------------------------------------------------------------
-- @exec
DROP TABLE IF EXISTS employee_monthly;

-- @exec
CREATE TABLE employee_monthly AS
WITH days AS (
    SELECT SalesMonth, COUNT(DISTINCT SalesDay) AS DaysInMonth
    FROM fact_sales WHERE SalesMonth IS NOT NULL GROUP BY SalesMonth
)
SELECT
    f.SalesPersonID,
    f.SalesMonth,
    d.DaysInMonth,
    COUNT(*)                          AS NumInvoices,
    SUM(f.NetRevenue)                 AS NetRevenue,
    SUM(f.NetRevenue) / d.DaysInMonth AS AvgDailyRevenue
FROM fact_sales f
JOIN days d ON f.SalesMonth = d.SalesMonth
GROUP BY f.SalesPersonID, f.SalesMonth, d.DaysInMonth;

/* (a) Chuỗi thời gian theo tháng: doanh số, MoM, thứ hạng tháng, tỷ trọng tháng */
-- @query: t4_3_employee_monthly_trend
SELECT
    m.SalesPersonID,
    em.EmployeeName,
    m.SalesMonth,
    CASE WHEN m.DaysInMonth >= 28 THEN 'Full' ELSE 'Partial' END                AS MonthStatus,
    m.NumInvoices,
    ROUND(m.NetRevenue, 2)                                                      AS NetRevenue,
    ROUND(m.AvgDailyRevenue, 2)                                                 AS AvgDailyRevenue,
    ROUND(m.NetRevenue * 100 / SUM(m.NetRevenue) OVER (PARTITION BY m.SalesMonth), 3) AS PctOfMonthRevenue,
    RANK() OVER (PARTITION BY m.SalesMonth ORDER BY m.NetRevenue DESC)          AS RankInMonth,
    ROUND((m.AvgDailyRevenue - LAG(m.AvgDailyRevenue) OVER w)
          * 100 / NULLIF(LAG(m.AvgDailyRevenue) OVER w, 0), 2)                  AS MoM_GrowthPct_DailyAvg,
    ROUND(SUM(m.NetRevenue) OVER (w ROWS UNBOUNDED PRECEDING), 2)               AS CumulativeRevenue
FROM employee_monthly m
JOIN employee_metrics em ON em.SalesPersonID = m.SalesPersonID
WINDOW w AS (PARTITION BY m.SalesPersonID ORDER BY m.SalesMonth)
ORDER BY m.SalesPersonID, m.SalesMonth;

/* (b) Chỉ số ổn định (T1-T4):
       CV% = độ lệch chuẩn / trung bình doanh số bình quân ngày -> càng thấp càng ổn định
       TrendSlopePct = hệ số góc hồi quy tuyến tính theo tháng, tính bằng % trên mức trung bình
       RankRange = biên độ dao động thứ hạng hàng tháng */
-- @query: t4_3_employee_stability
WITH full_m AS (
    SELECT m.*,
           CAST(SUBSTRING(m.SalesMonth, 6, 2) AS UNSIGNED) AS MonthIdx,
           RANK() OVER (PARTITION BY m.SalesMonth ORDER BY m.NetRevenue DESC) AS RankInMonth
    FROM employee_monthly m
    WHERE m.SalesMonth BETWEEN '2018-01' AND '2018-04'
),
stats AS (
    SELECT
        SalesPersonID,
        COUNT(*)                                      AS NumMonths,
        AVG(AvgDailyRevenue)                          AS MeanDaily,
        STDDEV_POP(AvgDailyRevenue)                   AS StdDaily,
        MIN(AvgDailyRevenue)                          AS MinDaily,
        MAX(AvgDailyRevenue)                          AS MaxDaily,
        (COUNT(*) * SUM(MonthIdx * AvgDailyRevenue) - SUM(MonthIdx) * SUM(AvgDailyRevenue))
          / (COUNT(*) * SUM(MonthIdx * MonthIdx) - SUM(MonthIdx) * SUM(MonthIdx)) AS Slope,
        MAX(CASE WHEN MonthIdx = 1 THEN AvgDailyRevenue END) AS JanDaily,
        MAX(CASE WHEN MonthIdx = 4 THEN AvgDailyRevenue END) AS AprDaily,
        MIN(RankInMonth)                              AS BestMonthlyRank,
        MAX(RankInMonth)                              AS WorstMonthlyRank
    FROM full_m
    GROUP BY SalesPersonID
),
labeled AS (
    SELECT stats.*,
           StdDaily * 100 / MeanDaily  AS CV_Pct,
           Slope * 100 / MeanDaily     AS TrendSlopePct,
           NTILE(3) OVER (ORDER BY StdDaily / MeanDaily) AS StabilityTercile
    FROM stats
)
SELECT
    l.SalesPersonID,
    em.EmployeeName,
    ROUND(l.MeanDaily, 2)                     AS MeanDailyRevenue,
    ROUND(l.MinDaily, 2)                      AS MinMonthDailyRevenue,
    ROUND(l.MaxDaily, 2)                      AS MaxMonthDailyRevenue,
    ROUND(l.CV_Pct, 2)                        AS CV_Pct,
    ROUND(l.TrendSlopePct, 2)                 AS TrendSlopePctPerMonth,
    ROUND((l.AprDaily / l.JanDaily - 1) * 100, 2) AS Growth_JanToApr_Pct,
    l.BestMonthlyRank,
    l.WorstMonthlyRank,
    l.WorstMonthlyRank - l.BestMonthlyRank    AS RankRange,
    CASE l.StabilityTercile
        WHEN 1 THEN 'High'
        WHEN 2 THEN 'Medium'
        ELSE 'Volatile'
    END                                       AS StabilityGroup,
    CASE
        WHEN l.TrendSlopePct >=  1 THEN 'Up'
        WHEN l.TrendSlopePct <= -1 THEN 'Down'
        ELSE 'Flat'
    END                                       AS TrendDirection
FROM labeled l
JOIN employee_metrics em ON em.SalesPersonID = l.SalesPersonID
ORDER BY l.CV_Pct;

/* (c) Ma trận Nhân viên x Tháng (doanh số bình quân ngày) - dùng vẽ heatmap */
-- @query: t4_3_employee_month_pivot
SELECT
    m.SalesPersonID,
    em.EmployeeName,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-01' THEN AvgDailyRevenue END), 2) AS `2018-01`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-02' THEN AvgDailyRevenue END), 2) AS `2018-02`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-03' THEN AvgDailyRevenue END), 2) AS `2018-03`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-04' THEN AvgDailyRevenue END), 2) AS `2018-04`,
    ROUND(MAX(CASE WHEN SalesMonth = '2018-05' THEN AvgDailyRevenue END), 2) AS `2018-05 (partial)`
FROM employee_monthly m
JOIN employee_metrics em ON em.SalesPersonID = m.SalesPersonID
GROUP BY m.SalesPersonID, em.EmployeeName
ORDER BY m.SalesPersonID;
