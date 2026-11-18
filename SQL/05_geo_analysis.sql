-- =====================================================================
-- TÌNH HUỐNG 5: TOÀN CẢNH DOANH THU THEO ĐỊA GIỚI  (MySQL 8.x)
-- Nguồn: fact_sales, customers, employees, cities, countries
--
-- * Thị trường (market) = thành phố của KHÁCH HÀNG (customers.CityID).
-- * Văn phòng / đại lý = thành phố nơi NHÂN VIÊN làm việc (employees.CityID).
-- * Lưu ý dữ liệu: cities.csv chỉ tham chiếu 1 quốc gia (CountryID = 32,
--   United States) -> cấp Quốc gia chỉ có 1 nút; phân tích chênh lệch vùng
--   được thực hiện ở cấp Thành phố và nhóm Thành phố (tier).
-- * Tăng trưởng = doanh thu bình quân ngày (T3+T4) so với (T1+T2):
--   T1+T2 = 59 ngày, T3+T4 = 61 ngày.
-- =====================================================================


-- @exec
DROP TABLE IF EXISTS city_metrics;

-- @exec
CREATE TABLE city_metrics AS
WITH sc AS (
    SELECT
        CustomerCityID                                                        AS CityID,
        COUNT(DISTINCT CustomerID)                                            AS ActiveCustomers,
        COUNT(*)                                                              AS NumTransactions,
        SUM(Quantity)                                                         AS TotalUnits,
        SUM(GrossRevenue)                                                     AS GrossRevenue,
        SUM(NetRevenue)                                                       AS NetRevenue,
        SUM(CASE WHEN SalesMonth IN ('2018-01', '2018-02') THEN NetRevenue END) / 59 AS DailyRev_JanFeb,
        SUM(CASE WHEN SalesMonth IN ('2018-03', '2018-04') THEN NetRevenue END) / 61 AS DailyRev_MarApr,
        SUM(CASE WHEN SalesMonth IN ('2018-01', '2018-02') THEN Quantity END)   / 59 AS DailyUnits_JanFeb,
        SUM(CASE WHEN SalesMonth IN ('2018-03', '2018-04') THEN Quantity END)   / 61 AS DailyUnits_MarApr
    FROM fact_sales
    GROUP BY CustomerCityID
),
cust AS (SELECT CityID, COUNT(*) AS RegisteredCustomers FROM customers GROUP BY CityID),
emp  AS (SELECT CityID, COUNT(*) AS EmployeesBased     FROM employees GROUP BY CityID)
SELECT
    ci.CityID,
    ci.CityName,
    co.CountryName,
    COALESCE(cust.RegisteredCustomers, 0) AS RegisteredCustomers,
    COALESCE(sc.ActiveCustomers, 0)       AS ActiveCustomers,
    COALESCE(sc.NumTransactions, 0)       AS NumTransactions,
    COALESCE(sc.TotalUnits, 0)            AS TotalUnits,
    COALESCE(sc.GrossRevenue, 0)          AS GrossRevenue,
    COALESCE(sc.NetRevenue, 0)            AS NetRevenue,
    sc.DailyRev_JanFeb,
    sc.DailyRev_MarApr,
    sc.DailyUnits_JanFeb,
    sc.DailyUnits_MarApr,
    COALESCE(emp.EmployeesBased, 0)       AS EmployeesBased
FROM cities ci
JOIN countries co   ON ci.CountryID = co.CountryID
LEFT JOIN sc        ON sc.CityID    = ci.CityID
LEFT JOIN cust      ON cust.CityID  = ci.CityID
LEFT JOIN emp       ON emp.CityID   = ci.CityID;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 5.1 - DOANH THU PHÂN CẤP QUỐC GIA -> THÀNH PHỐ
-- ---------------------------------------------------------------------

/* (a) Phân cấp bằng GROUP BY ... WITH ROLLUP (Grand total -> Country -> City) */
-- @query: t5_1_geo_hierarchy
WITH r AS (
    SELECT
        CASE WHEN GROUPING(CountryName) = 1 THEN 'Grand Total'
             WHEN GROUPING(CityName)    = 1 THEN 'Country'
             ELSE 'City' END                         AS GeoLevel,
        COALESCE(CountryName, '(All countries)')     AS CountryName,
        COALESCE(CityName, '(All cities)')           AS CityName,
        COUNT(*)                                     AS NumCities,
        SUM(ActiveCustomers)                         AS ActiveCustomers,
        SUM(NumTransactions)                         AS NumTransactions,
        SUM(TotalUnits)                              AS TotalUnits,
        SUM(NetRevenue)                              AS NetRevenue
    FROM city_metrics
    GROUP BY CountryName, CityName WITH ROLLUP
)
SELECT
    GeoLevel, CountryName, CityName, NumCities,
    ActiveCustomers, NumTransactions, TotalUnits,
    ROUND(NetRevenue, 2)                                                       AS NetRevenue,
    ROUND(NetRevenue / NULLIF(ActiveCustomers, 0), 2)                          AS RevenuePerCustomer,
    ROUND(NetRevenue * 100 / MAX(CASE WHEN GeoLevel = 'Country' THEN NetRevenue END)
          OVER (PARTITION BY CountryName), 3)                                  AS PctOfCountry,
    ROUND(NetRevenue * 100 / MAX(CASE WHEN GeoLevel = 'Grand Total' THEN NetRevenue END)
          OVER (), 3)                                                          AS PctOfGlobal,
    CASE WHEN GeoLevel = 'City'
         THEN RANK() OVER (PARTITION BY CountryName, GeoLevel ORDER BY NetRevenue DESC) END AS RankInCountry
FROM r
ORDER BY FIELD(GeoLevel, 'Grand Total', 'Country', 'City'), CountryName, NetRevenue DESC;

/* (b) Bảng xếp hạng thành phố + Pareto + phân tầng thị trường */
-- @query: t5_1_city_ranking
SELECT
    RANK() OVER (ORDER BY NetRevenue DESC)                                     AS RevenueRank,
    CountryName, CityName,
    ActiveCustomers, NumTransactions, TotalUnits,
    ROUND(NetRevenue, 2)                                                       AS NetRevenue,
    ROUND(NetRevenue * 100 / SUM(NetRevenue) OVER (), 3)                       AS PctOfGlobal,
    ROUND(SUM(NetRevenue) OVER (ORDER BY NetRevenue DESC, CityID
          ROWS UNBOUNDED PRECEDING) * 100 / SUM(NetRevenue) OVER (), 2)        AS CumPctOfGlobal,
    ROUND(NetRevenue / ActiveCustomers, 2)                                     AS RevenuePerCustomer,
    CASE NTILE(4) OVER (ORDER BY NetRevenue DESC)
        WHEN 1 THEN 'Tier 1 - Key'
        WHEN 2 THEN 'Tier 2 - Growing'
        WHEN 3 THEN 'Tier 3 - Average'
        ELSE        'Tier 4 - Small'
    END                                                                        AS MarketTier
FROM city_metrics
ORDER BY RevenueRank;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 5.2 - CHÊNH LỆCH SẢN LƯỢNG TIÊU THỤ GIỮA CÁC VÙNG
-- ---------------------------------------------------------------------

/* (a) So sánh từng thành phố với trung bình và với thành phố dẫn đầu */
-- @query: t5_2_volume_comparison
WITH v AS (
    SELECT
        CityName, ActiveCustomers, TotalUnits,
        TotalUnits / ActiveCustomers                           AS UnitsPerCustomer,
        AVG(TotalUnits)        OVER ()                         AS AvgUnits,
        MAX(TotalUnits)        OVER ()                         AS MaxUnits,
        STDDEV_POP(TotalUnits) OVER ()                         AS StdUnits,
        SUM(TotalUnits)        OVER ()                         AS SumUnits,
        SUM(TotalUnits) OVER () / SUM(ActiveCustomers) OVER () AS AvgUnitsPerCustomer
    FROM city_metrics
)
SELECT
    RANK() OVER (ORDER BY TotalUnits DESC)                     AS VolumeRank,
    CityName,
    TotalUnits,
    ROUND(TotalUnits * 100.0 / SumUnits, 3)                    AS PctOfTotalUnits,
    ROUND(TotalUnits - AvgUnits, 0)                            AS DiffVsAvgUnits,
    ROUND(TotalUnits * 100 / AvgUnits, 1)                      AS VolumeIndex,          -- 100 = trung bình
    ROUND(TotalUnits - MaxUnits, 0)                            AS GapVsTopCity,
    ROUND((TotalUnits / MaxUnits - 1) * 100, 2)                AS PctGapVsTopCity,
    ROUND((TotalUnits - AvgUnits) / StdUnits, 2)               AS ZScore,
    ActiveCustomers,
    ROUND(UnitsPerCustomer, 1)                                 AS UnitsPerCustomer,
    ROUND(UnitsPerCustomer * 100 / AvgUnitsPerCustomer, 1)     AS UnitsPerCustomerIndex -- 100 = trung bình
FROM v
ORDER BY VolumeRank;

/* (b) Chỉ số phân tán sản lượng giữa các thành phố */
-- @query: t5_2_volume_dispersion
WITH v AS (
    SELECT CityName, TotalUnits,
           ROW_NUMBER() OVER (ORDER BY TotalUnits DESC) AS rn_desc,
           ROW_NUMBER() OVER (ORDER BY TotalUnits ASC)  AS rn_asc,
           COUNT(*) OVER ()                             AS n
    FROM city_metrics
)
SELECT
    MAX(n)                                                              AS NumCities,
    SUM(TotalUnits)                                                     AS TotalUnits,
    ROUND(AVG(TotalUnits), 0)                                           AS MeanUnitsPerCity,
    ROUND(AVG(CASE WHEN rn_asc IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)) THEN TotalUnits END), 0) AS MedianUnitsPerCity,
    MAX(CASE WHEN rn_desc = 1 THEN CityName END)                        AS TopCity,
    MAX(TotalUnits)                                                     AS TopCityUnits,
    MAX(CASE WHEN rn_asc = 1 THEN CityName END)                         AS BottomCity,
    MIN(TotalUnits)                                                     AS BottomCityUnits,
    MAX(TotalUnits) - MIN(TotalUnits)                                   AS MaxMinGap,
    ROUND(MAX(TotalUnits) / MIN(TotalUnits), 3)                         AS MaxMinRatio,
    ROUND(STDDEV_POP(TotalUnits), 0)                                    AS StdDevUnits,
    ROUND(STDDEV_POP(TotalUnits) * 100 / AVG(TotalUnits), 2)            AS CV_Pct,
    ROUND(SUM(CASE WHEN rn_desc <= 10 THEN TotalUnits END) * 100.0 / SUM(TotalUnits), 2) AS Top10CitiesPctUnits,
    ROUND(SUM(CASE WHEN rn_asc  <= 10 THEN TotalUnits END) * 100.0 / SUM(TotalUnits), 2) AS Bottom10CitiesPctUnits
FROM v;

/* (c) So sánh giữa các nhóm vùng (tier tứ phân vị theo sản lượng) */
-- @query: t5_2_tier_comparison
WITH t AS (
    SELECT c.*, NTILE(4) OVER (ORDER BY TotalUnits DESC) AS VolumeTier
    FROM city_metrics c
)
SELECT
    CONCAT('Q', VolumeTier, CASE VolumeTier WHEN 1 THEN ' (highest)' WHEN 4 THEN ' (lowest)' ELSE '' END) AS VolumeTier,
    COUNT(*)                                                           AS NumCities,
    SUM(TotalUnits)                                                    AS TotalUnits,
    ROUND(SUM(TotalUnits) * 100.0 / SUM(SUM(TotalUnits)) OVER (), 2)   AS PctUnits,
    ROUND(AVG(TotalUnits), 0)                                          AS AvgUnitsPerCity,
    SUM(ActiveCustomers)                                               AS ActiveCustomers,
    ROUND(SUM(TotalUnits) / SUM(ActiveCustomers), 1)                   AS UnitsPerCustomer,
    ROUND(SUM(NetRevenue), 2)                                          AS NetRevenue,
    ROUND(SUM(NetRevenue) * 100 / SUM(SUM(NetRevenue)) OVER (), 2)     AS PctRevenue,
    ROUND((SUM(DailyUnits_MarApr) / SUM(DailyUnits_JanFeb) - 1) * 100, 2) AS DailyUnitsGrowthPct
FROM t
GROUP BY VolumeTier
ORDER BY VolumeTier;


-- ---------------------------------------------------------------------
-- NHIỆM VỤ 5.3 - BỘ CHỈ SỐ THẨM ĐỊNH CHIẾN LƯỢC THỊ TRƯỜNG THEO VÙNG
-- ---------------------------------------------------------------------

/* (a) Scorecard từng thị trường (thành phố) + nhóm chiến lược
       Quy mô (Revenue quartile) x Động lượng (Growth quartile) */
-- @query: t5_3_market_scorecard
WITH s AS (
    SELECT c.*,
           NetRevenue / ActiveCustomers                     AS RevenuePerCustomer,
           NumTransactions / ActiveCustomers                AS TxnPerCustomer,
           NetRevenue / NumTransactions                     AS AOV,
           (GrossRevenue - NetRevenue) * 100 / GrossRevenue AS EffDiscountPct,
           (DailyRev_MarApr / DailyRev_JanFeb - 1) * 100    AS GrowthPct,
           ActiveCustomers * 100.0 / RegisteredCustomers    AS ActivationRatePct,
           NTILE(4) OVER (ORDER BY NetRevenue)              AS SizeQ,     -- 4 = lớn nhất
           NTILE(4) OVER (ORDER BY (DailyRev_MarApr / DailyRev_JanFeb)) AS GrowthQ  -- 4 = tăng nhanh nhất
    FROM city_metrics c
)
SELECT
    RANK() OVER (ORDER BY NetRevenue DESC)          AS RevenueRank,
    CityName,
    ROUND(NetRevenue, 2)                            AS NetRevenue,
    ROUND(NetRevenue * 100 / SUM(NetRevenue) OVER (), 3) AS MarketSharePct,
    RegisteredCustomers,
    ROUND(ActivationRatePct, 1)                     AS ActivationRatePct,
    ROUND(RevenuePerCustomer, 2)                    AS RevenuePerCustomer,
    ROUND(TxnPerCustomer, 2)                        AS TxnPerCustomer,
    ROUND(AOV, 2)                                   AS AOV,
    ROUND(EffDiscountPct, 2)                        AS EffDiscountPct,
    ROUND(GrowthPct, 2)                             AS GrowthPct_MarApr_vs_JanFeb,
    EmployeesBased,
    SizeQ, GrowthQ,
    CASE
        WHEN SizeQ = 4 AND GrowthQ >= 3 THEN 'Star - Invest to expand'
        WHEN SizeQ = 4                  THEN 'Cash Cow - Maintain & optimize'
        WHEN SizeQ <= 3 AND GrowthQ = 4 THEN 'Rising - Accelerate growth'
        WHEN SizeQ = 1 AND GrowthQ <= 2 THEN 'Watchlist - Re-evaluate'
        ELSE 'Core - Stable'
    END                                             AS StrategicGroup
FROM s
ORDER BY RevenueRank;

/* (b) Tổng hợp theo nhóm chiến lược */
-- @query: t5_3_strategic_group_summary
WITH s AS (
    SELECT c.*,
           NTILE(4) OVER (ORDER BY NetRevenue) AS SizeQ,
           NTILE(4) OVER (ORDER BY (DailyRev_MarApr / DailyRev_JanFeb)) AS GrowthQ
    FROM city_metrics c
),
g AS (
    SELECT s.*,
        CASE
            WHEN SizeQ = 4 AND GrowthQ >= 3 THEN 'Star - Invest to expand'
            WHEN SizeQ = 4                  THEN 'Cash Cow - Maintain & optimize'
            WHEN SizeQ <= 3 AND GrowthQ = 4 THEN 'Rising - Accelerate growth'
            WHEN SizeQ = 1 AND GrowthQ <= 2 THEN 'Watchlist - Re-evaluate'
            ELSE 'Core - Stable'
        END AS StrategicGroup
    FROM s
)
SELECT
    StrategicGroup,
    COUNT(*)                                                         AS NumCities,
    ROUND(SUM(NetRevenue), 2)                                        AS NetRevenue,
    ROUND(SUM(NetRevenue) * 100 / SUM(SUM(NetRevenue)) OVER (), 2)   AS PctRevenue,
    SUM(ActiveCustomers)                                             AS ActiveCustomers,
    ROUND(SUM(NetRevenue) / SUM(ActiveCustomers), 2)                 AS RevenuePerCustomer,
    ROUND((SUM(DailyRev_MarApr) / SUM(DailyRev_JanFeb) - 1) * 100, 2) AS GrowthPct,
    GROUP_CONCAT(CityName ORDER BY NetRevenue DESC SEPARATOR ', ')   AS Cities
FROM g
GROUP BY StrategicGroup
ORDER BY NetRevenue DESC;

/* (c) KPI tổng quan cho Ban Giám đốc: độ tập trung thị trường & động lực doanh thu */
-- @query: t5_3_board_kpis
WITH s AS (
    SELECT c.*,
           NetRevenue / SUM(NetRevenue) OVER ()                     AS Share,
           SUM(NetRevenue) OVER (ORDER BY NetRevenue DESC, CityID ROWS UNBOUNDED PRECEDING)
               / SUM(NetRevenue) OVER ()                            AS CumShare,
           ROW_NUMBER() OVER (ORDER BY NetRevenue DESC)             AS rn,
           NetRevenue / ActiveCustomers                             AS RevPerCust
    FROM city_metrics c
)
SELECT
    COUNT(*)                                                         AS NumCityMarkets,
    COUNT(DISTINCT CountryName)                                      AS NumCountries,
    ROUND(SUM(NetRevenue), 2)                                        AS TotalNetRevenue,
    ROUND(AVG(NetRevenue), 2)                                        AS AvgRevenuePerCity,
    ROUND(SUM(Share * Share) * 10000, 1)                             AS HHI_Index,   -- <1500: phân tán, >2500: tập trung cao
    ROUND(SUM(CASE WHEN rn <= 5  THEN Share END) * 100, 2)           AS Top5CitiesSharePct,
    ROUND(SUM(CASE WHEN rn <= 10 THEN Share END) * 100, 2)           AS Top10CitiesSharePct,
    MIN(CASE WHEN CumShare >= 0.5 THEN rn END)                       AS CitiesFor50PctRevenue,
    MIN(CASE WHEN CumShare >= 0.8 THEN rn END)                       AS CitiesFor80PctRevenue,
    ROUND(STDDEV_POP(NetRevenue) * 100 / AVG(NetRevenue), 2)         AS CV_RevenueAcrossCities_Pct,
    ROUND(STDDEV_POP(RevPerCust) * 100 / AVG(RevPerCust), 2)         AS CV_RevenuePerCustomer_Pct,
    ROUND((COUNT(*) * SUM(ActiveCustomers * NetRevenue) - SUM(ActiveCustomers) * SUM(NetRevenue))
        / SQRT((COUNT(*) * SUM(ActiveCustomers * ActiveCustomers) - SUM(ActiveCustomers) * SUM(ActiveCustomers))
             * (COUNT(*) * SUM(NetRevenue * NetRevenue) - SUM(NetRevenue) * SUM(NetRevenue))), 4)
                                                                     AS Corr_Customers_vs_Revenue,
    ROUND((SUM(DailyRev_MarApr) / SUM(DailyRev_JanFeb) - 1) * 100, 2) AS SystemGrowthPct_MarApr_vs_JanFeb,
    SUM(DailyRev_MarApr > DailyRev_JanFeb)                           AS NumCitiesGrowing,
    SUM(DailyRev_MarApr <= DailyRev_JanFeb)                          AS NumCitiesDeclining,
    SUM(EmployeesBased > 0)                                          AS CitiesWithSalesOffice
FROM s;

/* (d) Hiệu quả văn phòng / điểm bán theo thành phố nơi nhân viên làm việc
       + tỷ lệ doanh thu bán cho khách hàng CÙNG thành phố (mức độ phủ địa bàn) */
-- @query: t5_3_office_performance
WITH o AS (
    SELECT
        f.EmployeeCityID                                     AS CityID,
        COUNT(DISTINCT f.SalesPersonID)                      AS NumEmployees,
        COUNT(*)                                             AS NumTransactions,
        SUM(f.NetRevenue)                                    AS NetRevenue,
        SUM(CASE WHEN f.CustomerCityID = f.EmployeeCityID THEN f.NetRevenue ELSE 0 END) AS LocalRevenue,
        COUNT(DISTINCT f.CustomerCityID)                     AS CustomerCitiesServed
    FROM fact_sales f
    GROUP BY f.EmployeeCityID
)
SELECT
    ci.CityName                                              AS OfficeCity,
    o.NumEmployees,
    o.NumTransactions,
    ROUND(o.NetRevenue, 2)                                   AS NetRevenue,
    ROUND(o.NetRevenue * 100 / SUM(o.NetRevenue) OVER (), 2) AS PctOfTotal,
    ROUND(o.NetRevenue / o.NumEmployees, 2)                  AS RevenuePerEmployee,
    ROUND(o.LocalRevenue * 100 / o.NetRevenue, 2)            AS PctRevenueFromLocalCustomers,
    o.CustomerCitiesServed,
    ROUND(cm.NetRevenue, 2)                                  AS LocalMarketRevenue  -- doanh thu thị trường tại TP này (mọi NV)
FROM o
JOIN cities ci        ON ci.CityID = o.CityID
JOIN city_metrics cm  ON cm.CityID = o.CityID
ORDER BY RevenuePerEmployee DESC;

/* (e) Thị trường có văn phòng vs không có văn phòng */
-- @query: t5_3_office_coverage
SELECT
    CASE WHEN EmployeesBased > 0 THEN 'Has sales office' ELSE 'No sales office' END AS Coverage,
    COUNT(*)                                                         AS NumCities,
    SUM(ActiveCustomers)                                             AS ActiveCustomers,
    ROUND(SUM(NetRevenue), 2)                                        AS NetRevenue,
    ROUND(SUM(NetRevenue) * 100 / SUM(SUM(NetRevenue)) OVER (), 2)   AS PctRevenue,
    ROUND(AVG(NetRevenue), 2)                                        AS AvgRevenuePerCity,
    ROUND(SUM(NetRevenue) / SUM(ActiveCustomers), 2)                 AS RevenuePerCustomer,
    ROUND((SUM(DailyRev_MarApr) / SUM(DailyRev_JanFeb) - 1) * 100, 2) AS GrowthPct
FROM city_metrics
GROUP BY Coverage;
