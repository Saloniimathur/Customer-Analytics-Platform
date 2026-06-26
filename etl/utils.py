import yaml
import logging
from loguru import logger
import snowflake.connector
from pathlib import Path

def load_config(config_path: str = "config/config.yaml") -> dict:
    with open(config_path, "r") as f:
        return yaml.safe_load(f)

def get_snowflake_connection(config: dict):
    sf = config["snowflake"]
    conn = snowflake.connector.connect(
        account=sf["account"],
        user=sf["user"],
        password=sf["password"],
        role=sf["role"],
        warehouse=sf["warehouse"],
        database=sf["database"],
        schema=sf["schema"],
    )
    logger.info("Snowflake connection established")
    return conn

# def setup_logger(log_level: str = "INFO"):
#     logger.remove()
#     logger.add(
#         "logs/etl_{time}.log",
#         rotation="10 MB",
#         level=log_level,
#         format="{time:YYYY-MM-DD HH:mm:ss} | {level} | {message}"
#     )
#     # logger.add(lambda msg: print(msg, end=""), level=log_level)
#     logger.add(lambda msg: print(msg.encode("utf-8", errors="replace").decode("utf-8"), end=""), level=log_level)
#     return logger

def setup_logger(log_level: str = "INFO"):
    from pathlib import Path
    Path("logs").mkdir(exist_ok=True)

    logger.remove()

    # File sink — UTF-8, no issues
    logger.add(
        "logs/etl_{time}.log",
        rotation="10 MB",
        level=log_level,
        encoding="utf-8",
        format="{time:YYYY-MM-DD HH:mm:ss} | {level} | {message}"
    )

    # Console sink — strip non-ASCII characters before printing
    def safe_print(msg):
        print(msg.encode("ascii", errors="replace").decode("ascii"), end="")

    logger.add(safe_print, level=log_level)
    return logger