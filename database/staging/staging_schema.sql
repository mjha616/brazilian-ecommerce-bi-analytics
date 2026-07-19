-- ============================================================================
-- Enterprise E-Commerce BI Solution - Staging Schema Definition (DDL)
-- Target Database: PostgreSQL (Staging Schema)
-- Purpose: Serve as a landing zone for raw CSV files from source systems.
-- Note: Foreign key constraints are intentionally omitted at this stage 
--       to ensure raw ingestion never fails. Valids & checks occur post-load.
-- ============================================================================

-- Clean up existing staging tables
DROP TABLE IF EXISTS stg_order_reviews CASCADE;
DROP TABLE IF EXISTS stg_order_payments CASCADE;
DROP TABLE IF EXISTS stg_order_items CASCADE;
DROP TABLE IF EXISTS stg_orders CASCADE;
DROP TABLE IF EXISTS stg_products CASCADE;
DROP TABLE IF EXISTS stg_sellers CASCADE;
DROP TABLE IF EXISTS stg_customers CASCADE;
DROP TABLE IF EXISTS stg_geolocation CASCADE;
DROP TABLE IF EXISTS stg_product_category_name_translation CASCADE;

-- 1. Product Category Translation Staging
CREATE TABLE stg_product_category_name_translation (
    product_category_name VARCHAR(150),
    product_category_name_english VARCHAR(150)
);

-- 2. Customers Staging
CREATE TABLE stg_customers (
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(20),
    customer_city VARCHAR(150),
    customer_state VARCHAR(10)
);

-- 3. Geolocation Staging
CREATE TABLE stg_geolocation (
    geolocation_zip_code_prefix VARCHAR(20),
    geolocation_lat VARCHAR(50), -- Read as text to prevent float conversion rounding failures
    geolocation_lng VARCHAR(50),
    geolocation_city VARCHAR(150),
    geolocation_state VARCHAR(10)
);

-- 4. Products Staging
CREATE TABLE stg_products (
    product_id VARCHAR(50),
    product_category_name VARCHAR(150),
    product_name_lenght VARCHAR(20),
    product_description_lenght VARCHAR(20),
    product_photos_qty VARCHAR(20),
    product_weight_g VARCHAR(20),
    product_length_cm VARCHAR(20),
    product_height_cm VARCHAR(20),
    product_width_cm VARCHAR(20)
);

-- 5. Sellers Staging
CREATE TABLE stg_sellers (
    seller_id VARCHAR(50),
    seller_zip_code_prefix VARCHAR(20),
    seller_city VARCHAR(150),
    seller_state VARCHAR(10)
);

-- 6. Orders Staging
CREATE TABLE stg_orders (
    order_id VARCHAR(50),
    customer_id VARCHAR(50),
    order_status VARCHAR(50),
    order_purchase_timestamp VARCHAR(50),
    order_approved_at VARCHAR(50),
    order_delivered_carrier_date VARCHAR(50),
    order_delivered_customer_date VARCHAR(50),
    order_estimated_delivery_date VARCHAR(50)
);

-- 7. Order Items Staging
CREATE TABLE stg_order_items (
    order_id VARCHAR(50),
    order_item_id VARCHAR(20),
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date VARCHAR(50),
    price VARCHAR(20),
    freight_value VARCHAR(20)
);

-- 8. Order Payments Staging
CREATE TABLE stg_order_payments (
    order_id VARCHAR(50),
    payment_sequential VARCHAR(20),
    payment_type VARCHAR(50),
    payment_installments VARCHAR(20),
    payment_value VARCHAR(20)
);

-- 9. Order Reviews Staging
CREATE TABLE stg_order_reviews (
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score VARCHAR(20),
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date VARCHAR(50),
    review_answer_timestamp VARCHAR(50)
);

-- ============================================================================
-- DATA INGESTION (COPY Commands)
-- Note: Referencing local Windows path 'C:/dataset/'
-- ============================================================================

-- 1. Product Category Translations
COPY stg_product_category_name_translation (
    product_category_name, 
    product_category_name_english
)
FROM 'C:/dataset/product_category_name_translation.csv' 
DELIMITER ',' CSV HEADER;

-- 2. Customers
COPY stg_customers (
    customer_id, 
    customer_unique_id, 
    customer_zip_code_prefix, 
    customer_city, 
    customer_state
)
FROM 'C:/dataset/olist_customers_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 3. Geolocation
COPY stg_geolocation (
    geolocation_zip_code_prefix, 
    geolocation_lat, 
    geolocation_lng, 
    geolocation_city, 
    geolocation_state
)
FROM 'C:/dataset/olist_geolocation_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 4. Products
COPY stg_products (
    product_id, 
    product_category_name, 
    product_name_lenght, 
    product_description_lenght, 
    product_photos_qty, 
    product_weight_g, 
    product_length_cm, 
    product_height_cm, 
    product_width_cm
)
FROM 'C:/dataset/olist_products_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 5. Sellers
COPY stg_sellers (
    seller_id, 
    seller_zip_code_prefix, 
    seller_city, 
    seller_state
)
FROM 'C:/dataset/olist_sellers_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 6. Orders
COPY stg_orders (
    order_id, 
    customer_id, 
    order_status, 
    order_purchase_timestamp, 
    order_approved_at, 
    order_delivered_carrier_date, 
    order_delivered_customer_date, 
    order_estimated_delivery_date
)
FROM 'C:/dataset/olist_orders_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 7. Order Items
COPY stg_order_items (
    order_id, 
    order_item_id, 
    product_id, 
    seller_id, 
    shipping_limit_date, 
    price, 
    freight_value
)
FROM 'C:/dataset/olist_order_items_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 8. Order Payments
COPY stg_order_payments (
    order_id, 
    payment_sequential, 
    payment_type, 
    payment_installments, 
    payment_value
)
FROM 'C:/dataset/olist_order_payments_dataset.csv' 
DELIMITER ',' CSV HEADER;

-- 9. Order Reviews
COPY stg_order_reviews (
    review_id, 
    order_id, 
    review_score, 
    review_comment_title, 
    review_comment_message, 
    review_creation_date, 
    review_answer_timestamp
)
FROM 'C:/dataset/olist_order_reviews_dataset.csv' 
DELIMITER ',' CSV HEADER;
