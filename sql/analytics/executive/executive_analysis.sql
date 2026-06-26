--Overall business KPIs
SELECT
    COUNT(DISTINCT f.invoice_id)        AS total_orders,
    COUNT(DISTINCT f.customer_key)      AS total_customers,
    COUNT(DISTINCT f.product_key)       AS total_products,
    COUNT(DISTINCT f.location_key)      AS total_markets,
    ROUND(SUM(f.revenue), 2)            AS total_revenue,
    ROUND(SUM(f.profit), 2)             AS total_profit,
    ROUND(SUM(f.profit) * 100.0 / SUM(f.revenue), 2) AS profit_margin_pct,
    ROUND(AVG(f.order_value), 2)        AS avg_order_value,
    ROUND(SUM(f.revenue) / COUNT(DISTINCT f.customer_key), 2) AS revenue_per_customer
FROM FACT_SALES f;


--Annual KPIs with YoY comparison
WITH annual AS (
    SELECT
        d.year,
        COUNT(DISTINCT f.invoice_id)    AS total_orders,
        COUNT(DISTINCT f.customer_key)  AS total_customers,
        ROUND(SUM(f.revenue), 2)        AS total_revenue,
        ROUND(SUM(f.profit), 2)         AS total_profit,
        ROUND(AVG(f.order_value), 2)    AS avg_order_value
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
    GROUP BY d.year
)
SELECT
    year,
    total_orders,
    total_customers,
    total_revenue,
    total_profit,
    ROUND(total_profit * 100.0 / total_revenue, 2) AS profit_margin_pct,
    avg_order_value,
    LAG(total_revenue) OVER (ORDER BY year) AS prev_year_revenue,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY year)) * 100.0
        / NULLIF(LAG(total_revenue) OVER (ORDER BY year), 0), 2
    ) AS yoy_revenue_growth_pct,
    LAG(total_customers) OVER (ORDER BY year) AS prev_year_customers,
    ROUND(
        (total_customers - LAG(total_customers) OVER (ORDER BY year)) * 100.0
        / NULLIF(LAG(total_customers) OVER (ORDER BY year), 0), 2
    ) AS yoy_customer_growth_pct
FROM annual
ORDER BY year;

--Customer segment health snapshot
SELECT
    segment,
    COUNT(*)                                                        AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS customer_pct,
    ROUND(SUM(monetary), 2)                                         AS total_revenue,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2)   AS revenue_pct,
    ROUND(AVG(clv), 2)                                              AS avg_clv,
    ROUND(AVG(recency_days), 0)                                     AS avg_recency_days,
    ROUND(AVG(frequency), 1)                                        AS avg_orders
FROM DIM_CUSTOMER
GROUP BY segment
ORDER BY total_revenue DESC;

--Revenue contribution — top region, segment, product

WITH region_top AS (
    SELECT l.region, ROUND(SUM(f.revenue), 2) AS revenue,
           RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS rn
    FROM FACT_SALES f
    JOIN DIM_LOCATION l ON f.location_key = l.location_key
    GROUP BY l.region
),
segment_top AS (
    SELECT c.segment, ROUND(SUM(f.revenue), 2) AS revenue,
           RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS rn
    FROM FACT_SALES f
    JOIN DIM_CUSTOMER c ON f.customer_key = c.customer_key
    GROUP BY c.segment
),
category_top AS (
    SELECT p.category, ROUND(SUM(f.revenue), 2) AS revenue,
           RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS rn
    FROM FACT_SALES f
    JOIN DIM_PRODUCT p ON f.product_key = p.product_key
    GROUP BY p.category
)
SELECT
    r.region      AS top_region,      r.revenue AS region_revenue,
    s.segment     AS top_segment,     s.revenue AS segment_revenue,
    c.category    AS top_category,    c.revenue AS category_revenue
FROM region_top   r
JOIN segment_top  s ON s.rn = r.rn
JOIN category_top c ON c.rn = r.rn
WHERE r.rn = 1;


--Monthly revenue run-rate vs prior year
WITH monthly AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        ROUND(SUM(f.revenue), 2) AS total_revenue
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
    GROUP BY d.year, d.month, d.month_name
)
SELECT
    year,
    month,
    month_name,
    total_revenue,
    LAG(total_revenue) OVER (PARTITION BY month ORDER BY year) AS same_month_prior_year,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (PARTITION BY month ORDER BY year)) * 100.0
        / NULLIF(LAG(total_revenue) OVER (PARTITION BY month ORDER BY year), 0), 2
    ) AS yoy_growth_pct,
    SUM(total_revenue) OVER (
        PARTITION BY year
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS ytd_revenue
FROM monthly
ORDER BY year, month;

--Churn risk exposure — revenue at risk summary

SELECT
    CASE
        WHEN recency_days > 180              THEN 'Churned'
        WHEN recency_days BETWEEN 91 AND 180 THEN 'High Risk'
        WHEN recency_days BETWEEN 61 AND 90  THEN 'Medium Risk'
        WHEN recency_days BETWEEN 31 AND 60  THEN 'Low Risk'
        ELSE 'Active'
    END AS churn_status,
    COUNT(*)                                                          AS customer_count,
    ROUND(SUM(monetary), 2)                                           AS revenue_at_risk,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2)     AS pct_of_total_revenue
FROM DIM_CUSTOMER
GROUP BY churn_status
ORDER BY
    CASE churn_status
        WHEN 'Churned'      THEN 1
        WHEN 'High Risk'    THEN 2
        WHEN 'Medium Risk'  THEN 3
        WHEN 'Low Risk'     THEN 4
        ELSE 5
    END;