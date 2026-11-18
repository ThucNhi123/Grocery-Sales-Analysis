-- =====================================================
-- GROCERY SALES DATABASE - SCHEMA CREATION
-- Thứ tự tạo bảng: bảng cha (không FK) trước, bảng con sau
-- =====================================================

-- 0. TẠO DATABASE VÀ CHUYỂN VÀO ĐÓ LÀM VIỆC
-- MySQL 8.x
CREATE DATABASE IF NOT EXISTS grocery_sales_db;
USE grocery_sales_db;

-- 1. COUNTRIES (không phụ thuộc bảng nào)
CREATE TABLE countries (
    CountryID   INT PRIMARY KEY,
    CountryName VARCHAR(45),
    CountryCode VARCHAR(2)
);

-- 2. CATEGORIES (không phụ thuộc bảng nào)
CREATE TABLE categories (
    CategoryID   INT PRIMARY KEY,
    CategoryName VARCHAR(45)
);

-- 3. CITIES (phụ thuộc countries)
CREATE TABLE cities (
    CityID    INT PRIMARY KEY,
    CityName  VARCHAR(45),
    Zipcode   DECIMAL(5,0),
    CountryID INT,
    CONSTRAINT fk_cities_country
        FOREIGN KEY (CountryID) REFERENCES countries(CountryID)
);

-- 4. CUSTOMERS (phụ thuộc cities)
CREATE TABLE customers (
    CustomerID    INT PRIMARY KEY,
    FirstName     VARCHAR(45),
    MiddleInitial VARCHAR(1),
    LastName      VARCHAR(45),
    CityID        INT,
    Address       VARCHAR(90),
    CONSTRAINT fk_customers_city
        FOREIGN KEY (CityID) REFERENCES cities(CityID)
);

-- 5. EMPLOYEES (phụ thuộc cities)
CREATE TABLE employees (
    EmployeeID    INT PRIMARY KEY,
    FirstName     VARCHAR(45),
    MiddleInitial VARCHAR(1),
    LastName      VARCHAR(45),
    BirthDate     DATE,
    Gender        VARCHAR(10),
    CityID        INT,
    HireDate      DATE,
    CONSTRAINT fk_employees_city
        FOREIGN KEY (CityID) REFERENCES cities(CityID)
);

-- 6. PRODUCTS (phụ thuộc categories)
CREATE TABLE products (
    ProductID INT PRIMARY KEY,
    ProductName VARCHAR(255),
    Price DECIMAL(10,4),
    CategoryID INT,
    Class VARCHAR(20),
    ModifyDate DATETIME,
    Resistant VARCHAR(20),
    IsAllergic VARCHAR(10),
    VitalityDays FLOAT,
    FOREIGN KEY (CategoryID) REFERENCES categories(CategoryID)
);

-- 7. SALES (bảng fact - phụ thuộc employees, customers, products)
CREATE TABLE sales (
    SalesID           INT PRIMARY KEY,
    SalesPersonID     INT,
    CustomerID        INT,
    ProductID         INT,
    Quantity          INT,
    Discount          DECIMAL(10,2),
    TotalPrice        DECIMAL(10,2),
    SalesDate         DATETIME,
    TransactionNumber VARCHAR(25),
    CONSTRAINT fk_sales_employee
        FOREIGN KEY (SalesPersonID) REFERENCES employees(EmployeeID),
    CONSTRAINT fk_sales_customer
        FOREIGN KEY (CustomerID) REFERENCES customers(CustomerID),
    CONSTRAINT fk_sales_product
        FOREIGN KEY (ProductID) REFERENCES products(ProductID)
);

-- =====================================================
-- INDEX GỢI Ý (tăng tốc JOIN/GROUP BY trên 7 triệu dòng)
-- =====================================================
CREATE INDEX idx_sales_product   ON sales(ProductID);
CREATE INDEX idx_sales_customer  ON sales(CustomerID);
CREATE INDEX idx_sales_employee  ON sales(SalesPersonID);
CREATE INDEX idx_sales_date      ON sales(SalesDate);

CREATE INDEX idx_customers_city  ON customers(CityID);
CREATE INDEX idx_employees_city  ON employees(CityID);
CREATE INDEX idx_products_cat    ON products(CategoryID);
CREATE INDEX idx_cities_country  ON cities(CountryID);


