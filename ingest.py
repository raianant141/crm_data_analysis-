# importing the essential libraries for ingesting the data into SQL database(PostgresSQL)
from sqlalchemy import create_engine
import pandas as pd
import numpy as np
import time
import logging

# defining a  function for creating a connection with the Database
def get_engine():
    try:
        engine = create_engine('postgresql+psycopg2://postgres:daring_baaz1@localhost:5432/crm_db')
        with engine.begin() as conn:
            logging.info("Connected to PostgresSQL")
    except Exception as e:
        logging.info(f"Connection failed-- {e}")
        raise
    return engine

# defining a  function for light cleaning a dataset
def clean_df(df):
    df.columns = df.columns.str.strip().str.lower()
    df = df.drop_duplicates()
    for col in df.columns:
        if 'date' in col:
            df[col] = pd.to_datetime(df[col], errors='coerce')
    return df

# defining a function for ingesting the data into the database
def load_data(engine, table, path):
    start = time.perf_counter()
    try:
        df = pd.read_csv(path)
        df = clean_df(df)
        df.to_sql(table, engine, index= False, if_exists = 'replace')
        loaded = pd.read_sql(f"SELECT COUNT(*) FROM {table}", engine).iloc[0,0]
        if loaded == len(df):
            logging.info(f"{table}: {loaded} rows in {time.perf_counter()-start:.1f}s")
        else:
            logging.warning(f"{table}: expected {len(df)}, DB has {loaded}")
    except FileNotFoundError :
        logging.error(f"{table}: failed at {path} ")
    except Exception as e:
        logging.error(f'{table} failed -- {e}')

#
def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", handlers=[
    logging.FileHandler("ingest.log", encoding="utf-8"),
    logging.StreamHandler()])
    
    engine = get_engine()

    #  writing the table name from the file path 
    files = {
    "customers":               "customers.csv",
    "subscription_history":    "subscription_history.csv"
    }
    start = time.perf_counter()
    for table, path in files.items():
        load_data(engine, table, path)
    logging.info("Ingestion Complete")
    logging.info(f"Ingestion complete in {time.perf_counter() - start:.1f}s")

if __name__ == "__main__":
    main()

    

    