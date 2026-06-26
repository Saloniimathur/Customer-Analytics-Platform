import pandas as pd
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas
from pathlib import Path
from tqdm import tqdm
from utils import load_config, setup_logger, get_snowflake_connection

config = load_config()
logger = setup_logger(config["etl"]["log_level"])

PROCESSED_DIR = Path(config["paths"]["processed_dir"])

# Load order matters — dims before fact (foreign keys)
LOAD_ORDER = [
    ("dim_customer",  "DIM_CUSTOMER"),
    ("dim_product",   "DIM_PRODUCT"),
    ("dim_date",      "DIM_DATE"),
    ("dim_location",  "DIM_LOCATION"),
    ("fact_sales",    "FACT_SALES"),
]

def load_csv(filename: str) -> pd.DataFrame:
    path = PROCESSED_DIR / f"{filename}.csv"
    df = pd.read_csv(path)
    # Snowflake write_pandas requires uppercase column names
    df.columns = [c.upper() for c in df.columns]
    return df

def truncate_table(conn, table: str):
    conn.cursor().execute(f"TRUNCATE TABLE IF EXISTS {table}")
    logger.info(f"Truncated {table}")

def load_table(conn, df: pd.DataFrame, table: str):
    logger.info(f"Loading {table} — {len(df):,} rows...")

    success, num_chunks, num_rows, output = write_pandas(
        conn=conn,
        df=df,
        table_name=table,
        database=config["snowflake"]["database"],
        schema=config["snowflake"]["schema"],
        chunk_size=config["etl"]["batch_size"],
        auto_create_table=False,
        overwrite=False,
    )

    if success:
        logger.info(f"Loaded {table} — {num_rows:,} rows in {num_chunks} chunks")
    else:
        logger.error(f"Failed to load {table}")
        raise RuntimeError(f"write_pandas failed for {table}")

def verify_counts(conn):
    logger.info("Verifying row counts in Snowflake...")
    cur = conn.cursor()
    for _, table in LOAD_ORDER:
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        count = cur.fetchone()[0]
        logger.info(f"  {table:20s} {count:>10,} rows")

def run_load():
    conn = get_snowflake_connection(config)

    try:
        for filename, table in tqdm(LOAD_ORDER, desc="Loading tables"):
            df = load_csv(filename)
            truncate_table(conn, table)
            load_table(conn, df, table)

        verify_counts(conn)
        logger.info("Load complete")

    except Exception as e:
        logger.error(f"Load failed: {e}")
        raise
    finally:
        conn.close()
        logger.info("Snowflake connection closed")

if __name__ == "__main__":
    run_load()