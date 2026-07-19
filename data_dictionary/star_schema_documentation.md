# Star Schema Data Model & SCD Specifications

This document outlines the dimensional structure of the Data Warehouse, defining relationships and discussing Slowly Changing Dimension (SCD) strategies to support accurate historical reporting.

---

## 1. Schema Relational Design

The warehouse is designed as a **Star Schema** to isolate independent transactions and optimize analytical queries:

*   **Shared Dimensions:** `dim_date`, `dim_customers`, `dim_products`, `dim_sellers`, and `dim_orders`.
*   **Facts:** `fact_order_items` (sales grain), `fact_order_payments` (payment grain), and `fact_order_reviews` (satisfaction grain).

### Diagram of Model Relationships
*   `dim_date[date_actual]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_items[purchase_date]`
*   `dim_date[date_actual]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_payments[purchase_date]`
*   `dim_date[date_actual]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_reviews[purchase_date]`
*   `dim_customers[customer_unique_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_items[customer_unique_id]`
*   `dim_customers[customer_unique_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_payments[customer_unique_id]`
*   `dim_customers[customer_unique_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_reviews[customer_unique_id]`
*   `dim_products[product_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_items[product_id]`
*   `dim_sellers[seller_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_items[seller_id]`
*   `dim_orders[order_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_items[order_id]`
*   `dim_orders[order_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_payments[order_id]`
*   `dim_orders[order_id]` $\rightarrow$ `1:N` $\rightarrow$ `fact_order_reviews[order_id]`

---

## 2. Slowly Changing Dimensions (SCD) Specification

In transactional databases, dimension attributes change over time (e.g., a customer moves to another city, a seller shifts their warehouse, or a product changes its category listing). In enterprise warehouses, we manage these changes using **SCD patterns**.

### SCD Type 1 (Overwrite)
*   **Behavior:** Directly updates the existing row with the new value, overwriting historical data.
*   **Implications:** No historical record is kept. If a customer moves from SP (São Paulo) to RJ (Rio de Janeiro), all their past sales are retroactively attributed to RJ.
*   **Use Case:** Correcting minor spelling mistakes in product descriptions or city names.

### SCD Type 2 (Add New Row - Historical Tracking)
*   **Behavior:** Creates a new row with a unique surrogate key, keeping the original row unchanged.
*   **Structure:** Add audit columns to the dimension table:
    *   `row_key` (SERIAL / INT - Surrogate primary key)
    *   `valid_from` (DATE / TIMESTAMP - Start date of the record version)
    *   `valid_to` (DATE / TIMESTAMP - End date of the record version, defaults to `9999-12-31` for current)
    *   `is_current` (BOOLEAN - 1 if current, 0 if historical)
*   **Implications:** Preserves the history of dimension attributes.
*   **Use Case:** Tracking customer address changes to ensure past sales are correctly attributed to the state where the customer lived at the time of purchase.

---

## 3. Implementation Blueprint: SCD Type 2 Customer Dimension

If SCD Type 2 were implemented for `dim_customers` in this warehouse, the schema and loading steps would be modified as follows:

### Step 1: Modify Table DDL
```sql
CREATE TABLE dim_customers_scd2 (
    customer_row_key SERIAL PRIMARY KEY, -- Surrogate Key
    customer_unique_id CHAR(32) NOT NULL, -- Natural Key
    customer_zip_code_prefix VARCHAR(10) NOT NULL,
    customer_city VARCHAR(100) NOT NULL,
    customer_state CHAR(2) NOT NULL,
    valid_from TIMESTAMP NOT NULL,
    valid_to TIMESTAMP NOT NULL,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
);
```

### Step 2: Modify ETL Loading Logic (Incremental SCD Load)
When loading customers from staging:
1.  **Expire Old Records:** If a customer's location has changed (the staging record has a different state/city than the current warehouse record), update the existing active row:
    ```sql
    UPDATE dim_customers_scd2
    SET valid_to = CURRENT_TIMESTAMP, is_current = FALSE
    WHERE customer_unique_id = stg.customer_unique_id AND is_current = TRUE;
    ```
2.  **Insert New Current Records:** Insert the updated staging record as the new active row:
    ```sql
    INSERT INTO dim_customers_scd2 (customer_unique_id, customer_zip_code_prefix, customer_city, customer_state, valid_from, valid_to, is_current)
    VALUES (stg.customer_unique_id, stg.customer_zip_code_prefix, stg.customer_city, stg.customer_state, CURRENT_TIMESTAMP, '9999-12-31'::timestamp, TRUE);
    ```

### Step 3: Modify Fact Table Joins
In the ETL loading step for `fact_order_items`, the join to the customer dimension must match the order's purchase date to the customer record's active date range:
```sql
INSERT INTO fact_order_items (...)
SELECT ...
FROM stg_order_items oi
JOIN dim_orders o ON oi.order_id = o.order_id
JOIN dim_customers_scd2 c 
  ON o.customer_unique_id = c.customer_unique_id
  -- Match transaction date to the customer's location history
  AND o.purchase_timestamp >= c.valid_from 
  AND o.purchase_timestamp < c.valid_to;
```
*This approach ensures that sales revenue is correctly attributed to the state where the customer lived at the time of purchase.*
