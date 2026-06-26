--Monthly revenue with MoM and YoY growth
WITH monthly_revenue AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        COUNT(DISTINCT f.invoice_id)    AS order_count,
        COUNT(DISTINCT f.customer_key)  AS unique_customers,
        ROUND(SUM(f.revenue), 2)        AS total_revenue,
        ROUND(SUM(f.profit), 2)         AS total_profit,
        ROUND(AVG(f.order_value), 2)    AS avg_order_value
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
    GROUP BY d.year, d.month, d.month_name
)
SELECT
    year,
    month,
    month_name,
    order_count,
    unique_customers,
    total_revenue,
    total_profit,
    avg_order_value,
    LAG(total_revenue) OVER (PARTITION BY month ORDER BY year)   AS prev_year_revenue,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (PARTITION BY month ORDER BY year)) * 100.0
        / NULLIF(LAG(total_revenue) OVER (PARTITION BY month ORDER BY year), 0), 2
    ) AS yoy_growth_pct,
    LAG(total_revenue) OVER (ORDER BY year, month)               AS prev_month_revenue,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY year, month)) * 100.0
        / NULLIF(LAG(total_revenue) OVER (ORDER BY year, month), 0), 2
    ) AS mom_growth_pct,
    SUM(total_revenue) OVER (
        PARTITION BY year
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS ytd_revenue
FROM monthly_revenue
ORDER BY year, month;


--Annual revenue summary with YoY comparison 
WITH annual AS (
    SELECT
        d.year,
        COUNT(DISTINCT f.invoice_id)    AS total_orders,
        COUNT(DISTINCT f.customer_key)  AS total_customers,
        ROUND(SUM(f.revenue), 2)        AS total_revenue,
        ROUND(SUM(f.profit), 2)         AS total_profit,
        ROUND(AVG(f.order_value), 2)    AS avg_order_value,
        ROUND(SUM(f.revenue) / COUNT(DISTINCT f.customer_key), 2) AS revenue_per_customer
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
    avg_order_value,
    revenue_per_customer,
    LAG(total_revenue) OVER (ORDER BY year) AS prev_year_revenue,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY year)) * 100.0
        / NULLIF(LAG(total_revenue) OVER (ORDER BY year), 0), 2
    ) AS yoy_growth_pct,
    LEAD(total_revenue) OVER (ORDER BY year) AS next_year_revenue
FROM annual
ORDER BY year;

--Quarterly revenue breakdown 
SELECT
    d.year,
    d.quarter,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    COUNT(DISTINCT f.customer_key)  AS unique_customers,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(SUM(f.profit), 2)         AS total_profit,
    ROUND(AVG(f.order_value), 2)    AS avg_order_value,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (PARTITION BY d.year), 2) AS pct_of_annual_revenue
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_key = d.date_key
GROUP BY d.year, d.quarter
ORDER BY d.year, d.quarter;

--Revenue by day of week — which days sell most 
SELECT
    d.day_of_week,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(AVG(f.order_value), 2)    AS avg_order_value,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC) AS revenue_rank
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_key = d.date_key
GROUP BY d.day_of_week
ORDER BY revenue_rank;

--Weekday vs weekend revenue 
SELECT
    CASE WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    COUNT(DISTINCT f.customer_key)  AS unique_customers,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(AVG(f.order_value), 2)    AS avg_order_value,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2) AS revenue_pct
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_key = d.date_key
GROUP BY d.is_weekend
ORDER BY total_revenue DESC;

--top 10 highest revenue days

SELECT
    d.full_date,
    d.day_of_week,
    d.month_name,
    d.year,
    COUNT(DISTINCT f.invoice_id)    AS order_count,
    COUNT(DISTINCT f.customer_key)  AS unique_customers,
    ROUND(SUM(f.revenue), 2)        AS total_revenue
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_key = d.date_key
GROUP BY d.full_date, d.day_of_week, d.month_name, d.year
ORDER BY total_revenue DESC
LIMIT 10;

--rolling 3-month average revenue
WITH monthly AS (
    SELECT
        d.year,
        d.month,
        ROUND(SUM(f.revenue), 2) AS total_revenue
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
    GROUP BY d.year, d.month
)
SELECT
    year,
    month,
    total_revenue,
    ROUND(AVG(total_revenue) OVER (
        ORDER BY year, month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_3m_avg_revenue
FROM monthly
ORDER BY year, month;