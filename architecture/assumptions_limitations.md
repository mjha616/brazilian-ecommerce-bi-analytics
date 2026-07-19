# Data Assumptions & Analytical Limitations

This document lists assumptions and limitations identified within the Olist E-commerce dataset, explaining how they affect business decisions and dashboard reporting.

---

## 1. Inventory Snapshots
*   **Limitation:** The dataset does not contain inventory levels, supplier lead times, or product availability logs.
*   **Business Impact:** Without warehouse inventory data, we cannot calculate critical metrics like **Stock Turn Rate**, **Days of Inventory Outstanding (DIO)**, or forecast product out-of-stock events.
*   **Action Taken:** We focused our product analysis on sales volume and order cancellation rates to identify category popularity.

---

## 2. Marketing Attribution & Acquisition Cost
*   **Limitation:** There is no marketing data available, such as search campaign costs, conversion paths, or ad impressions.
*   **Business Impact:** We cannot calculate **Customer Acquisition Cost (CAC)** or **Return on Ad Spend (ROAS)**.
*   **Action Taken:** We used customer purchase frequency to model customer lifetime value (LTV) and RFM segments as indicators of retention.

---

## 3. Financial Metrics (Profitability)
*   **Limitation:** The dataset only contains the customer purchase price, excluding cost of goods sold (COGS), warehouse overhead, and staff salaries.
*   **Business Impact:** We cannot calculate net margins or EBITDA.
*   **Action Taken:** We used Gross Merchandise Value (GMV) and price revenue as top-line sales metrics, treating freight fees as logistics pass-through costs.

---

## 4. Return Logs
*   **Limitation:** The dataset contains order cancellation flags in `order_status` but lacks a returns logging system to track refunds or items sent back post-delivery.
*   **Business Impact:** This limitation prevents analyzing customer return rates or product quality issues after delivery.
*   **Action Taken:** We treated cancellations as the primary metric for returns, correlating reviews scoring under 3 stars with delivery lead times.

---

## 5. Currency Stability
*   **Limitation:** Sales values are in Brazilian Real (BRL) but lack exchange rate tables to support multi-currency comparisons over time.
*   **Business Impact:** Does not reflect the impact of currency fluctuations on business performance.
*   **Action Taken:** All revenue calculations are reported in a single, constant currency.
