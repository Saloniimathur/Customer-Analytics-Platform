--Revenue by region
SELECT
    l.region,
    COUNT(DISTINCT l.country)           AS country_count,
    COUNT(DISTINCT f.invoice_id)        AS order_count,
    COUNT(DISTINCT f.customer_key)      AS unique_customers,
    ROUND(SUM(f.revenue), 2)            AS total_revenue,
    ROUND(SUM(f.profit), 2)             AS total_profit,
    ROUND(AVG(f.order_value), 2)        AS avg_order_value,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS revenue_rank,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2) AS revenue_share_pct
FROM FACT_SALES f
JOIN DIM_LOCATION l ON f.location_key = l.location_key
GROUP BY l.region
ORDER BY revenue_rank;

--Revenue by country with global and regional ranking
SELECT
    l.region,
    l.country,
    COUNT(DISTINCT f.invoice_id)        AS order_count,
    COUNT(DISTINCT f.customer_key)      AS unique_customers,
    ROUND(SUM(f.revenue), 2)            AS total_revenue,
    ROUND(SUM(f.profit), 2)             AS total_profit,
    ROUND(AVG(f.order_value), 2)        AS avg_order_value,
    SUM(f.quantity)                     AS total_units_sold,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC)                          AS global_rank,
    RANK() OVER (PARTITION BY l.region ORDER BY SUM(f.revenue) DESC)    AS region_rank,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2)              AS global_revenue_share_pct,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (PARTITION BY l.region), 2) AS region_revenue_share_pct
FROM FACT_SALES f
JOIN DIM_LOCATION l ON f.location_key = l.location_key
GROUP BY l.region, l.country
ORDER BY global_rank;

--top 10 markets by revenue
SELECT
    l.country,
    l.region,
    COUNT(DISTINCT f.customer_key)  AS unique_customers,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(AVG(f.order_value), 2)    AS avg_order_value,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS revenue_rank
FROM FACT_SALES f
JOIN DIM_LOCATION l ON f.location_key = l.location_key
GROUP BY l.country, l.region
ORDER BY revenue_rank
LIMIT 10;

--Customer segment distribution by region
SELECT
    l.region,
    c.segment,
    COUNT(DISTINCT c.customer_key)  AS customer_count,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(COUNT(DISTINCT c.customer_key) * 100.0 / SUM(COUNT(DISTINCT c.customer_key)) OVER (PARTITION BY l.region), 2) AS segment_pct_in_region
FROM FACT_SALES f
JOIN DIM_CUSTOMER c  ON f.customer_key  = c.customer_key
JOIN DIM_LOCATION l  ON f.location_key  = l.location_key
GROUP BY l.region, c.segment
ORDER BY l.region, total_revenue DESC;

--monthly revenue trend by region 

SELECT
    d.year,
    d.month,
    d.month_name,
    l.region,
    ROUND(SUM(f.revenue), 2) AS total_revenue,
    COUNT(DISTINCT f.invoice_id) AS order_count,
    ROUND(SUM(f.revenue) - LAG(SUM(f.revenue)) OVER (
        PARTITION BY l.region ORDER BY d.year, d.month
    ), 2) AS mom_revenue_change
FROM FACT_SALES f
JOIN DIM_DATE     d ON f.date_key     = d.date_key
JOIN DIM_LOCATION l ON f.location_key = l.location_key
GROUP BY d.year, d.month, d.month_name, l.region
ORDER BY l.region, d.year, d.month;

--Average order value by country — top 15
SELECT
    l.country,
    l.region,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    ROUND(AVG(f.order_value), 2)    AS avg_order_value,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    RANK() OVER (ORDER BY AVG(f.order_value) DESC) AS aov_rank
FROM FACT_SALES f
JOIN DIM_LOCATION l ON f.location_key = l.location_key
GROUP BY l.country, l.region
HAVING COUNT(DISTINCT f.invoice_id) >= 10
ORDER BY aov_rank
LIMIT 15;