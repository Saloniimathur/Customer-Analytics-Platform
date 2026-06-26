import pandas as pd
from pathlib import Path
from tqdm import tqdm
from utils import load_config, setup_logger

config = load_config()
logger = setup_logger(config["etl"]["log_level"])

def extract() -> pd.DataFrame:
    raw_path = Path(config["paths"]["raw_data"])
    logger.info(f"Reading Excel file: {raw_path}")

    sheets = ["Year 2009-2010", "Year 2010-2011"]
    frames = []

    for sheet in tqdm(sheets, desc="Loading sheets"):
        df = pd.read_excel(raw_path, sheet_name=sheet, engine="openpyxl")
        df["source_sheet"] = sheet
        logger.info(f"Sheet '{sheet}': {len(df):,} rows loaded")
        frames.append(df)

    df_raw = pd.concat(frames, ignore_index=True)
    logger.info(f"Combined dataset: {len(df_raw):,} rows, {df_raw.shape[1]} columns")

    # Sanity checks
    logger.info(f"Columns: {list(df_raw.columns)}")
    logger.info(f"Date range: {df_raw['InvoiceDate'].min()} → {df_raw['InvoiceDate'].max()}")
    logger.info(f"Null counts:\n{df_raw.isnull().sum()}")
    logger.info(f"Unique customers: {df_raw['Customer ID'].nunique():,}")
    logger.info(f"Unique products: {df_raw['StockCode'].nunique():,}")

    # Save raw combined
    out_path = Path(config["paths"]["processed_dir"]) / "raw_combined.csv"
    df_raw.to_csv(out_path, index=False)
    logger.info(f"Raw combined saved to {out_path}")

    return df_raw

if __name__ == "__main__":
    df = extract()
    print(df.head())
    print(df.dtypes)