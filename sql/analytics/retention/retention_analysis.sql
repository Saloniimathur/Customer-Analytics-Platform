--Monthly cohort retention table
--Each row = cohort month × period
WITH first_purchase AS (
    SELECT
        c.customer_key,
        DATE_TRUNC('month', MIN(d.full_date)) AS cohort_month
    FROM FACT_SALES f
    JOIN DIM_CUSTOMER c ON f.customer_key = c.customer_key
    JOIN DIM_DATE     d ON f.date_key     = d.date_key
    GROUP BY c.customer_key
),
monthly_activity AS (
    SELECT DISTINCT
        f.customer_key,
        DATE_TRUNC('month', d.full_date) AS activity_month
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
),
cohort_data AS (
    SELECT
        fp.cohort_month,
        DATEDIFF('month', fp.cohort_month, ma.activity_month) AS period,
        COUNT(DISTINCT fp.customer_key) AS active_customers
    FROM first_purchase fp
    JOIN monthly_activity ma ON fp.customer_key = ma.customer_key
    GROUP BY fp.cohort_month, period
),
cohort_sizes AS (
    SELECT cohort_month, active_customers AS cohort_size
    FROM cohort_data
    WHERE period = 0
)
SELECT
    cd.cohort_month,
    cs.cohort_size,
    cd.period,
    cd.active_customers,
    ROUND(cd.active_customers * 100.0 / cs.cohort_size, 2) AS retention_rate_pct
FROM cohort_data cd
JOIN cohort_sizes cs ON cd.cohort_month = cs.cohort_month
WHERE cd.period <= 12
ORDER BY cd.cohort_month, cd.period;


--Overall retention rate by cohort (M1, M3, M6, M12)
WITH first_purchase AS (
    SELECT
        c.customer_key,
        DATE_TRUNC('month', MIN(d.full_date)) AS cohort_month
    FROM FACT_SALES f
    JOIN DIM_CUSTOMER c ON f.customer_key = c.customer_key
    JOIN DIM_DATE     d ON f.date_key     = d.date_key
    GROUP BY c.customer_key
),
monthly_activity AS (
    SELECT DISTINCT
        f.customer_key,
        DATE_TRUNC('month', d.full_date) AS activity_month
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
),
cohort_data AS (
    SELECT
        fp.cohort_month,
        fp.customer_key,
        DATEDIFF('month', fp.cohort_month, ma.activity_month) AS period
    FROM first_purchase fp
    JOIN monthly_activity ma ON fp.customer_key = ma.customer_key
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_key) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT
    cd.cohort_month,
    cs.cohort_size,
    COUNT(DISTINCT CASE WHEN period = 1  THEN customer_key END) AS m1_retained,
    COUNT(DISTINCT CASE WHEN period = 3  THEN customer_key END) AS m3_retained,
    COUNT(DISTINCT CASE WHEN period = 6  THEN customer_key END) AS m6_retained,
    COUNT(DISTINCT CASE WHEN period = 12 THEN customer_key END) AS m12_retained,
    ROUND(COUNT(DISTINCT CASE WHEN period = 1  THEN customer_key END) * 100.0 / cs.cohort_size, 2) AS m1_retention_pct,
    ROUND(COUNT(DISTINCT CASE WHEN period = 3  THEN customer_key END) * 100.0 / cs.cohort_size, 2) AS m3_retention_pct,
    ROUND(COUNT(DISTINCT CASE WHEN period = 6  THEN customer_key END) * 100.0 / cs.cohort_size, 2) AS m6_retention_pct,
    ROUND(COUNT(DISTINCT CASE WHEN period = 12 THEN customer_key END) * 100.0 / cs.cohort_size, 2) AS m12_retention_pct
FROM cohort_data cd
JOIN cohort_sizes cs ON cd.cohort_month = cs.cohort_month
GROUP BY cd.cohort_month, cs.cohort_size
ORDER BY cd.cohort_month;


--Repeat purchase rate 
SELECT
    COUNT(DISTINCT CASE WHEN frequency > 1 THEN customer_key END) AS repeat_customers,
    COUNT(DISTINCT customer_key)                                    AS total_customers,
    ROUND(
        COUNT(DISTINCT CASE WHEN frequency > 1 THEN customer_key END) * 100.0
        / COUNT(DISTINCT customer_key), 2
    ) AS repeat_purchase_rate_pct
FROM DIM_CUSTOMER;

--Average days between orders per customer segment
WITH purchase_gaps AS (
    SELECT
        f.customer_key,
        d.full_date,
        LAG(d.full_date) OVER (PARTITION BY f.customer_key ORDER BY d.full_date) AS prev_date
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
),
gap_stats AS (
    SELECT
        customer_key,
        AVG(DATEDIFF('day', prev_date, full_date)) AS avg_gap_days,
        MIN(DATEDIFF('day', prev_date, full_date)) AS min_gap_days,
        MAX(DATEDIFF('day', prev_date, full_date)) AS max_gap_days
    FROM purchase_gaps
    WHERE prev_date IS NOT NULL
    GROUP BY customer_key
)
SELECT
    c.segment,
    COUNT(DISTINCT c.customer_key)      AS customer_count,
    ROUND(AVG(g.avg_gap_days), 1)       AS avg_days_between_orders,
    ROUND(MIN(g.min_gap_days), 0)       AS fastest_repeat_days,
    ROUND(MAX(g.max_gap_days), 0)       AS slowest_repeat_days
FROM gap_stats g
JOIN DIM_CUSTOMER c ON g.customer_key = c.customer_key
GROUP BY c.segment
ORDER BY avg_days_between_orders;

--Customer lifespan — first to last purchase
WITH customer_span AS (
    SELECT
        f.customer_key,
        MIN(d.full_date) AS first_purchase,
        MAX(d.full_date) AS last_purchase,
        DATEDIFF('day', MIN(d.full_date), MAX(d.full_date)) AS lifespan_days,
        COUNT(DISTINCT f.invoice_id) AS total_orders
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
    GROUP BY f.customer_key
)
SELECT
    c.segment,
    COUNT(DISTINCT c.customer_key)      AS customer_count,
    ROUND(AVG(cs.lifespan_days), 0)     AS avg_lifespan_days,
    ROUND(AVG(cs.total_orders), 1)      AS avg_orders_per_customer,
    MIN(cs.first_purchase)              AS earliest_first_purchase,
    MAX(cs.last_purchase)               AS latest_last_purchase
FROM customer_span cs
JOIN DIM_CUSTOMER c ON cs.customer_key = c.customer_key
GROUP BY c.segment
ORDER BY avg_lifespan_days DESC;

--Monthly new vs returning customer count
WITH first_purchase AS (
    SELECT
        customer_key,
        MIN(date_key) AS first_date_key
    FROM FACT_SALES
    GROUP BY customer_key
),
monthly_customers AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        f.customer_key,
        CASE WHEN f.date_key = fp.first_date_key THEN 'New' ELSE 'Returning' END AS customer_type
    FROM FACT_SALES f
    JOIN DIM_DATE d         ON f.date_key     = d.date_key
    JOIN first_purchase fp  ON f.customer_key = fp.customer_key
)
SELECT
    year,
    month,
    month_name,
    COUNT(DISTINCT CASE WHEN customer_type = 'New'       THEN customer_key END) AS new_customers,
    COUNT(DISTINCT CASE WHEN customer_type = 'Returning' THEN customer_key END) AS returning_customers,
    COUNT(DISTINCT customer_key)                                                 AS total_customers
FROM monthly_customers
GROUP BY year, month, month_name
ORDER BY year, month;