-- ============================================================================
-- Enterprise E-Commerce BI Solution - ELT Migration Script
-- Target Database: PostgreSQL
-- Purpose: Extract, clean, and load staging data into the physical Star Schema.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: Populate Physical Calendar Dimension (dim_date)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE dim_date CASCADE;

INSERT INTO dim_date (
    date_actual,
    epoch,
    year_actual,
    quarter_actual,
    month_actual,
    month_name,
    month_name_short,
    week_of_year,
    day_of_month,
    day_of_week,
    day_name,
    day_name_short,
    weekend_flag,
    fiscal_year,
    fiscal_quarter,
    month_start_date,
    month_end_date
)
SELECT
    datum AS date_actual,
    EXTRACT(EPOCH FROM datum) AS epoch,
    EXTRACT(YEAR FROM datum) AS year_actual,
    EXTRACT(QUARTER FROM datum) AS quarter_actual,
    EXTRACT(MONTH FROM datum) AS month_actual,
    TO_CHAR(datum, 'Month') AS month_name,
    TO_CHAR(datum, 'Mon') AS month_name_short,
    EXTRACT(WEEK FROM datum) AS week_of_year,
    EXTRACT(DAY FROM datum) AS day_of_month,
    EXTRACT(ISODOW FROM datum) AS day_of_week,
    TO_CHAR(datum, 'Day') AS day_name,
    TO_CHAR(datum, 'Dy') AS day_name_short,
    CASE WHEN EXTRACT(ISODOW FROM datum) IN (6, 7) THEN TRUE ELSE FALSE END AS weekend_flag,
    -- Fiscal Year: Custom corporate calendar starting April 1
    CASE 
        WHEN EXTRACT(MONTH FROM datum) >= 4 THEN EXTRACT(YEAR FROM datum)
        ELSE EXTRACT(YEAR FROM datum) - 1
    END AS fiscal_year,
    -- Fiscal Quarter definition starting April
    CASE 
        WHEN EXTRACT(MONTH FROM datum) BETWEEN 4 AND 6 THEN 'Q1'
        WHEN EXTRACT(MONTH FROM datum) BETWEEN 7 AND 9 THEN 'Q2'
        WHEN EXTRACT(MONTH FROM datum) BETWEEN 10 AND 12 THEN 'Q3'
        ELSE 'Q4'
    END AS fiscal_quarter,
    (DATE_TRUNC('month', datum))::date AS month_start_date,
    (DATE_TRUNC('month', datum) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date
FROM GENERATE_SERIES(
    '2016-01-01'::date,
    '2020-12-31'::date,
    '1 day'::interval
) AS datum;

-- ----------------------------------------------------------------------------
-- STEP 2: Load Customer Dimension (dim_customers)
-- Cleaning: Deduplicate by unique customer ID, capitalize city names, and convert states to uppercase.
-- ----------------------------------------------------------------------------
TRUNCATE TABLE dim_customers CASCADE;

INSERT INTO dim_customers (
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT DISTINCT ON (customer_unique_id)
    customer_unique_id,
    customer_zip_code_prefix,
    INITCAP(customer_city),
    UPPER(customer_state)
FROM stg_customers
WHERE customer_unique_id IS NOT NULL 
  AND customer_unique_id != ''
ORDER BY customer_unique_id, customer_city;

-- ----------------------------------------------------------------------------
-- STEP 3: Load Product Dimension (dim_products)
-- Cleaning: Translate category names, handle null values, and compute volume metrics.
-- ----------------------------------------------------------------------------
TRUNCATE TABLE dim_products CASCADE;

INSERT INTO dim_products (
    product_id,
    category,
    weight_g,
    length_cm,
    height_cm,
    width_cm,
    volume_cm3
)
SELECT
    p.product_id,
    COALESCE(INITCAP(t.product_category_name_english), 'Uncategorized') AS category,
    COALESCE(NULLIF(p.product_weight_g, '')::INTEGER, 0) AS weight_g,
    COALESCE(NULLIF(p.product_length_cm, '')::INTEGER, 0) AS length_cm,
    COALESCE(NULLIF(p.product_height_cm, '')::INTEGER, 0) AS height_cm,
    COALESCE(NULLIF(p.product_width_cm, '')::INTEGER, 0) AS width_cm,
    -- Pre-calculate spatial volume to optimize BI analytical reports
    COALESCE(
        NULLIF(p.product_length_cm, '')::INTEGER * 
        NULLIF(p.product_height_cm, '')::INTEGER * 
        NULLIF(p.product_width_cm, '')::INTEGER, 
        0
    ) AS volume_cm3
FROM stg_products p
LEFT JOIN stg_product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_id IS NOT NULL 
  AND p.product_id != '';

-- ----------------------------------------------------------------------------
-- STEP 4: Load Seller Dimension (dim_sellers)
-- Deduplicate and standardize city names.
-- ----------------------------------------------------------------------------
TRUNCATE TABLE dim_sellers CASCADE;

INSERT INTO dim_sellers (
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT DISTINCT ON (seller_id)
    seller_id,
    seller_zip_code_prefix,
    INITCAP(seller_city),
    UPPER(seller_state)
FROM stg_sellers
WHERE seller_id IS NOT NULL 
  AND seller_id != '';

-- ----------------------------------------------------------------------------
-- STEP 5: Load Order Dimension (dim_orders)
-- Cleaning: Cast string timestamps to timestamps/dates, calculate delivery days, delays, and late flag.
-- ----------------------------------------------------------------------------
TRUNCATE TABLE dim_orders CASCADE;

INSERT INTO dim_orders (
    order_id,
    customer_id,
    customer_unique_id,
    order_status,
    purchase_timestamp,
    purchase_date,
    approved_timestamp,
    carrier_timestamp,
    delivered_timestamp,
    delivered_date,
    estimated_timestamp,
    estimated_date,
    delivery_lead_time_days,
    delivery_delay_days,
    is_late
)
SELECT DISTINCT ON (o.order_id)
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    o.order_status,
    o.order_purchase_timestamp::timestamp AS purchase_timestamp,
    o.order_purchase_timestamp::date AS purchase_date,
    NULLIF(o.order_approved_at, '')::timestamp AS approved_timestamp,
    NULLIF(o.order_delivered_carrier_date, '')::timestamp AS carrier_timestamp,
    NULLIF(o.order_delivered_customer_date, '')::timestamp AS delivered_timestamp,
    NULLIF(o.order_delivered_customer_date, '')::date AS delivered_date,
    o.order_estimated_delivery_date::timestamp AS estimated_timestamp,
    o.order_estimated_delivery_date::date AS estimated_date,
    -- Lead time: days from purchase to customer delivery
    CASE 
        WHEN o.order_delivered_customer_date != '' AND o.order_delivered_customer_date IS NOT NULL
        THEN DATE_PART('day', o.order_delivered_customer_date::timestamp - o.order_purchase_timestamp::timestamp)::INTEGER
        ELSE NULL
    END AS delivery_lead_time_days,
    -- Delay: days from estimation to customer delivery (positive = late, negative = early)
    CASE 
        WHEN o.order_delivered_customer_date != '' AND o.order_delivered_customer_date IS NOT NULL
        THEN DATE_PART('day', o.order_delivered_customer_date::timestamp - o.order_estimated_delivery_date::timestamp)::INTEGER
        ELSE NULL
    END AS delivery_delay_days,
    -- Binary flag for on-time delivery KPIs
    CASE 
        WHEN o.order_delivered_customer_date != '' AND o.order_delivered_customer_date IS NOT NULL 
             AND o.order_delivered_customer_date::timestamp > o.order_estimated_delivery_date::timestamp 
        THEN 1
        ELSE 0
    END AS is_late
FROM stg_orders o
JOIN stg_customers c ON o.customer_id = c.customer_id
WHERE o.order_id IS NOT NULL 
  AND o.order_id != '';

-- ----------------------------------------------------------------------------
-- STEP 6: Load Sales Fact Table (fact_order_items)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE fact_order_items CASCADE;

INSERT INTO fact_order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    customer_unique_id,
    purchase_date,
    shipping_limit_date,
    price,
    freight_value,
    gross_merchandise_value
)
SELECT
    oi.order_id,
    oi.order_item_id::INTEGER,
    oi.product_id,
    oi.seller_id,
    o.customer_unique_id,
    o.purchase_date,
    oi.shipping_limit_date::date,
    oi.price::numeric,
    oi.freight_value::numeric,
    (oi.price::numeric + oi.freight_value::numeric) AS gross_merchandise_value
FROM stg_order_items oi
JOIN dim_orders o ON oi.order_id = o.order_id
JOIN dim_products p ON oi.product_id = p.product_id
JOIN dim_sellers s ON oi.seller_id = s.seller_id;

-- ----------------------------------------------------------------------------
-- STEP 7: Load Payment Fact Table (fact_order_payments)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE fact_order_payments CASCADE;

INSERT INTO fact_order_payments (
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value,
    purchase_date,
    customer_unique_id
)
SELECT
    op.order_id,
    op.payment_sequential::INTEGER,
    op.payment_type,
    op.payment_installments::INTEGER,
    op.payment_value::numeric,
    o.purchase_date,
    o.customer_unique_id
FROM stg_order_payments op
JOIN dim_orders o ON op.order_id = o.order_id;

-- ----------------------------------------------------------------------------
-- STEP 8: Load Review Fact Table (fact_order_reviews)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE fact_order_reviews CASCADE;

INSERT INTO fact_order_reviews (
    review_id,
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    customer_unique_id,
    purchase_date
)
SELECT
    r.review_id,
    r.order_id,
    r.review_score::SMALLINT,
    r.review_creation_date::date,
    NULLIF(r.review_answer_timestamp, '')::timestamp,
    o.customer_unique_id,
    o.purchase_date
FROM stg_order_reviews r
JOIN dim_orders o ON r.order_id = o.order_id;
