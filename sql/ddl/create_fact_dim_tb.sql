-- SET CONFIG
USE DATABASE CUSTOMER360;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;
USE SCHEMA ANALYTICS;

-- Dimensions tables 

CREATE OR REPLACE TABLE DIM_CUSTOMER (
    customer_key      INTEGER       PRIMARY KEY,
    customer_id       VARCHAR(20)   NOT NULL,
    country           VARCHAR(100),
    segment           VARCHAR(50),
    recency_days      INTEGER,
    frequency         INTEGER,
    monetary          FLOAT,
    clv               FLOAT,
    r_score           INTEGER,
    f_score           INTEGER,
    m_score           INTEGER,
    rfm_score         INTEGER,
    customer_type     VARCHAR(20),
    created_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE DIM_PRODUCT (
    product_key       INTEGER       PRIMARY KEY,
    product_id        VARCHAR(20)   NOT NULL,
    product_name      VARCHAR(500),
    category          VARCHAR(100),
    created_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE DIM_DATE (
    date_key          INTEGER       PRIMARY KEY,
    full_date         DATE          NOT NULL,
    day               INTEGER,
    day_of_week       VARCHAR(20),
    week              INTEGER,
    month             INTEGER,
    month_name        VARCHAR(20),
    quarter           INTEGER,
    year              INTEGER,
    is_weekend        BOOLEAN,
    created_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE DIM_LOCATION (
    location_key      INTEGER       PRIMARY KEY,
    country           VARCHAR(100)  NOT NULL,
    region            VARCHAR(100),
    created_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Fact Table 

CREATE OR REPLACE TABLE FACT_SALES (
    sale_id           INTEGER       AUTOINCREMENT PRIMARY KEY,
    invoice_id        VARCHAR(20)   NOT NULL,
    customer_key      INTEGER       REFERENCES DIM_CUSTOMER(customer_key),
    product_key       INTEGER       REFERENCES DIM_PRODUCT(product_key),
    date_key          INTEGER       REFERENCES DIM_DATE(date_key),
    location_key      INTEGER       REFERENCES DIM_LOCATION(location_key),
    quantity          INTEGER,
    unit_price        FLOAT,
    revenue           FLOAT,
    discount          FLOAT,
    profit            FLOAT,
    order_value       FLOAT,
    created_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (date_key, customer_key);  -- speeds up time-series and customer queries

SHOW TABLES IN SCHEMA ANALYTICS;

-- check tbs
SELECT 'DIM_CUSTOMER' AS table_name, COUNT(*) AS row_count FROM DIM_CUSTOMER UNION ALL
SELECT 'DIM_PRODUCT',                COUNT(*)               FROM DIM_PRODUCT  UNION ALL
SELECT 'DIM_DATE',                   COUNT(*)               FROM DIM_DATE     UNION ALL
SELECT 'DIM_LOCATION',               COUNT(*)               FROM DIM_LOCATION UNION ALL
SELECT 'FACT_SALES',                 COUNT(*)               FROM FACT_SALES
ORDER BY table_name;

-- Quick sanity join — top 5 customers by revenue
SELECT
    c.customer_id,
    c.segment,
    c.country,
    SUM(f.revenue) AS total_revenue
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.customer_key = c.customer_key
GROUP BY 1, 2, 3
ORDER BY total_revenue DESC
LIMIT 5;