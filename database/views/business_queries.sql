-- ============================================================================
-- Enterprise E-Commerce BI Solution - 30 Advanced Business Queries
-- Target Database: PostgreSQL
-- Purpose: Extract executive insights from the Star Schema warehouse.
-- ============================================================================

-- ============================================================================
-- CATEGORY 1: REVENUE, SALES TRENDS, & GROWTH PERFORMANCE
-- ============================================================================

-- Q1: Monthly Revenue Trend and Month-on-Month (MoM) Growth %
-- ----------------------------------------------------------------------------
WITH MonthlySales AS (
    SELECT
        d.month_start_date AS sales_month,
        SUM(i.price) AS total_revenue
    FROM fact_order_items i
    JOIN dim_date d ON i.purchase_date = d.date_actual
    GROUP BY 1
),
SalesWithLag AS (
    SELECT
        sales_month,
        total_revenue,
        LAG(total_revenue, 1) OVER (ORDER BY sales_month) AS prev_month_revenue
    FROM MonthlySales
)
SELECT
    sales_month,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(prev_month_revenue, 2) AS prev_month_revenue,
    ROUND(
        ((total_revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0)) * 100, 
        2
    ) AS mom_growth_pct
FROM SalesWithLag
ORDER BY sales_month;

/*
  * Business Insight: Revenue displays significant seasonality, with peaks during holiday promotional periods.
  * Business Impact: Sudden drops in MoM growth can signal logistical or customer acquisition bottlenecks.
  * Recommended Action: Allocate ad budget 30 days prior to historical peak months and ramp up warehouse staffing to support demand spikes.
*/


-- Q2: Cumulative (Running Total) Revenue by Year
-- ----------------------------------------------------------------------------
SELECT
    i.purchase_date,
    d.year_actual AS sales_year,
    ROUND(i.price, 2) AS order_item_price,
    ROUND(
        SUM(i.price) OVER (
            PARTITION BY d.year_actual 
            ORDER BY i.purchase_date, i.order_id, i.order_item_id
        ), 
        2
    ) AS running_total_revenue
FROM fact_order_items i
JOIN dim_date d ON i.purchase_date = d.date_actual
ORDER BY i.purchase_date;

/*
  * Business Insight: Visualizes year-to-date (YTD) sales pacing to track target benchmarks.
  * Business Impact: Highlights whether annual sales targets will be achieved early or if promo intervention is required.
  * Recommended Action: Establish trigger alerts in reporting tools when running totals fall 10% below projected paths.
*/


-- Q3: Year-over-Year (YoY) Revenue Growth Comparison
-- ----------------------------------------------------------------------------
WITH MonthlySales AS (
    SELECT
        d.year_actual AS sales_year,
        d.month_actual AS sales_month,
        SUM(i.price) AS total_revenue
    FROM fact_order_items i
    JOIN dim_date d ON i.purchase_date = d.date_actual
    GROUP BY 1, 2
)
SELECT
    c.sales_month,
    c.sales_year AS current_year,
    ROUND(c.total_revenue, 2) AS current_year_revenue,
    p.sales_year AS prior_year,
    ROUND(p.total_revenue, 2) AS prior_year_revenue,
    ROUND(
        ((c.total_revenue - p.total_revenue) / NULLIF(p.total_revenue, 0)) * 100, 
        2
    ) AS yoy_growth_pct
FROM MonthlySales c
JOIN MonthlySales p 
    ON c.sales_month = p.sales_month 
   AND c.sales_year = p.sales_year + 1
ORDER BY c.sales_year, c.sales_month;

/*
  * Business Insight: Discovers whether growth is structural or merely seasonal fluctuations.
  * Business Impact: Identifies long-term stagnation patterns before they affect corporate profitability.
  * Recommended Action: Investigate negative YoY quarters for shifts in customer retention or category-level attrition.
*/


-- Q4: Top 5 Product Categories by Revenue for Each Year-Month
-- ----------------------------------------------------------------------------
WITH RankedCategories AS (
    SELECT
        d.month_start_date AS sales_month,
        p.category,
        SUM(i.price) AS category_revenue,
        DENSE_RANK() OVER (
            PARTITION BY d.month_start_date 
            ORDER BY SUM(i.price) DESC
        ) AS rank_index
    FROM fact_order_items i
    JOIN dim_products p ON i.product_id = p.product_id
    JOIN dim_date d ON i.purchase_date = d.date_actual
    GROUP BY 1, 2
)
SELECT
    sales_month,
    category,
    ROUND(category_revenue, 2) AS category_revenue,
    rank_index
FROM RankedCategories
WHERE rank_index <= 5
ORDER BY sales_month, rank_index;

/*
  * Business Insight: Identifies the core categories driving up to 80% of marketplace revenue.
  * Business Impact: Shift in category ranks can disrupt supplier contracts and storage space optimization.
  * Recommended Action: Align supplier restocking timelines with the monthly ranking trajectory of top-performing categories.
*/


-- Q5: Daily Revenue with a 7-day Moving Average (Rolling Window)
-- ----------------------------------------------------------------------------
WITH DailyRevenue AS (
    SELECT
        purchase_date,
        SUM(price) AS daily_revenue
    FROM fact_order_items
    GROUP BY 1
)
SELECT
    purchase_date,
    ROUND(daily_revenue, 2) AS daily_revenue,
    ROUND(
        AVG(daily_revenue) OVER (
            ORDER BY purchase_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 
        2
    ) AS rolling_7d_avg_revenue
FROM DailyRevenue
ORDER BY purchase_date;

/*
  * Business Insight: Filters out daily variations to identify the baseline revenue direction.
  * Business Impact: Prevents knee-jerk marketing adjustments based on normal daily changes (e.g. low Sunday checkouts).
  * Recommended Action: Use the 7-day rolling average as the primary trend metric on the Executive dashboard.
*/


-- ============================================================================
-- CATEGORY 2: CUSTOMER SEGMENTATION & BEHAVIOR
-- ============================================================================

-- Q6: RFM (Recency, Frequency, Monetary) Customer Segmentation
-- ----------------------------------------------------------------------------
WITH MaxDate AS (
    SELECT MAX(purchase_date) AS max_dataset_date FROM fact_order_items
),
CustomerMetrics AS (
    SELECT
        customer_unique_id,
        MAX(purchase_date) AS last_purchase_date,
        COUNT(DISTINCT order_id) AS purchase_frequency,
        SUM(price) AS total_spend
    FROM fact_order_items
    GROUP BY customer_unique_id
),
RFM_Scores AS (
    SELECT
        m.customer_unique_id,
        m.purchase_frequency,
        m.total_spend,
        EXTRACT(DAY FROM (SELECT max_dataset_date FROM MaxDate) - m.last_purchase_date) AS recency_days,
        NTILE(5) OVER (ORDER BY m.last_purchase_date) AS r_score,
        NTILE(5) OVER (ORDER BY COUNT(DISTINCT order_id)) AS f_score,
        NTILE(5) OVER (ORDER BY SUM(price)) AS m_score
    FROM CustomerMetrics m
    GROUP BY m.customer_unique_id, m.last_purchase_date, m.purchase_frequency, m.total_spend
)
SELECT
    customer_unique_id,
    recency_days,
    purchase_frequency,
    ROUND(total_spend, 2) AS total_spend,
    r_score, f_score, m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk / Can''t Lose Them'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost Customers'
        ELSE 'About to Sleep / New'
    END AS customer_segment
FROM RFM_Scores
ORDER BY total_spend DESC
LIMIT 100;

/*
  * Business Insight: High segment concentrations in 'Lost Customers' suggest retention issues.
  * Business Impact: Retaining existing customers costs 5x less than acquiring new ones.
  * Recommended Action: Deliver customized promo codes to the 'At Risk' segment to re-engage them before churn is finalized.
*/


-- Q7: Customer Cohort Retention Analysis (Monthly Cohorts)
-- ----------------------------------------------------------------------------
WITH CustomerFirstPurchase AS (
    SELECT
        customer_unique_id,
        DATE_TRUNC('month', MIN(purchase_date))::date AS cohort_month
    FROM fact_order_items
    GROUP BY customer_unique_id
),
CustomerActivity AS (
    SELECT DISTINCT
        i.customer_unique_id,
        DATE_TRUNC('month', i.purchase_date)::date AS activity_month
    FROM fact_order_items i
),
CohortSizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM CustomerFirstPurchase
    GROUP BY cohort_month
),
Retention AS (
    SELECT
        f.cohort_month,
        (EXTRACT(YEAR FROM a.activity_month) - EXTRACT(YEAR FROM f.cohort_month)) * 12 +
        (EXTRACT(MONTH FROM a.activity_month) - EXTRACT(MONTH FROM f.cohort_month)) AS period_no,
        COUNT(DISTINCT a.customer_unique_id) AS active_customers
    FROM CustomerFirstPurchase f
    JOIN CustomerActivity a ON f.customer_unique_id = a.customer_unique_id
    GROUP BY 1, 2
)
SELECT
    r.cohort_month,
    s.cohort_size,
    r.period_no,
    r.active_customers,
    ROUND((r.active_customers::numeric / s.cohort_size) * 100, 2) AS retention_pct
FROM Retention r
JOIN CohortSizes s ON r.cohort_month = s.cohort_month
ORDER BY r.cohort_month, r.period_no;

/*
  * Business Insight: Retention curves show typical e-commerce drops after Month 1.
  * Business Impact: Steep drop-offs indicate poor initial onboarding or post-purchase experiences.
  * Recommended Action: Automate a 'feedback loop' email campaign 15 days post-purchase, offering loyalty points.
*/


-- Q8: Repeat Purchase Rate
-- ----------------------------------------------------------------------------
WITH PurchaseCounts AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM fact_order_items
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(
        (SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
        2
    ) AS repeat_purchase_rate_pct
FROM PurchaseCounts;

/*
  * Business Insight: A low repeat purchase rate indicates the business relies heavily on new acquisition.
  * Business Impact: CAC (Customer Acquisition Cost) increases, limiting long-term net margins.
  * Recommended Action: Launch a tier-based VIP program to incentivize repeat purchases.
*/


-- Q9: Average Time (in Days) Between Consecutive Purchases for Customers
-- ----------------------------------------------------------------------------
WITH CustomerPurchaseIntervals AS (
    SELECT
        customer_unique_id,
        order_id,
        purchase_date,
        LAG(purchase_date) OVER (
            PARTITION BY customer_unique_id 
            ORDER BY purchase_date
        ) AS previous_purchase_date
    FROM fact_order_items
    GROUP BY customer_unique_id, order_id, purchase_date
)
SELECT
    ROUND(AVG(purchase_date - previous_purchase_date)::numeric, 1) AS avg_days_between_purchases,
    COUNT(previous_purchase_date) AS total_consecutive_purchases_analyzed
FROM CustomerPurchaseIntervals
WHERE previous_purchase_date IS NOT NULL;

/*
  * Business Insight: Identifies the average time it takes for a customer to return and purchase again.
  * Business Impact: Aligning retargeting campaigns with this window optimizes marketing conversion rates.
  * Recommended Action: Set up email workflows to trigger coupons slightly before the average repurchase window expires.
*/


-- Q10: Top 1% of High-Value Customers and their contribution to total revenue
-- ----------------------------------------------------------------------------
WITH CustomerSpend AS (
    SELECT
        customer_unique_id,
        SUM(price) AS customer_revenue
    FROM fact_order_items
    GROUP BY customer_unique_id
),
RankedSpend AS (
    SELECT
        customer_unique_id,
        customer_revenue,
        PERCENT_RANK() OVER (ORDER BY customer_revenue DESC) AS percentile_rank
    FROM CustomerSpend
)
SELECT
    ROUND(SUM(CASE WHEN percentile_rank <= 0.01 THEN customer_revenue ELSE 0 END), 2) AS top_1_pct_revenue,
    ROUND(SUM(customer_revenue), 2) AS global_total_revenue,
    ROUND(
        (SUM(CASE WHEN percentile_rank <= 0.01 THEN customer_revenue ELSE 0 END) / SUM(customer_revenue)) * 100, 
        2
    ) AS contribution_pct_of_top_1_pct
FROM RankedSpend;

/*
  * Business Insight: High revenue concentration in the top 1% indicates reliance on key customer segments.
  * Business Impact: Losing these high-value customers represents a major revenue risk.
  * Recommended Action: Assign dedicated customer support agents to these accounts and offer exclusive access to new product drops.
*/


-- ============================================================================
-- CATEGORY 3: LOGISTICS, DELIVERIES, & SHIPPING PERFORMANCE
-- ============================================================================

-- Q11: Average Delivery Time (Actual vs. Estimated) by Customer State
-- ----------------------------------------------------------------------------
SELECT
    c.customer_state,
    ROUND(AVG(o.delivery_lead_time_days)::numeric, 1) AS avg_actual_delivery_days,
    ROUND(
        AVG(DATE_PART('day', o.estimated_timestamp - o.purchase_timestamp))::numeric, 
        1
    ) AS avg_estimated_delivery_days,
    ROUND(AVG(o.delivery_delay_days)::numeric, 1) AS avg_delivery_variance_days
FROM dim_orders o
JOIN dim_customers c ON o.customer_unique_id = c.customer_unique_id
WHERE o.delivered_timestamp IS NOT NULL
GROUP BY 1
ORDER BY avg_delivery_variance_days DESC;

/*
  * Business Insight: Highlights regions experiencing transit delays.
  * Business Impact: Delivery delays drive negative reviews and increase refund claims.
  * Recommended Action: Partner with regional carrier networks in underperforming states to shorten shipping intervals.
*/


-- Q12: Late Delivery Rate Trend by Month
-- ----------------------------------------------------------------------------
SELECT
    d.month_start_date AS order_month,
    COUNT(o.order_id) AS total_delivered_orders,
    SUM(o.is_late) AS total_late_orders,
    ROUND((SUM(o.is_late)::numeric / COUNT(o.order_id)) * 100, 2) AS late_delivery_rate_pct
FROM dim_orders o
JOIN dim_date d ON o.purchase_date = d.date_actual
WHERE o.order_status = 'delivered' AND o.delivered_date IS NOT NULL
GROUP BY 1
ORDER BY order_month;

/*
  * Business Insight: Detects seasonal performance dips during holiday shopping periods.
  * Business Impact: Delivery failures during peak periods damage holiday sales opportunities.
  * Recommended Action: Adjust the shipping estimate formula to set expectations for peak months.
*/


-- Q13: Carrier Shipping Efficiency (Order Approval to Carrier Handover)
-- ----------------------------------------------------------------------------
SELECT
    d.month_start_date AS order_month,
    ROUND(AVG(EXTRACT(EPOCH FROM (o.carrier_timestamp - o.approved_timestamp)) / 3600)::numeric, 1) AS avg_hours_to_carrier
FROM dim_orders o
JOIN dim_date d ON o.purchase_date = d.date_actual
WHERE o.approved_timestamp IS NOT NULL AND o.carrier_timestamp IS NOT NULL
GROUP BY 1
ORDER BY order_month;

/*
  * Business Insight: Measures warehouse processing speed before package is picked up by carrier.
  * Business Impact: Slow handoffs delay final delivery times, even if courier transit is fast.
  * Recommended Action: Streamline pick-and-pack workflows and coordinate scheduled daily carrier pickups.
*/


-- Q14: Correlation Between Shipping Delay and Customer Review Score
-- ----------------------------------------------------------------------------
SELECT
    CASE
        WHEN o.delivery_delay_days IS NULL THEN 'Not Delivered'
        WHEN o.delivery_delay_days <= -5 THEN 'Very Early (>5 days early)'
        WHEN o.delivery_delay_days < 0 THEN 'Early / On-time (0-4 days early)'
        WHEN o.delivery_delay_days = 0 THEN 'Exactly On-Time'
        WHEN o.delivery_delay_days <= 3 THEN 'Slightly Late (1-3 days)'
        WHEN o.delivery_delay_days <= 7 THEN 'Moderately Late (4-7 days)'
        ELSE 'Severely Late (>7 days)'
    END AS delivery_performance,
    COUNT(DISTINCT r.order_id) AS total_reviews,
    ROUND(AVG(r.review_score), 2) AS average_review_score
FROM dim_orders o
JOIN fact_order_reviews r ON o.order_id = r.order_id
GROUP BY 1
ORDER BY MIN(o.delivery_delay_days) NULLS LAST;

/*
  * Business Insight: Quantifies the impact of delivery delays on customer reviews.
  * Business Impact: Late deliveries lead to 1-star reviews, dragging down overall product rankings.
  * Recommended Action: Issue proactive apology discount coupons immediately to customers experiencing delays over 3 days.
*/


-- Q15: Shipping Cost (Freight) as a % of Order Price by State
-- ----------------------------------------------------------------------------
SELECT
    c.customer_state,
    ROUND(SUM(i.price), 2) AS total_items_revenue,
    ROUND(SUM(i.freight_value), 2) AS total_freight_paid,
    ROUND((SUM(i.freight_value) / SUM(i.price)) * 100, 2) AS freight_cost_ratio_pct
FROM fact_order_items i
JOIN dim_customers c ON i.customer_unique_id = c.customer_unique_id
GROUP BY 1
ORDER BY freight_cost_ratio_pct DESC;

/*
  * Business Insight: Highlights states where shipping costs impact margins.
  * Business Impact: High freight rates reduce checkout conversions in remote areas.
  * Recommended Action: Establish regional fulfillment centers in high-ratio states to decrease local shipping distances.
*/


-- ============================================================================
-- CATEGORY 4: PRODUCT & SELLER ANALYTICS
-- ============================================================================

-- Q16: Most Returned/Canceled Product Categories
-- ----------------------------------------------------------------------------
SELECT
    p.category,
    COUNT(DISTINCT o.order_id) AS total_ordered_items,
    SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END) AS total_canceled_orders,
    ROUND(
        (SUM(CASE WHEN o.order_status = 'canceled' THEN 1 ELSE 0 END)::numeric / COUNT(DISTINCT o.order_id)) * 100, 
        2
    ) AS cancellation_rate_pct
FROM fact_order_items i
JOIN dim_orders o ON i.order_id = o.order_id
JOIN dim_products p ON i.product_id = p.product_id
GROUP BY 1
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY cancellation_rate_pct DESC;

/*
  * Business Insight: High cancellation rates point to quality issues or misleading category descriptions.
  * Business Impact: Processing cancellations increases customer service costs and impacts store margins.
  * Recommended Action: Audit the product listings and sizes for categories with cancellation rates over 5%.
*/


-- Q17: Seller Concentration: Top 5% Sellers Contribution to Total Revenue
-- ----------------------------------------------------------------------------
WITH SellerRevenue AS (
    SELECT
        seller_id,
        SUM(price) AS seller_sales
    FROM fact_order_items
    GROUP BY seller_id
),
RankedSellers AS (
    SELECT
        seller_id,
        seller_sales,
        PERCENT_RANK() OVER (ORDER BY seller_sales DESC) AS percentile_rank
    FROM SellerRevenue
)
SELECT
    COUNT(seller_id) AS total_active_sellers,
    ROUND(SUM(CASE WHEN percentile_rank <= 0.05 THEN seller_sales ELSE 0 END), 2) AS top_5_pct_sellers_revenue,
    ROUND(SUM(seller_sales), 2) AS total_marketplace_revenue,
    ROUND(
        (SUM(CASE WHEN percentile_rank <= 0.05 THEN seller_sales ELSE 0 END) / SUM(seller_sales)) * 100, 
        2
    ) AS seller_concentration_pct
FROM RankedSellers;

/*
  * Business Insight: High concentration highlights reliance on a few key sellers.
  * Business Impact: If top sellers leave, platform GMV will experience a direct drop.
  * Recommended Action: Diversify vendor options and implement incentives to help mid-tier sellers grow.
*/


-- Q18: Product Category Affinity (Basket Analysis)
-- ----------------------------------------------------------------------------
SELECT
    p1.category AS product_category_a,
    p2.category AS product_category_b,
    COUNT(DISTINCT i1.order_id) AS co_purchase_count
FROM fact_order_items i1
JOIN fact_order_items i2 
    ON i1.order_id = i2.order_id 
   AND i1.product_id < i2.product_id 
JOIN dim_products p1 ON i1.product_id = p1.product_id
JOIN dim_products p2 ON i2.product_id = p2.product_id
WHERE p1.category <> p2.category 
GROUP BY 1, 2
ORDER BY co_purchase_count DESC
LIMIT 50;

/*
  * Business Insight: Identifies categories that are frequently bought together in a single checkout.
  * Business Impact: Informs bundling promos, cross-sell engines, and warehouse layout planning.
  * Recommended Action: Create bundled discount promotions for affinity categories to increase AOV.
*/


-- Q19: Product Volume/Weight vs. Average Freight Cost
-- ----------------------------------------------------------------------------
SELECT
    CASE
        WHEN volume_cm3 <= 5000 THEN 'Small (0-5L)'
        WHEN volume_cm3 <= 20000 THEN 'Medium (5-20L)'
        WHEN volume_cm3 <= 50000 THEN 'Large (20-50L)'
        ELSE 'Extra Large (>50L)'
    END AS volume_tier,
    ROUND(AVG(weight_g)::numeric, 0) AS average_weight_grams,
    ROUND(AVG(freight_value), 2) AS average_freight_paid,
    COUNT(*) AS total_items_evaluated
FROM fact_order_items i
JOIN dim_products p ON i.product_id = p.product_id
GROUP BY 1
ORDER BY average_freight_paid;

/*
  * Business Insight: Highlights freight rate progression based on product size and weight.
  * Business Impact: Inefficient freight pricing structure for bulky items can impact overall shipping margins.
  * Recommended Action: Optimize spatial pricing scales and renegotiate heavy-bulk cargo carrier rates.
*/


-- Q20: Cold Products: Active products with zero sales in the last 90 days
-- ----------------------------------------------------------------------------
WITH ProductLastSale AS (
    SELECT
        product_id,
        MAX(purchase_date) AS last_purchase_date
    FROM fact_order_items
    GROUP BY product_id
),
MaxDate AS (
    SELECT MAX(purchase_date) AS max_dataset_date FROM fact_order_items
)
SELECT
    p.product_id,
    p.category,
    s.last_purchase_date,
    EXTRACT(DAY FROM (SELECT max_dataset_date FROM MaxDate) - s.last_purchase_date) AS days_inactive
FROM dim_products p
JOIN ProductLastSale s ON p.product_id = s.product_id
WHERE s.last_purchase_date < (SELECT max_dataset_date FROM MaxDate) - INTERVAL '90 days'
ORDER BY days_inactive DESC
LIMIT 100;

/*
  * Business Insight: Identifies underperforming products taking up space in catalog views.
  * Business Impact: Slow-moving items impact warehousing efficiency and resource utilization.
  * Recommended Action: Apply markdowns or bundle promotions to clear out cold inventory.
*/


-- ============================================================================
-- CATEGORY 5: PAYMENTS & RISK ANALYSIS
-- ============================================================================

-- Q21: Payment Method Preferences by Order Value Bucket
-- ----------------------------------------------------------------------------
SELECT
    CASE
        WHEN payment_value <= 50 THEN 'Low Ticket (0-50)'
        WHEN payment_value <= 200 THEN 'Mid Ticket (51-200)'
        ELSE 'High Ticket (>200)'
    END AS order_value_tier,
    payment_type,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(payment_installments)::numeric, 1) AS avg_payment_installments,
    ROUND(SUM(payment_value), 2) AS total_payment_volume
FROM fact_order_payments
GROUP BY 1, 2
ORDER BY 1, total_payment_volume DESC;

/*
  * Business Insight: Highlights customer payment preferences based on cart value.
  * Business Impact: Credit card transaction fees can impact margins on high-ticket orders.
  * Recommended Action: Promote instant transfer options (e.g. PIX/Boleto) for high-ticket tiers with cashback incentives.
*/


-- Q22: Risk Analysis: Orders with split payment types or high installments
-- ----------------------------------------------------------------------------
SELECT
    order_id,
    COUNT(DISTINCT payment_type) AS distinct_payment_methods,
    MAX(payment_installments) AS max_installments,
    ROUND(SUM(payment_value), 2) AS total_order_payment
FROM fact_order_payments
GROUP BY order_id
HAVING COUNT(DISTINCT payment_type) > 1 OR MAX(payment_installments) >= 12
ORDER BY distinct_payment_methods DESC, total_order_payment DESC
LIMIT 100;

/*
  * Business Insight: Tracks usage patterns of customers relying on multi-card or long-term financing options.
  * Business Impact: Higher installment terms delay net cash collections.
  * Recommended Action: Set limit caps on credit installment lengths to mitigate risk.
*/


-- Q23: Impact of Payment Installment options on Average Order Value (AOV)
-- ----------------------------------------------------------------------------
SELECT
    CASE 
        WHEN payment_installments = 1 THEN '1 Installment'
        WHEN payment_installments <= 3 THEN '2-3 Installments'
        WHEN payment_installments <= 6 THEN '4-6 Installments'
        WHEN payment_installments <= 10 THEN '7-10 Installments'
        ELSE '11+ Installments'
    END AS installment_bracket,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(AVG(payment_value), 2) AS average_order_value_aov,
    ROUND(SUM(payment_value), 2) AS total_payment_revenue
FROM fact_order_payments
GROUP BY 1
ORDER BY installment_bracket;

/*
  * Business Insight: Long installment terms correlate with higher average transaction size.
  * Business Impact: Restricting financing options could lead to drops in average order values.
  * Recommended Action: Run promotions on installment payment options for orders exceeding premium thresholds.
*/


-- Q24: Multi-Payment Breakdown: Split Transaction Analysis
-- ----------------------------------------------------------------------------
WITH MultiPayOrders AS (
    SELECT
        order_id,
        STRING_AGG(DISTINCT payment_type, ' + ' ORDER BY payment_type) AS split_combination,
        COUNT(payment_sequential) AS transaction_count,
        SUM(payment_value) AS total_value
    FROM fact_order_payments
    GROUP BY order_id
    HAVING COUNT(payment_sequential) > 1
)
SELECT
    split_combination,
    COUNT(order_id) AS number_of_orders,
    ROUND(AVG(total_value), 2) AS average_order_value,
    ROUND(SUM(total_value), 2) AS total_payments
FROM MultiPayOrders
GROUP BY split_combination
ORDER BY number_of_orders DESC;

/*
  * Business Insight: Highlights trends in how customers combine payment methods (e.g. credit cards + vouchers).
  * Business Impact: Clear visibility helps payment gateways process split transactions efficiently.
  * Recommended Action: Improve checkout payment flow to make split credit/voucher payments intuitive.
*/


-- ============================================================================
-- CATEGORY 6: REVIEWS, SENTIMENT, & CUSTOMER SATISFACTION
-- ============================================================================

-- Q25: Average Review Score Trend & Correlation with Delivery Lead Time
-- ----------------------------------------------------------------------------
SELECT
    o.delivery_lead_time_days,
    COUNT(DISTINCT r.order_id) AS review_count,
    ROUND(AVG(r.review_score), 2) AS average_review_score
FROM dim_orders o
JOIN fact_order_reviews r ON o.order_id = r.order_id
WHERE o.delivery_lead_time_days IS NOT NULL 
  AND o.delivery_lead_time_days BETWEEN 0 AND 30 
GROUP BY 1
ORDER BY o.delivery_lead_time_days;

/*
  * Business Insight: Direct correlation between delivery lead time and rating drops.
  * Business Impact: Deliveries taking over 10 days experience a sharp drop in average rating.
  * Recommended Action: Target logistics performance to keep transit lead times under 7 days to maintain high ratings.
*/


-- Q26: Identifying critical products: Low review score (< 2) but high sales volume
-- ----------------------------------------------------------------------------
WITH ProductAggregates AS (
    SELECT
        i.product_id,
        COUNT(DISTINCT i.order_id) AS total_units_sold,
        AVG(r.review_score) AS average_review_score
    FROM fact_order_items i
    LEFT JOIN fact_order_reviews r ON i.order_id = r.order_id
    GROUP BY i.product_id
)
SELECT
    a.product_id,
    p.category,
    a.total_units_sold,
    ROUND(a.average_review_score, 2) AS average_review_score
FROM ProductAggregates a
JOIN dim_products p ON a.product_id = p.product_id
WHERE a.total_units_sold >= 20 
  AND a.average_review_score <= 2.5
ORDER BY a.total_units_sold DESC, a.average_review_score ASC;

/*
  * Business Insight: Identifies high-selling items with quality concerns.
  * Business Impact: High-volume bad items damage customer trust and increase returns.
  * Recommended Action: Temporarily pause listings of flagged products and request quality audits from suppliers.
*/


-- Q27: Response Time Analysis: Average time to answer reviews
-- ----------------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', review_creation_date)::date AS review_month,
    ROUND(AVG(EXTRACT(EPOCH FROM (review_answer_timestamp - review_creation_date)) / 3600)::numeric, 1) AS avg_hours_to_respond,
    COUNT(*) AS total_reviews_responded
FROM fact_order_reviews
WHERE review_answer_timestamp IS NOT NULL
GROUP BY 1
ORDER BY review_month;

/*
  * Business Insight: Measures customer service speed in responding to reviews.
  * Business Impact: Long response times to negative reviews can lead to customer churn.
  * Recommended Action: Set SLA targets for customer service agents to reply to 1-3 star reviews within 24 hours.
*/


-- Q28: Review text length correlation with review score
-- ----------------------------------------------------------------------------
SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(AVG(LENGTH(review_comment_message))::numeric, 1) AS avg_comment_length_chars,
    SUM(CASE WHEN review_comment_message IS NOT NULL THEN 1 ELSE 0 END) AS reviews_with_text
FROM stg_order_reviews
GROUP BY review_score
ORDER BY review_score;

/*
  * Business Insight: Shows that negative reviews tend to write longer comments.
  * Business Impact: Detailed complaints capture the specific pain points of dissatisfied customers.
  * Recommended Action: Run text analytics and keyword mining on reviews over 150 characters to identify quality issues.
*/


-- ============================================================================
-- CATEGORY 7: ADVANCED ANALYTICAL WINDOWS & RECURSIVE PATTERNS
-- ============================================================================

-- Q29: First and Last Purchased product category for every customer
-- ----------------------------------------------------------------------------
WITH CustomerOrderedPurchases AS (
    SELECT
        i.customer_unique_id,
        p.category,
        i.purchase_date,
        ROW_NUMBER() OVER (
            PARTITION BY i.customer_unique_id 
            ORDER BY i.purchase_date ASC, i.order_id, i.order_item_id
        ) AS purchase_asc_index,
        ROW_NUMBER() OVER (
            PARTITION BY i.customer_unique_id 
            ORDER BY i.purchase_date DESC, i.order_id, i.order_item_id
        ) AS purchase_desc_index
    FROM fact_order_items i
    JOIN dim_products p ON i.product_id = p.product_id
)
SELECT
    f.customer_unique_id,
    f.category AS first_purchased_category,
    f.purchase_date AS first_purchase_date,
    l.category AS last_purchased_category,
    l.purchase_date AS last_purchase_date
FROM CustomerOrderedPurchases f
JOIN CustomerOrderedPurchases l 
    ON f.customer_unique_id = l.customer_unique_id
WHERE f.purchase_asc_index = 1 
  AND l.purchase_desc_index = 1
ORDER BY f.purchase_date DESC
LIMIT 100;

/*
  * Business Insight: Maps customer product category journey over time.
  * Business Impact: Informs marketing campaigns on the typical progression paths of repeat buyers.
  * Recommended Action: Customize email recommendations based on the customer's first purchase history.
*/


-- Q30: Recursive CTE: Customer Buying Path Sequence (Simulating Multi-touch purchasing flow)
-- ----------------------------------------------------------------------------
WITH RECURSIVE CustomerPath AS (
    SELECT
        customer_unique_id,
        purchase_date,
        order_id,
        category::text AS purchase_sequence,
        1 AS step_count
    FROM (
        SELECT
            i.customer_unique_id,
            i.purchase_date,
            i.order_id,
            p.category,
            ROW_NUMBER() OVER (PARTITION BY i.customer_unique_id ORDER BY i.purchase_date, i.order_id) AS seq_num
        FROM fact_order_items i
        JOIN dim_products p ON i.product_id = p.product_id
    ) t
    WHERE seq_num = 1

    UNION ALL

    SELECT
        curr.customer_unique_id,
        curr.purchase_date,
        curr.order_id,
        (prev.purchase_sequence || ' -> ' || curr.category)::text AS purchase_sequence,
        prev.step_count + 1
    FROM (
        SELECT
            i.customer_unique_id,
            i.purchase_date,
            i.order_id,
            p.category,
            ROW_NUMBER() OVER (PARTITION BY i.customer_unique_id ORDER BY i.purchase_date, i.order_id) AS seq_num
        FROM fact_order_items i
        JOIN dim_products p ON i.product_id = p.product_id
    ) curr
    JOIN CustomerPath prev 
      ON curr.customer_unique_id = prev.customer_unique_id
     AND curr.seq_num = prev.step_count + 1
     AND prev.step_count < 4 
)
SELECT
    purchase_sequence,
    COUNT(DISTINCT customer_unique_id) AS customer_count,
    ROUND(AVG(step_count)::numeric, 1) AS average_steps
FROM CustomerPath
WHERE step_count > 1 
GROUP BY purchase_sequence
ORDER BY customer_count DESC
LIMIT 50;

/*
  * Business Insight: Identifies the most common repeat purchase combinations and sequences.
  * Business Impact: Helps optimize automated product catalog and category recommendation engines.
  * Recommended Action: Deliver category-specific promotions to guide customers along the most common purchase paths.
*/
