-- total customers, total order, total revenue
select * from FACT_SALES limit 5;

select
    COUNT(DISTINCT Customer_Key) AS TotalCustomers,
    COUNT(DISTINCT Invoice_ID) AS TotalOrders,
    ROUND(SUM(Revenue),2) AS TotalRevenue,
    ROUND(AVG(Revenue),2) AS AverageOrderValue,
    ROUND(SUM(Quantity),2) AS TotalItemsSold
from FACT_SALES;

--top customers by revenue
SELECT
    dc.Customer_ID,
    COUNT(DISTINCT fs.Invoice_id) AS Orders,
    SUM(fs.Revenue) AS Revenue,
    RANK() OVER(
        ORDER BY SUM(fs.Revenue) DESC
    ) AS RevenueRank
FROM FACT_SALES fs
JOIN DIM_CUSTOMER dc
ON fs.Customer_Key = dc.Customer_Key
GROUP BY dc.Customer_ID
QUALIFY RevenueRank <= 20;

select dc.Customer_ID,
    COUNT(DISTINCT fs.Invoice_id) AS Orders,
    SUM(fs.Revenue) AS Revenue
    FROM FACT_SALES fs
JOIN DIM_CUSTOMER dc
ON fs.Customer_Key = dc.Customer_Key
GROUP BY dc.Customer_ID
order by Revenue desc
limit 20;


-- most frequent customers
SELECT
    dc.Customer_ID,
    COUNT(DISTINCT fs.Invoice_id) AS PurchaseFrequency,
    SUM(fs.Revenue) AS TotalRevenue,
    ROUND(
        AVG(fs.Revenue),2
    ) AS AverageOrderValue
FROM FACT_SALES fs
JOIN DIM_CUSTOMER dc
ON fs.Customer_Key = dc.Customer_Key
GROUP BY dc.Customer_ID
ORDER BY PurchaseFrequency DESC;

-- inactive customers from last 90 days
select
    dc.Customer_ID,
    MAX(dd.Full_Date) AS LastPurchaseDate,
    DATEDIFF(
        DAY,
        MAX(dd.Full_Date),
        CURRENT_DATE()
    ) AS DaysInactive
FROM FACT_SALES fs
JOIN DIM_CUSTOMER dc
ON fs.Customer_Key = dc.Customer_Key
JOIN DIM_DATE dd
ON fs.Date_Key = dd.Date_Key
GROUP BY dc.Customer_ID
HAVING DaysInactive > 90
ORDER BY DaysInactive DESC;

--customer segmentation
SELECT
    dc.Country,
    COUNT(DISTINCT dc.Customer_ID) AS Customers,
    SUM(fs.Revenue) AS Revenue,
    AVG(fs.Revenue) AS AvgRevenue
FROM FACT_SALES fs
JOIN DIM_CUSTOMER dc
ON fs.Customer_Key = dc.Customer_Key
GROUP BY dc.Country
ORDER BY Revenue DESC;

-- RFM Segmentation--
WITH customer_metrics AS (
    SELECT
        c.customer_id,
        c.customer_key,
        DATEDIFF('day', MAX(d.full_date), '2012-01-01') AS recency_days,
        COUNT(DISTINCT f.invoice_id)                     AS frequency,
        ROUND(SUM(f.revenue), 2)                         AS monetary
    FROM FACT_SALES f
    JOIN DIM_CUSTOMER c ON f.customer_key = c.customer_key
    JOIN DIM_DATE     d ON f.date_key     = d.date_key
    GROUP BY c.customer_id, c.customer_key
),
rfm_scored AS (
    SELECT
        customer_id,
        customer_key,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM customer_metrics
),
rfm_segmented AS (
    SELECT
        *,
        r_score + f_score + m_score AS rfm_score,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP'
            WHEN r_score >= 3 AND f_score >= 3                   THEN 'Loyal'
            WHEN r_score >= 4 AND f_score <= 2                   THEN 'New'
            WHEN r_score <= 2 AND f_score >= 3                   THEN 'At Risk'
            WHEN r_score = 1                                      THEN 'Lost'
            ELSE 'Potential'
        END AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(*)                        AS customer_count,
    ROUND(AVG(recency_days), 1)     AS avg_recency_days,
    ROUND(AVG(frequency), 1)        AS avg_frequency,
    ROUND(AVG(monetary), 2)         AS avg_monetary,
    ROUND(SUM(monetary), 2)         AS total_revenue,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2) AS revenue_pct
FROM rfm_segmented
GROUP BY segment
ORDER BY total_revenue DESC;


-- Customer segment distribution
SELECT
    segment,
    COUNT(*)                                                        AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS customer_pct,
    ROUND(SUM(monetary), 2)                                         AS total_revenue,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2)   AS revenue_pct,
    ROUND(AVG(clv), 2)                                              AS avg_clv
FROM DIM_CUSTOMER
GROUP BY segment
ORDER BY total_revenue DESC;

--Customer Lifetime Value (CLV)
WITH order_revenue AS (
    SELECT
        customer_key,
        invoice_id,
        date_key,
        SUM(revenue) AS invoice_revenue
    FROM FACT_SALES
    GROUP BY customer_key, invoice_id, date_key
),
customer_timeline AS (
    SELECT
        customer_key,
        invoice_id,
        date_key,
        invoice_revenue,
        ROW_NUMBER() OVER (PARTITION BY customer_key ORDER BY date_key, invoice_id) AS order_seq,
        SUM(invoice_revenue) OVER (
            PARTITION BY customer_key
            ORDER BY date_key, invoice_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue
    FROM order_revenue
),
customer_clv AS (
    SELECT
        customer_key,
        MAX(order_seq)          AS total_orders,
        MAX(cumulative_revenue) AS total_clv,
        ROUND(MAX(cumulative_revenue) / NULLIF(MAX(order_seq), 0), 2) AS avg_order_value,
        NTILE(4) OVER (ORDER BY MAX(cumulative_revenue)) AS clv_quartile
    FROM customer_timeline
    GROUP BY customer_key
)
SELECT
    clv_quartile,
    CASE clv_quartile
        WHEN 4 THEN 'Top 25% — Champions'
        WHEN 3 THEN 'Upper Mid — High Value'
        WHEN 2 THEN 'Lower Mid — Medium Value'
        WHEN 1 THEN 'Bottom 25% — Low Value'
    END AS clv_tier,
    COUNT(*)                        AS customer_count,
    ROUND(MIN(total_clv), 2)        AS min_clv,
    ROUND(AVG(total_clv), 2)        AS avg_clv,
    ROUND(MAX(total_clv), 2)        AS max_clv,
    ROUND(SUM(total_clv), 2)        AS total_revenue,
    ROUND(AVG(total_orders), 1)     AS avg_orders,
    ROUND(AVG(avg_order_value), 2)  AS avg_order_value
FROM customer_clv
GROUP BY clv_quartile
ORDER BY clv_quartile DESC;

--New vs Returning customers — order volume & revenue
SELECT
    c.customer_type,
    COUNT(DISTINCT c.customer_key)  AS customer_count,
    COUNT(DISTINCT f.invoice_id)    AS total_orders,
    ROUND(SUM(f.revenue), 2)        AS total_revenue,
    ROUND(AVG(f.order_value), 2)    AS avg_order_value,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2) AS revenue_pct
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.customer_key = c.customer_key
GROUP BY c.customer_type
ORDER BY total_revenue DESC;

--Churn risk classification by recency
WITH customer_activity AS (
    SELECT
        c.customer_key,
        c.customer_id,
        c.segment,
        c.monetary,
        c.frequency,
        c.recency_days
    FROM DIM_CUSTOMER c
),
purchase_dates AS (
    SELECT
        f.customer_key,
        d.full_date,
        LAG(d.full_date) OVER (PARTITION BY f.customer_key ORDER BY d.full_date) AS prev_date
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.date_key = d.date_key
),
purchase_gaps AS (
    SELECT
        customer_key,
        AVG(DATEDIFF('day', prev_date, full_date)) AS avg_days_between_orders
    FROM purchase_dates
    WHERE prev_date IS NOT NULL
    GROUP BY customer_key
),
churn_scored AS (
    SELECT
        ca.*,
        pg.avg_days_between_orders,
        CASE
            WHEN ca.recency_days > 180               THEN 'Churned'
            WHEN ca.recency_days BETWEEN 91 AND 180  THEN 'High Risk'
            WHEN ca.recency_days BETWEEN 61 AND 90   THEN 'Medium Risk'
            WHEN ca.recency_days BETWEEN 31 AND 60   THEN 'Low Risk'
            ELSE 'Active'
        END AS churn_status
    FROM customer_activity ca
    LEFT JOIN purchase_gaps pg ON ca.customer_key = pg.customer_key
)
SELECT
    churn_status,
    COUNT(*)                                AS customer_count,
    ROUND(AVG(monetary), 2)                 AS avg_revenue,
    ROUND(SUM(monetary), 2)                 AS total_revenue_at_risk,
    ROUND(AVG(frequency), 1)                AS avg_orders,
    ROUND(AVG(recency_days), 0)             AS avg_recency_days,
    ROUND(AVG(avg_days_between_orders), 0)  AS avg_purchase_gap_days,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)              AS customer_share_pct,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2)    AS revenue_share_pct
FROM churn_scored
GROUP BY churn_status
ORDER BY
    CASE churn_status
        WHEN 'Churned'      THEN 1
        WHEN 'High Risk'    THEN 2
        WHEN 'Medium Risk'  THEN 3
        WHEN 'Low Risk'     THEN 4
        ELSE 5
    END;


--High-value customers at churn risk
SELECT
    c.customer_id,
    c.segment,
    c.country,
    c.recency_days,
    c.frequency,
    ROUND(c.monetary, 2) AS lifetime_revenue,
    ROUND(c.clv, 2)      AS clv,
    CASE
        WHEN c.recency_days > 180              THEN 'Churned'
        WHEN c.recency_days BETWEEN 91 AND 180 THEN 'High Risk'
        ELSE 'Medium Risk'
    END AS churn_status,
    RANK() OVER (ORDER BY c.monetary DESC) AS revenue_rank
FROM DIM_CUSTOMER c
WHERE c.recency_days > 90
  AND c.monetary > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY monetary) FROM DIM_CUSTOMER)
ORDER BY lifetime_revenue DESC
LIMIT 20;
