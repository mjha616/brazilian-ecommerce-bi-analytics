-- ============================================================================
-- Enterprise E-Commerce BI Solution - Data Warehouse Schema (DDL)
-- Target Database: PostgreSQL (Warehouse Layer)
-- Purpose: Physical tables modeling a high-performance Star Schema.
--
-- Why do enterprise warehouses never rely on raw timestamps?
-- 1. Minimizing Cardinality: Timestamps contain hours, minutes, and seconds, 
--    creating high-cardinality values that bloat index structures and slow down joins.
-- 2. Standardized Business Logic: Pre-calculating fiscal calendars, weekends, 
--    and regional holidays in a single dimension ensures that Finance, Sales, 
--    and Logistics reports use identical period definitions.
-- 3. Simplifying DAX & SQL: Queries can group, slice, and filter on fields like 
--    `weekend_flag` or `fiscal_quarter` without performing runtime date parsing.
-- ============================================================================

-- Clean up existing warehouse tables
DROP TABLE IF EXISTS fact_order_reviews CASCADE;
DROP TABLE IF EXISTS fact_order_payments CASCADE;
DROP TABLE IF EXISTS fact_order_items CASCADE;
DROP TABLE IF EXISTS dim_orders CASCADE;
DROP TABLE IF EXISTS dim_products CASCADE;
DROP TABLE IF EXISTS dim_sellers CASCADE;
DROP TABLE IF EXISTS dim_customers CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;

-- ============================================================================
-- 1. DIMENSION TABLES
-- ============================================================================

-- 1.1 Date Dimension (Physical Calendar Table)
CREATE TABLE dim_date (
    date_actual DATE PRIMARY KEY,
    epoch BIGINT NOT NULL,
    year_actual INTEGER NOT NULL CHECK (year_actual >= 2000),
    quarter_actual INTEGER NOT NULL CHECK (quarter_actual BETWEEN 1 AND 4),
    month_actual INTEGER NOT NULL CHECK (month_actual BETWEEN 1 AND 12),
    month_name VARCHAR(15) NOT NULL,
    month_name_short CHAR(3) NOT NULL,
    week_of_year INTEGER NOT NULL CHECK (week_of_year BETWEEN 1 AND 53),
    day_of_month INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 31),
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    day_name VARCHAR(15) NOT NULL,
    day_name_short CHAR(3) NOT NULL,
    weekend_flag BOOLEAN NOT NULL,
    fiscal_year INTEGER NOT NULL,
    fiscal_quarter CHAR(2) NOT NULL,
    month_start_date DATE NOT NULL,
    month_end_date DATE NOT NULL
);

-- 1.2 Customer Dimension
CREATE TABLE dim_customers (
    customer_unique_id CHAR(32) PRIMARY KEY,
    customer_zip_code_prefix VARCHAR(10) NOT NULL,
    customer_city VARCHAR(100) NOT NULL,
    customer_state CHAR(2) NOT NULL
);

-- 1.3 Product Dimension
CREATE TABLE dim_products (
    product_id CHAR(32) PRIMARY KEY,
    category VARCHAR(100) NOT NULL,
    weight_g INTEGER NOT NULL,
    length_cm INTEGER NOT NULL,
    height_cm INTEGER NOT NULL,
    width_cm INTEGER NOT NULL,
    volume_cm3 INTEGER NOT NULL
);

-- 1.4 Seller Dimension
CREATE TABLE dim_sellers (
    seller_id CHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10) NOT NULL,
    seller_city VARCHAR(100) NOT NULL,
    seller_state CHAR(2) NOT NULL
);

-- 1.5 Order Dimension (Order Level Details)
CREATE TABLE dim_orders (
    order_id CHAR(32) PRIMARY KEY,
    customer_id CHAR(32) NOT NULL,
    customer_unique_id CHAR(32) NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    purchase_timestamp TIMESTAMP NOT NULL,
    purchase_date DATE NOT NULL, -- FK to dim_date
    approved_timestamp TIMESTAMP,
    carrier_timestamp TIMESTAMP,
    delivered_timestamp TIMESTAMP,
    delivered_date DATE,
    estimated_timestamp TIMESTAMP NOT NULL,
    estimated_date DATE NOT NULL,
    delivery_lead_time_days INTEGER,
    delivery_delay_days INTEGER,
    is_late INTEGER NOT NULL CHECK (is_late IN (0, 1))
);

-- ============================================================================
-- 2. FACT TABLES
-- ============================================================================

-- 2.1 Sales Fact Table (Order Item Level Grain)
CREATE TABLE fact_order_items (
    order_id CHAR(32) NOT NULL,
    order_item_id INTEGER NOT NULL,
    product_id CHAR(32) NOT NULL,
    seller_id CHAR(32) NOT NULL,
    customer_unique_id CHAR(32) NOT NULL,
    purchase_date DATE NOT NULL, -- FK to dim_date
    shipping_limit_date DATE NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    freight_value NUMERIC(10, 2) NOT NULL CHECK (freight_value >= 0),
    gross_merchandise_value NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_fact_items_orders FOREIGN KEY (order_id) 
        REFERENCES dim_orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_fact_items_products FOREIGN KEY (product_id) 
        REFERENCES dim_products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fact_items_sellers FOREIGN KEY (seller_id) 
        REFERENCES dim_sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fact_items_customers FOREIGN KEY (customer_unique_id) 
        REFERENCES dim_customers(customer_unique_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fact_items_date FOREIGN KEY (purchase_date) 
        REFERENCES dim_date(date_actual) ON DELETE RESTRICT
);

-- 2.2 Payment Fact Table (Payment Instance Level Grain)
CREATE TABLE fact_order_payments (
    order_id CHAR(32) NOT NULL,
    payment_sequential INTEGER NOT NULL,
    payment_type VARCHAR(30) NOT NULL,
    payment_installments INTEGER NOT NULL CHECK (payment_installments >= 0),
    payment_value NUMERIC(10, 2) NOT NULL CHECK (payment_value >= 0),
    purchase_date DATE NOT NULL, -- FK to dim_date
    customer_unique_id CHAR(32) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_fact_payments_orders FOREIGN KEY (order_id) 
        REFERENCES dim_orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_fact_payments_customers FOREIGN KEY (customer_unique_id) 
        REFERENCES dim_customers(customer_unique_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fact_payments_date FOREIGN KEY (purchase_date) 
        REFERENCES dim_date(date_actual) ON DELETE RESTRICT
);

-- 2.3 Review Fact Table (Review Instance Level Grain)
CREATE TABLE fact_order_reviews (
    review_id CHAR(32) NOT NULL,
    order_id CHAR(32) NOT NULL,
    review_score SMALLINT NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_creation_date DATE NOT NULL,
    review_answer_timestamp TIMESTAMP,
    customer_unique_id CHAR(32) NOT NULL,
    purchase_date DATE NOT NULL, -- FK to dim_date
    PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_fact_reviews_orders FOREIGN KEY (order_id) 
        REFERENCES dim_orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_fact_reviews_customers FOREIGN KEY (customer_unique_id) 
        REFERENCES dim_customers(customer_unique_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fact_reviews_date FOREIGN KEY (purchase_date) 
        REFERENCES dim_date(date_actual) ON DELETE RESTRICT
);
