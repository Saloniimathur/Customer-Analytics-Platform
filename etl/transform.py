import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime
from utils import load_config, setup_logger

config = load_config()
logger = setup_logger(config["etl"]["log_level"])

SNAPSHOT_DATE = datetime(2012, 1, 1)  # 1 day after last transaction for RFM recency

# ── 1. Load ──────────────────────────────────────────────────────────────────

def load_raw() -> pd.DataFrame:
    path = Path(config["paths"]["processed_dir"]) / "raw_combined.csv"
    df = pd.read_csv(path, dtype={"Customer ID": str, "StockCode": str})
    df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"])
    logger.info(f"Loaded raw: {len(df):,} rows")
    return df

# ── 2. Clean ─────────────────────────────────────────────────────────────────

def clean(df: pd.DataFrame) -> pd.DataFrame:
    original_len = len(df)

    # Drop rows with no Customer ID (guest checkouts — can't track behaviour)
    df = df.dropna(subset=["Customer ID"])
    logger.info(f"Dropped {original_len - len(df):,} rows with null Customer ID")

    # Drop rows with no Description
    df = df.dropna(subset=["Description"])

    # Remove cancellations (Invoice starts with C) and returns (Quantity < 0)
    df = df[~df["Invoice"].astype(str).str.startswith("C")]
    df = df[df["Quantity"] > 0]
    df = df[df["Price"] > 0]

    # Remove test/non-product stock codes
    invalid_codes = {"POST", "D", "M", "BANK CHARGES", "PADS", "DOT", "CRUK"}
    df = df[~df["StockCode"].isin(invalid_codes)]
    df = df[~df["StockCode"].str.startswith("GIFT", na=False)]

    # Strip whitespace from string columns
    str_cols = ["StockCode", "Description", "Country"]
    for col in str_cols:
        df[col] = df[col].str.strip()

    # Normalize country names
    df["Country"] = df["Country"].str.title()

    # Remove duplicates
    before = len(df)
    df = df.drop_duplicates(subset=["Invoice", "StockCode", "Customer ID"])
    logger.info(f"Removed {before - len(df):,} duplicate rows")

    logger.info(f"Clean dataset: {len(df):,} rows remaining")
    return df.reset_index(drop=True)

# ── 3. Enrich & derive metrics ────────────────────────────────────────────────

def enrich(df: pd.DataFrame) -> pd.DataFrame:
    # Core financial metrics
    df["Revenue"]      = (df["Quantity"] * df["Price"]).round(2)
    df["Discount"]     = 0.0        # not in this dataset; placeholder for schema
    df["Profit"]       = (df["Revenue"] * 0.4).round(2)   # assumed 40% margin
    df["OrderValue"]   = df.groupby("Invoice")["Revenue"].transform("sum").round(2)

    # Date parts (used to populate DimDate)
    df["InvoiceDate"]  = pd.to_datetime(df["InvoiceDate"])
    df["Date"]         = df["InvoiceDate"].dt.date
    df["Year"]         = df["InvoiceDate"].dt.year
    df["Quarter"]      = df["InvoiceDate"].dt.quarter
    df["Month"]        = df["InvoiceDate"].dt.month
    df["Week"]         = df["InvoiceDate"].dt.isocalendar().week.astype(int)
    df["Day"]          = df["InvoiceDate"].dt.day
    df["DayOfWeek"]    = df["InvoiceDate"].dt.day_name()
    df["IsWeekend"]    = df["InvoiceDate"].dt.dayofweek >= 5

    # RFM components per customer (computed on full dataset, joined back)
    rfm = df.groupby("Customer ID").agg(
        LastPurchaseDate=("InvoiceDate", "max"),
        Frequency=("Invoice", "nunique"),
        Monetary=("Revenue", "sum")
    ).reset_index()

    rfm["Recency"] = (SNAPSHOT_DATE - rfm["LastPurchaseDate"]).dt.days

    # RFM scores (1–5 using quintiles)
    rfm["R_Score"] = pd.qcut(rfm["Recency"],   q=5, labels=[5,4,3,2,1]).astype(int)
    rfm["F_Score"] = pd.qcut(rfm["Frequency"].rank(method="first"), q=5, labels=[1,2,3,4,5]).astype(int)
    rfm["M_Score"] = pd.qcut(rfm["Monetary"].rank(method="first"),  q=5, labels=[1,2,3,4,5]).astype(int)
    rfm["RFM_Score"] = rfm["R_Score"] + rfm["F_Score"] + rfm["M_Score"]

    # Customer segment based on RFM
    def segment(row):
        r, f, m = row["R_Score"], row["F_Score"], row["M_Score"]
        if r >= 4 and f >= 4 and m >= 4: return "VIP"
        elif r >= 3 and f >= 3:          return "Loyal"
        elif r >= 4 and f <= 2:          return "New"
        elif r <= 2 and f >= 3:          return "At Risk"
        elif r == 1:                     return "Lost"
        else:                            return "Potential"

    rfm["Segment"] = rfm.apply(segment, axis=1)

    # CLV: total revenue per customer
    rfm["CLV"] = rfm["Monetary"].round(2)

    # Join RFM back onto main df
    df = df.merge(
        rfm[["Customer ID", "Recency", "Frequency", "Monetary",
             "R_Score", "F_Score", "M_Score", "RFM_Score", "Segment", "CLV"]],
        on="Customer ID", how="left"
    )

    logger.info("Enrichment complete — revenue, RFM, CLV, date parts added")
    return df

# ── 4. Surrogate keys ─────────────────────────────────────────────────────────

def add_surrogate_keys(df: pd.DataFrame) -> pd.DataFrame:
    # Customer key
    customers = df[["Customer ID"]].drop_duplicates().reset_index(drop=True)
    customers["CustomerKey"] = customers.index + 1

    # Product key
    products = df[["StockCode"]].drop_duplicates().reset_index(drop=True)
    products["ProductKey"] = products.index + 1

    # Date key (YYYYMMDD integer)
    df["DateKey"] = df["InvoiceDate"].dt.strftime("%Y%m%d").astype(int)

    # Location key
    locations = df[["Country"]].drop_duplicates().reset_index(drop=True)
    locations["LocationKey"] = locations.index + 1

    df = df.merge(customers, on="Customer ID", how="left")
    df = df.merge(products,  on="StockCode",   how="left")
    df = df.merge(locations, on="Country",     how="left")

    logger.info("Surrogate keys added: CustomerKey, ProductKey, DateKey, LocationKey")
    return df, customers, products, locations

# ── 5. Build dimension & fact tables ─────────────────────────────────────────

def build_dim_customer(df: pd.DataFrame, customers: pd.DataFrame) -> pd.DataFrame:
    # customers df already has Customer ID + CustomerKey
    # merge RFM columns from df onto customers directly
    rfm_cols = df[["Customer ID", "Segment", "Country",
                   "Recency", "Frequency", "Monetary", "CLV",
                   "R_Score", "F_Score", "M_Score", "RFM_Score"]].drop_duplicates(subset=["Customer ID"])

    dim = customers.merge(rfm_cols, on="Customer ID", how="left")

    dim = dim.rename(columns={
        "CustomerKey":  "customer_key",
        "Customer ID":  "customer_id",
        "Country":      "country",
        "Segment":      "segment",
        "Recency":      "recency_days",
        "Frequency":    "frequency",
        "Monetary":     "monetary",
        "CLV":          "clv",
        "R_Score":      "r_score",
        "F_Score":      "f_score",
        "M_Score":      "m_score",
        "RFM_Score":    "rfm_score",
    })

    dim["customer_type"] = np.where(dim["frequency"] > 1, "Returning", "New")
    logger.info(f"DimCustomer: {len(dim):,} rows")
    return dim

def build_dim_product(df: pd.DataFrame, products: pd.DataFrame) -> pd.DataFrame:
    desc = df[["StockCode", "Description"]].drop_duplicates(subset=["StockCode"])

    dim = products.merge(desc, on="StockCode", how="left")

    dim = dim.rename(columns={
        "ProductKey":   "product_key",
        "StockCode":    "product_id",
        "Description":  "product_name",
    })

    def categorize(name):
        name = str(name).upper()
        if any(k in name for k in ["HEART", "ROSE", "LOVE"]):    return "Romance"
        if any(k in name for k in ["CHRISTMAS", "XMAS"]):        return "Seasonal"
        if any(k in name for k in ["BAG", "TOTE", "PURSE"]):     return "Bags"
        if any(k in name for k in ["CANDLE", "LIGHT", "LAMP"]):  return "Lighting"
        if any(k in name for k in ["MUG", "CUP", "GLASS"]):      return "Drinkware"
        if any(k in name for k in ["FRAME", "SIGN", "PRINT"]):   return "Décor"
        if any(k in name for k in ["BOX", "TIN", "JAR"]):        return "Storage"
        if any(k in name for k in ["CAKE", "FOOD", "TEA"]):      return "Food & Drink"
        return "General"

    dim["category"] = dim["product_name"].apply(categorize)
    logger.info(f"DimProduct: {len(dim):,} rows")
    return dim

def build_dim_date(df: pd.DataFrame) -> pd.DataFrame:
    dim = df[["DateKey", "Date", "Day", "DayOfWeek", "Week",
              "Month", "Quarter", "Year", "IsWeekend"]].drop_duplicates(subset=["DateKey"])
    dim.columns = ["date_key", "full_date", "day", "day_of_week", "week",
                   "month", "quarter", "year", "is_weekend"]
    dim["month_name"] = pd.to_datetime(dim["full_date"]).dt.month_name()
    dim = dim.sort_values("date_key").reset_index(drop=True)
    logger.info(f"DimDate: {len(dim):,} rows")
    return dim

def build_dim_location(df: pd.DataFrame, locations: pd.DataFrame) -> pd.DataFrame:
    dim = locations.copy()
    dim.columns = ["country", "location_key"]

    # Basic region mapping
    eu = {"United Kingdom","Germany","France","Spain","Netherlands",
          "Belgium","Portugal","Sweden","Finland","Denmark","Norway",
          "Austria","Switzerland","Italy","Poland","Greece","Cyprus",
          "Czech Republic","Malta","Iceland","Lithuania","Latvia","Estonia"}
    dim["region"] = dim["country"].apply(
        lambda c: "Europe" if c in eu else
                  "North America" if c in {"United States","Canada"} else
                  "Asia Pacific" if c in {"Australia","Japan","Singapore"} else
                  "Other"
    )
    dim = dim[["location_key", "country", "region"]]
    logger.info(f"DimLocation: {len(dim):,} rows")
    return dim

def build_fact_sales(df: pd.DataFrame) -> pd.DataFrame:
    fact = df[[
        "Invoice", "CustomerKey", "ProductKey", "DateKey", "LocationKey",
        "Quantity", "Price", "Revenue", "Discount", "Profit", "OrderValue"
    ]].copy()
    fact.columns = [
        "invoice_id", "customer_key", "product_key", "date_key", "location_key",
        "quantity", "unit_price", "revenue", "discount", "profit", "order_value"
    ]
    logger.info(f"FactSales: {len(fact):,} rows")
    return fact

# ── 6. Save all tables ────────────────────────────────────────────────────────

def save_tables(dim_customer, dim_product, dim_date, dim_location, fact_sales):
    out = Path(config["paths"]["processed_dir"])
    tables = {
        "dim_customer": dim_customer,
        "dim_product":  dim_product,
        "dim_date":     dim_date,
        "dim_location": dim_location,
        "fact_sales":   fact_sales,
    }
    for name, df in tables.items():
        path = out / f"{name}.csv"
        df.to_csv(path, index=False)
        logger.info(f"Saved {name}.csv — {len(df):,} rows")

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    df = load_raw()
    df = clean(df)
    df = enrich(df)
    df, customers, products, locations = add_surrogate_keys(df)

    dim_customer = build_dim_customer(df, customers)
    dim_product  = build_dim_product(df, products)
    dim_date     = build_dim_date(df)
    dim_location = build_dim_location(df, locations)
    fact_sales   = build_fact_sales(df)

    save_tables(dim_customer, dim_product, dim_date, dim_location, fact_sales)
    logger.info("Transform complete ✓")