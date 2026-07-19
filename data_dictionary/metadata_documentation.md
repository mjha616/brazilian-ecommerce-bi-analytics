# Data Warehouse Metadata & Lineage Documentation

This document contains metadata profiles for all tables and views deployed in the Star Schema data warehouse layer.

---

## 1. Dimensional Warehouse Tables

### 1.1 `dim_date`
*   **Source:** System-generated calendar rows via SQL load.
*   **Owner:** Data Engineering Core Team.
*   **Refresh Frequency:** Static (pre-calculated from 2016-01-01 to 2020-12-31).
*   **Grain:** 1 row per calendar date.
*   **Primary Key:** `date_actual` (Date).
*   **Description:** Complete dimension table supporting time-intelligence, calendar splits, and corporate fiscal definitions.
*   **Purpose:** Act as the single source of calendar filters for all transactional facts.

### 1.2 `dim_customers`
*   **Source:** CRM registration logs.
*   **Owner:** Customer Analytics Unit.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per unique customer identity (`customer_unique_id`).
*   **Primary Key:** `customer_unique_id` (CHAR(32)).
*   **Description:** Master customer table. Capitallizes locations and groups zip codes.
*   **Purpose:** Filter and slice sales metrics by customer regional attributes.

### 1.3 `dim_products`
*   **Source:** Catalog database management system.
*   **Owner:** Merchant & Catalog Merchandising Team.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per catalog product (`product_id`).
*   **Primary Key:** `product_id` (CHAR(32)).
*   **Description:** Product dimension containing weights, measurements, volume calculations, and English translation categories.
*   **Purpose:** Categorize order metrics and optimize spatial shipping pricing.

### 1.4 `dim_sellers`
*   **Source:** Partner onboarding registry.
*   **Owner:** Marketplace Merchant Relations.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per registered merchant (`seller_id`).
*   **Primary Key:** `seller_id` (CHAR(32)).
*   **Description:** Merchant master record including location data.
*   **Purpose:** Support seller concentration audits and logistics carrier analysis.

### 1.5 `dim_orders`
*   **Source:** OMS (Order Management System) transaction states.
*   **Owner:** Order Fulfillment Operations.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per transactional checkout cart (`order_id`).
*   **Primary Key:** `order_id` (CHAR(32)).
*   **Description:** Tracks order statuses, timestamps (purchase, carrier handover, final arrival), and pre-computed transit times.
*   **Purpose:** Analyze logistics SLAs and serve as a link table connecting sales, payment, and review facts.

---

## 2. Fact Tables

### 2.1 `fact_order_items`
*   **Source:** OMS line-item tables.
*   **Owner:** Sales Reporting & Core Analytics.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per order item line (`order_id` + `order_item_id`).
*   **Primary Key:** Composite: `(order_id, order_item_id)`.
*   **Description:** Central sales ledger storing item selling price, freight fees, and computed gross merchandise value (GMV).
*   **Purpose:** Core reporting fact table for revenue, profit margins, and sales volumes.

### 2.2 `fact_order_payments`
*   **Source:** Payment Gateway logs.
*   **Owner:** Financial Accounting & Payment Gateway Operations.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per card/boleto payment sequence transaction (`order_id` + `payment_sequential`).
*   **Primary Key:** Composite: `(order_id, payment_sequential)`.
*   **Description:** Records payment types, installment selections, and payment value.
*   **Purpose:** Monitor payment cash flows, installment terms, and transaction costs.

### 2.3 `fact_order_reviews`
*   **Source:** Customer Satisfaction Survey engine.
*   **Owner:** Customer Relations.
*   **Refresh Frequency:** Daily Incremental.
*   **Grain:** 1 row per customer feedback submission (`review_id` + `order_id`).
*   **Primary Key:** Composite: `(review_id, order_id)`.
*   **Description:** Records score ratings and dates.
*   **Purpose:** Measure customer satisfaction rates and analyze logistics SLA performance.

---

## 3. Reporting Database Views

### 3.1 `vw_sales_summary`
*   **Grain:** Daily level grouped by product category and states.
*   **Purpose:** Speed up trend reports and reduce Power BI gateway load.

### 3.2 `vw_customer_metrics`
*   **Grain:** Customer level showing metrics such as lifetime orders, total spend, AOV, and lifecycle duration.
*   **Purpose:** Support RFM calculations and cohort modeling.

### 3.3 `vw_product_metrics`
*   **Grain:** Product level showing orders, revenue, average rating, and cancellations.
*   **Purpose:** Identify top categories and underperforming listings.

### 3.4 `vw_delivery_metrics`
*   **Grain:** Purchase date level grouped by customer state.
*   **Purpose:** Provide logistics dashboards with actual transit times, delays, and late delivery rates.
