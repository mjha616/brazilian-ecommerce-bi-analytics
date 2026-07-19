# SQL Coding & Style Convention Guide

To ensure code maintainability, team readability, and high performance across BI developers, the database engineering layer enforces the following guidelines.

---

## 1. Capitalization & Typography

*   **SQL Keywords:** Always write keywords, built-in functions, and data types in **UPPERCASE** (e.g. `SELECT`, `FROM`, `WHERE`, `JOIN`, `ON`, `GROUP BY`, `SUM()`, `CAST()`, `INTEGER`, `TIMESTAMP`).
*   **Database Objects:** Always write table names, view names, column names, schemas, and aliases in **lowercase** using **snake_case** (e.g., `fact_order_items`, `customer_unique_id`, `vw_sales_summary`).

---

## 2. Query Structure & Joins

*   **Explicit JOIN Syntax:** Always use ANSI SQL explicit joins (`INNER JOIN`, `LEFT JOIN`, `RIGHT JOIN`, `CROSS JOIN`, `FULL OUTER JOIN`) with `ON` criteria. Never use implicit comma-separated joins with `WHERE` clauses.
*   **Aliasing Tables:** Use meaningful, short table aliases (e.g., `fact_order_items AS i`, `dim_products AS p`). Avoid single letters like `a`, `b`, `c` when they represent non-intuitive relations. Always use the explicit `AS` keyword.
*   **No SELECT * in Production:** Never use `SELECT *` in production scripts or view definitions. Explicitly declare every column to ensure schema change stability.

---

## 3. CTE (Common Table Expression) Usage

*   **Name Meanings:** Name CTEs clearly after their business logic (e.g., `WITH MonthlySales AS (...)`).
*   **Decoupling Logic:** Prefer CTEs over subqueries for readability. Align indentation levels for brackets and select queries within the CTE.

---

## 4. Query Formatting & Indentation

*   **Align Clauses:** Align major SQL clauses (`SELECT`, `FROM`, `JOIN`, `WHERE`, `GROUP BY`, `ORDER BY`) to the left margin.
*   **Line Breaks:** Insert a line break for every column in the `SELECT` list.
*   **Indenting:** Use 4 spaces for indentation. Never use tabs.

### Example Alignment:
```sql
SELECT
    i.order_id,
    p.category,
    SUM(i.price) AS category_revenue
FROM fact_order_items i
JOIN dim_products p ON i.product_id = p.product_id
WHERE i.purchase_date >= '2018-01-01'::date
GROUP BY 1, 2
ORDER BY category_revenue DESC;
```

---

## 5. Commenting

*   **Header Blocks:** Include a header block at the top of scripts detailing target DB, author, purpose, and dependencies.
*   **Inline Comments:** Comment complex logic, regular expressions, window partitions, and business assumptions using double dashes (`--`).
