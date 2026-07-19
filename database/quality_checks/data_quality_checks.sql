-- ============================================================================
-- Enterprise E-Commerce BI Solution - Data Quality Assertion Framework
-- Target Database: PostgreSQL
-- Purpose: Implement auditing scripts to flag anomalies in staging before loading.
--
-- Why validate data BEFORE loading the warehouse in enterprise BI?
-- 1. Garbage In, Garbage Out (GIGO): If dirty data enters the warehouse, it corrupts 
--    subsequent aggregations, resulting in incorrect KPI reports for executives.
-- 2. Performance Safeguard: Invalid rows (like circular references or orphan records)
--    can break physical PK/FK constraints, causing loading jobs to fail midway.
-- 3. System Auditing: Quality audits provide data lineage logs, helping BI and 
--    Data Engineering teams isolate bugs in upstream transactional software.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CHECK 1: Duplicate Orders
-- Expectation: order_id must be unique in stg_orders.
-- ----------------------------------------------------------------------------
SELECT 
    'Duplicate Orders' AS check_name,
    COUNT(DISTINCT order_id) AS total_unique_records,
    COUNT(order_id) - COUNT(DISTINCT order_id) AS duplicate_count,
    CASE 
        WHEN COUNT(order_id) = COUNT(DISTINCT order_id) THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM stg_orders;

-- ----------------------------------------------------------------------------
-- CHECK 2: Duplicate Customers
-- Expectation: customer_id must be unique in stg_customers.
-- ----------------------------------------------------------------------------
SELECT 
    'Duplicate Customers' AS check_name,
    COUNT(DISTINCT customer_id) AS total_unique_records,
    COUNT(customer_id) - COUNT(DISTINCT customer_id) AS duplicate_count,
    CASE 
        WHEN COUNT(customer_id) = COUNT(DISTINCT customer_id) THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM stg_customers;

-- ----------------------------------------------------------------------------
-- CHECK 3: Null Primary Keys
-- Expectation: Vital identifiers must not be NULL.
-- ----------------------------------------------------------------------------
SELECT 
    'Null Primary Keys (stg_orders)' AS check_name,
    COUNT(*) - COUNT(order_id) AS null_pk_count,
    CASE WHEN COUNT(*) = COUNT(order_id) THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_orders
UNION ALL
SELECT 
    'Null Primary Keys (stg_customers)' AS check_name,
    COUNT(*) - COUNT(customer_id) AS null_pk_count,
    CASE WHEN COUNT(*) = COUNT(customer_id) THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_customers
UNION ALL
SELECT 
    'Null Primary Keys (stg_products)' AS check_name,
    COUNT(*) - COUNT(product_id) AS null_pk_count,
    CASE WHEN COUNT(*) = COUNT(product_id) THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_products
UNION ALL
SELECT 
    'Null Primary Keys (stg_sellers)' AS check_name,
    COUNT(*) - COUNT(seller_id) AS null_pk_count,
    CASE WHEN COUNT(*) = COUNT(seller_id) THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_sellers;

-- ----------------------------------------------------------------------------
-- CHECK 4: Missing Foreign Keys (Referential Integrity Check - Orders vs Customers)
-- Expectation: Every order must link to a valid customer in the customer registry.
-- ----------------------------------------------------------------------------
SELECT 
    'Orphaned Orders (Missing Customer)' AS check_name,
    COUNT(o.order_id) AS orphan_count,
    CASE WHEN COUNT(o.order_id) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_orders o
LEFT JOIN stg_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- ----------------------------------------------------------------------------
-- CHECK 5: Invalid Dates (Date Formatting Check)
-- Expectation: String timestamps must conform to ISO format YYYY-MM-DD HH:MM:SS.
-- ----------------------------------------------------------------------------
SELECT 
    'Invalid Purchase Timestamps' AS check_name,
    COUNT(*) AS invalid_format_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_orders
WHERE order_purchase_timestamp IS NOT NULL 
  AND order_purchase_timestamp !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';

-- ----------------------------------------------------------------------------
-- CHECK 6: Future Dates Check
-- Expectation: Purchase timestamps must not be in the future relative to system time.
-- ----------------------------------------------------------------------------
SELECT 
    'Future Purchase Dates' AS check_name,
    COUNT(*) AS future_date_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_orders
WHERE order_purchase_timestamp::timestamp > NOW();

-- ----------------------------------------------------------------------------
-- CHECK 7: Negative Prices Check
-- Expectation: Product pricing in order items must be positive.
-- ----------------------------------------------------------------------------
SELECT 
    'Negative Prices' AS check_name,
    COUNT(*) AS negative_price_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_order_items
WHERE price::numeric < 0;

-- ----------------------------------------------------------------------------
-- CHECK 8: Invalid Payment Values Check
-- Expectation: Payment sums must be greater than or equal to zero.
-- ----------------------------------------------------------------------------
SELECT 
    'Negative or Zero Payments' AS check_name,
    COUNT(*) AS invalid_payment_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_order_payments
WHERE payment_value::numeric <= 0;

-- ----------------------------------------------------------------------------
-- CHECK 9: Revenue Validation (Order Price + Freight vs. Payment Value)
-- Expectation: The sum of product prices + freight must match total payment value.
-- Note: Variance of > $0.05 is flagged to capture data entry errors.
-- ----------------------------------------------------------------------------
WITH ItemTotals AS (
    SELECT order_id, SUM(price::numeric + freight_value::numeric) AS expected_sum
    FROM stg_order_items
    GROUP BY order_id
),
PaymentTotals AS (
    SELECT order_id, SUM(payment_value::numeric) AS actual_sum
    FROM stg_order_payments
    GROUP BY order_id
)
SELECT 
    'Order Value vs. Payment Variance' AS check_name,
    COUNT(*) AS mismatch_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM ItemTotals i
JOIN PaymentTotals p ON i.order_id = p.order_id
WHERE ABS(i.expected_sum - p.actual_sum) > 0.05;

-- ----------------------------------------------------------------------------
-- CHECK 10: Referential Integrity Validation (Order Items vs. Products/Sellers)
-- Expectation: Every line item must point to an existing product and seller.
-- ----------------------------------------------------------------------------
SELECT 
    'Orphaned Product Items' AS check_name,
    COUNT(*) AS orphan_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_order_items oi
LEFT JOIN stg_products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 
    'Orphaned Seller Items' AS check_name,
    COUNT(*) AS orphan_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM stg_order_items oi
LEFT JOIN stg_sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;
