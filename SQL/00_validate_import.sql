-- =====================================================
-- VALIDATION SCRIPT - Kiểm tra chất lượng dữ liệu sau import
-- Chạy sau khi đã import xong cả 7 bảng
-- =====================================================

-- =====================================================
-- 1. ĐẾM SỐ DÒNG MỖI BẢNG
-- So sánh với số dòng thực tế trong file CSV (mở file hoặc wc -l)
-- để chắc chắn import không bị thiếu/dư dòng nào
-- =====================================================
SELECT 'countries' AS table_name, COUNT(*) AS row_count FROM countries
UNION ALL
SELECT 'categories', COUNT(*) FROM categories
UNION ALL
SELECT 'cities', COUNT(*) FROM cities
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'employees', COUNT(*) FROM employees
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sales', COUNT(*) FROM sales;


-- =====================================================
-- 2. CHECK NULL Ở CÁC CỘT FK
-- Nếu FK bị NULL, dòng đó sẽ "rớt" khỏi kết quả khi JOIN
-- (trừ khi cố tình dùng LEFT JOIN) -> cần biết trước bao nhiêu dòng bị vậy
-- =====================================================
SELECT
    COUNT(*) AS total_sales,
    SUM(CASE WHEN SalesPersonID IS NULL THEN 1 ELSE 0 END) AS null_salesperson,
    SUM(CASE WHEN CustomerID   IS NULL THEN 1 ELSE 0 END) AS null_customer,
    SUM(CASE WHEN ProductID    IS NULL THEN 1 ELSE 0 END) AS null_product
FROM sales;

SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN CityID IS NULL THEN 1 ELSE 0 END) AS null_city
FROM customers;

SELECT
    COUNT(*) AS total_employees,
    SUM(CASE WHEN CityID IS NULL THEN 1 ELSE 0 END) AS null_city
FROM employees;

SELECT
    COUNT(*) AS total_products,
    SUM(CASE WHEN CategoryID IS NULL THEN 1 ELSE 0 END) AS null_category
FROM products;

SELECT
    COUNT(*) AS total_cities,
    SUM(CASE WHEN CountryID IS NULL THEN 1 ELSE 0 END) AS null_country
FROM cities;


-- =====================================================
-- 3. CHECK TRÙNG LẶP PRIMARY KEY
-- Nếu PK có ràng buộc UNIQUE thật sự thì bước này sẽ luôn ra 0 dòng,
-- nhưng vẫn nên check để chắc chắn schema/constraint hoạt động đúng
-- (đặc biệt hữu ích nếu import bằng công cụ bỏ qua constraint check)
-- =====================================================
SELECT SalesID, COUNT(*) AS num_duplicates
FROM sales
GROUP BY SalesID
HAVING COUNT(*) > 1;

SELECT ProductID, COUNT(*) AS num_duplicates
FROM products
GROUP BY ProductID
HAVING COUNT(*) > 1;

SELECT CustomerID, COUNT(*) AS num_duplicates
FROM customers
GROUP BY CustomerID
HAVING COUNT(*) > 1;

-- Check trùng TransactionNumber (không phải PK nhưng nên là duy nhất mỗi hóa đơn)
SELECT TransactionNumber, COUNT(DISTINCT SalesID) AS num_lines
FROM sales
GROUP BY TransactionNumber
HAVING COUNT(DISTINCT SalesID) > 1
LIMIT 20;
-- Lưu ý: 1 TransactionNumber có nhiều SalesID là BÌNH THƯỜNG
-- (1 hóa đơn có nhiều dòng sản phẩm). Query này chỉ để xem thử,
-- không phải lỗi dữ liệu.


-- =====================================================
-- 4. CHECK ORPHAN RECORDS (dòng con có FK nhưng không tìm thấy dòng cha)
-- Đây là bước quan trọng nhất: nếu có orphan, INNER JOIN sau này
-- sẽ âm thầm loại bỏ những dòng đó -> doanh thu/số liệu bị sai lệch
-- mà không có cảnh báo gì.
-- =====================================================

-- 4.1 Sales có ProductID không tồn tại trong products
SELECT s.ProductID, COUNT(*) AS orphan_rows
FROM sales s
LEFT JOIN products p ON s.ProductID = p.ProductID
WHERE p.ProductID IS NULL
GROUP BY s.ProductID;

-- 4.2 Sales có CustomerID không tồn tại trong customers
SELECT s.CustomerID, COUNT(*) AS orphan_rows
FROM sales s
LEFT JOIN customers c ON s.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL
GROUP BY s.CustomerID;

-- 4.3 Sales có SalesPersonID không tồn tại trong employees
SELECT s.SalesPersonID, COUNT(*) AS orphan_rows
FROM sales s
LEFT JOIN employees e ON s.SalesPersonID = e.EmployeeID
WHERE e.EmployeeID IS NULL
GROUP BY s.SalesPersonID;

-- 4.4 Customers có CityID không tồn tại trong cities
SELECT c.CityID, COUNT(*) AS orphan_rows
FROM customers c
LEFT JOIN cities ci ON c.CityID = ci.CityID
WHERE ci.CityID IS NULL
GROUP BY c.CityID;

-- 4.5 Employees có CityID không tồn tại trong cities
SELECT e.CityID, COUNT(*) AS orphan_rows
FROM employees e
LEFT JOIN cities ci ON e.CityID = ci.CityID
WHERE ci.CityID IS NULL
GROUP BY e.CityID;

-- 4.6 Products có CategoryID không tồn tại trong categories
SELECT p.CategoryID, COUNT(*) AS orphan_rows
FROM products p
LEFT JOIN categories c ON p.CategoryID = c.CategoryID
WHERE c.CategoryID IS NULL
GROUP BY p.CategoryID;

-- 4.7 Cities có CountryID không tồn tại trong countries
SELECT ci.CountryID, COUNT(*) AS orphan_rows
FROM cities ci
LEFT JOIN countries co ON ci.CountryID = co.CountryID
WHERE co.CountryID IS NULL
GROUP BY ci.CountryID;

-- Tất cả 7 query mục 4: nếu ra 0 dòng (empty result) nghĩa là SẠCH,
-- không có orphan record nào. Nếu ra kết quả -> cần quay lại xem
-- data gốc, quyết định xóa dòng đó hay gán giá trị mặc định.


-- =====================================================
-- 5. CHECK GIÁ TRỊ BẤT THƯỜNG (ngoài phạm vi FK nhưng đáng kiểm tra)
-- =====================================================

-- Quantity hoặc TotalPrice âm/bằng 0 - có thể là lỗi nhập liệu hoặc đơn hủy
SELECT COUNT(*) AS suspicious_rows
FROM sales
WHERE Quantity <= 0 OR TotalPrice < 0;

-- Discount vượt quá 100% (nếu Discount lưu dạng tỷ lệ 0-1) hoặc âm
SELECT COUNT(*) AS suspicious_discount
FROM sales
WHERE Discount < 0 OR Discount > 1;
-- Nếu Discount lưu dạng số tiền (không phải %), sửa điều kiện lại cho phù hợp

-- SalesDate nằm ngoài phạm vi 4 tháng mà đề bài mô tả
SELECT MIN(SalesDate) AS earliest_date, MAX(SalesDate) AS latest_date
FROM sales;