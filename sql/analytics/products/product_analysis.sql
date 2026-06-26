--Top 10 products by total revenue
SELECT
    p.product_id,
    p.product_name,
    p.category,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    SUM(f.quantity)                 AS total_units_sold,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(SUM(f.profit), 2)         AS total_profit,
    ROUND(AVG(f.unit_price), 2)     AS avg_price,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS revenue_rank
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_key = p.product_key
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue_rank
LIMIT 10;

--Top 10 products by units sold
SELECT
    p.product_id,
    p.product_name,
    p.category,
    SUM(f.quantity)                 AS total_units_sold,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(AVG(f.unit_price), 2)     AS avg_price,
    COUNT(DISTINCT f.customer_key)  AS unique_customers,
    RANK() OVER (ORDER BY SUM(f.quantity) DESC) AS volume_rank
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_key = p.product_key
GROUP BY p.product_id, p.product_name, p.category
ORDER BY volume_rank
LIMIT 10;

--Pareto analysis — products driving 80% of revenue
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category,
        ROUND(SUM(f.revenue), 2) AS total_revenue
    FROM FACT_SALES f
    JOIN DIM_PRODUCT p ON f.product_key = p.product_key
    GROUP BY p.product_id, p.product_name, p.category
),
pareto AS (
    SELECT
        *,
        RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_revenue,
        SUM(total_revenue) OVER ()                             AS grand_total
    FROM product_revenue
)
SELECT
    product_id,
    product_name,
    category,
    revenue_rank,
    total_revenue,
    ROUND(total_revenue * 100.0 / grand_total, 4)       AS revenue_share_pct,
    ROUND(cumulative_revenue * 100.0 / grand_total, 2)  AS cumulative_revenue_pct,
    CASE
        WHEN cumulative_revenue * 100.0 / grand_total <= 80 THEN 'Top 80% Revenue'
        ELSE 'Tail 20% Revenue'
    END AS pareto_band
FROM pareto
ORDER BY revenue_rank;


--Category performance summary
SELECT
    p.category,
    COUNT(DISTINCT p.product_id)    AS product_count,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    SUM(f.quantity)                 AS total_units_sold,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(SUM(f.profit), 2)         AS total_profit,
    ROUND(AVG(f.unit_price), 2)     AS avg_price,
    COUNT(DISTINCT f.customer_key)  AS unique_customers,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS revenue_rank,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2) AS revenue_share_pct
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY revenue_rank;

--Top product per category
WITH category_ranked AS (
    SELECT
        p.category,
        p.product_id,
        p.product_name,
        ROUND(SUM(f.revenue), 2)    AS total_revenue,
        SUM(f.quantity)             AS total_units_sold,
        RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.revenue) DESC) AS rank_in_category
    FROM FACT_SALES f
    JOIN DIM_PRODUCT p ON f.product_key = p.product_key
    GROUP BY p.category, p.product_id, p.product_name
)
SELECT
    category,
    product_id,
    product_name,
    total_revenue,
    total_units_sold
FROM category_ranked
WHERE rank_in_category = 1
ORDER BY total_revenue DESC;

--Product sales trend — monthly revenue per category
SELECT
    d.year,
    d.month,
    d.month_name,
    p.category,
    COUNT(DISTINCT f.invoice_id)  AS order_count,
    SUM(f.quantity)               AS total_units_sold,
    ROUND(SUM(f.revenue), 2)      AS total_revenue,
    ROUND(SUM(f.revenue) - LAG(SUM(f.revenue)) OVER (
        PARTITION BY p.category ORDER BY d.year, d.month
    ), 2) AS mom_revenue_change
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_key = p.product_key
JOIN DIM_DATE    d ON f.date_key    = d.date_key
GROUP BY d.year, d.month, d.month_name, p.category
ORDER BY p.category, d.year, d.month;