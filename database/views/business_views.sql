-- ============================================================================
-- Enterprise E-Commerce BI Solution - Business Metrics Views
-- Target Database: PostgreSQL
-- Purpose: Pre-calculated analytical views serving as a reusable metric layer.
--
-- Why push business logic into database views instead of repeating it in BI tools?
-- 1. Single Source of Truth: Centralizing metrics (like AOV and Late Delivery Rates) 
--    guarantees that separate departments (Sales, Finance, Logistics) see 
--    consistent figures, regardless of the BI tool they connect with.
-- 2. Code Reusability: PBI dashboards, Tableau worksheets, and Python analytics 
--    can all query the same views, avoiding redundant metric re-engineering.
-- 3. Tool Independence: Business rules are kept in database DDL, allowing 
--    migrations (e.g. from Power BI to Looker) without rewriting calculations.
-- 4. Gateway Optimization: Shifting complex aggregations and joins to the 
--    database engine reduces Power BI memory and gateway CPU load.
-- ============================================================================

-- 1. Sales Summary View
-- Purpose: Provide daily aggregated financial metrics for trends.
CREATE OR REPLACE VIEW vw_sales_summary AS
SELECT
    i.purchase_date,
    d.year_actual AS sales_year,
    d.month_actual AS sales_month,
    d.month_name_short AS sales_month_name,
    p.category AS product_category,
    c.customer_state,
    s.seller_state,
    COUNT(DISTINCT i.order_id) AS total_orders,
    COUNT(i.order_item_id) AS total_items_sold,
    SUM(i.price) AS item_revenue,
    SUM(i.freight_value) AS freight_revenue,
    SUM(i.gross_merchandise_value) AS gross_merchandise_value_gmv,
    ROUND(SUM(i.price) / COUNT(DISTINCT i.order_id), 2) AS average_order_value_aov
FROM fact_order_items i
JOIN dim_date d ON i.purchase_date = d.date_actual
JOIN dim_products p ON i.product_id = p.product_id
JOIN dim_customers c ON i.customer_unique_id = c.customer_unique_id
JOIN dim_sellers s ON i.seller_id = s.seller_id
GROUP BY 1, 2, 3, 4, 5, 6, 7;


-- 2. Customer Lifecycle Metrics View
-- Purpose: Pre-calculate lifecycle milestones for cohort and retention analysis.
CREATE OR REPLACE VIEW vw_customer_metrics AS
SELECT
    i.customer_unique_id,
    c.customer_city,
    c.customer_state,
    MIN(i.purchase_date) AS first_purchase_date,
    MAX(i.purchase_date) AS last_purchase_date,
    COUNT(DISTINCT i.order_id) AS lifetime_orders,
    COUNT(i.order_item_id) AS lifetime_items,
    SUM(i.price) AS lifetime_revenue,
    SUM(i.freight_value) AS lifetime_freight,
    SUM(i.gross_merchandise_value) AS lifetime_gmv,
    ROUND(SUM(i.price) / COUNT(DISTINCT i.order_id), 2) AS customer_aov,
    (MAX(i.purchase_date) - MIN(i.purchase_date)) AS lifecycle_duration_days
FROM fact_order_items i
JOIN dim_customers c ON i.customer_unique_id = c.customer_unique_id
GROUP BY 1, 2, 3;


-- 3. Product Catalog Performance View
-- Purpose: Analyze sales velocity, returns, and reviews at the category level.
CREATE OR REPLACE VIEW vw_product_metrics AS
SELECT
    p.product_id,
    p.category AS product_category,
    p.volume_cm3,
    p.weight_g,
    COUNT(DISTINCT i.order_id) AS items_ordered,
    SUM(i.price) AS total_revenue,
    SUM(i.freight_value) AS total_freight,
    ROUND(AVG(i.price), 2) AS average_selling_price_asp,
    ROUND(AVG(r.review_score), 2) AS average_review_score,
    COUNT(DISTINCT r.review_id) AS review_count,
    SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) AS order_cancellations,
    ROUND(
        (SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END)::numeric / NULLIF(COUNT(DISTINCT o.order_id), 0)) * 100, 
        2
    ) AS cancellation_rate_pct
FROM dim_products p
LEFT JOIN fact_order_items i ON p.product_id = i.product_id
LEFT JOIN dim_orders o ON i.order_id = o.order_id
LEFT JOIN fact_order_reviews r ON i.order_id = r.order_id
GROUP BY 1, 2, 3, 4;


-- 4. Delivery & Logistics Metrics View
-- Purpose: Serve logistics performance indicators to carriers.
CREATE OR REPLACE VIEW vw_delivery_metrics AS
SELECT
    o.purchase_date,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders_shipped,
    SUM(CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END) AS total_orders_delivered,
    SUM(o.is_late) AS late_orders,
    ROUND(
        (SUM(o.is_late)::numeric / NULLIF(SUM(CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END), 0)) * 100, 
        2
    ) AS late_delivery_rate_pct,
    ROUND(AVG(o.delivery_lead_time_days)::numeric, 1) AS average_transit_days,
    ROUND(AVG(o.delivery_delay_days)::numeric, 1) AS average_delay_variance_days
FROM dim_orders o
JOIN dim_customers c ON o.customer_unique_id = c.customer_unique_id
GROUP BY 1, 2;
