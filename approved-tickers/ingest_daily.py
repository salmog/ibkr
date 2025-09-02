#!/usr/bin/env python3
from ib_insync import IB, Stock, util
import pandas as pd
import sqlalchemy as sa
import time

# =========================
# Config
# =========================
IB_HOST = '127.0.0.1'
IB_PORT = 4001
CLIENT_ID = 1
CSV_FILE = 'tickers.csv'  # CSV file with column 'symbol'

DB_USER = 'pguser'
DB_PASS = 'pgpass'
DB_HOST = '127.0.0.1'
DB_PORT = '5432'
DB_NAME = 'stockdb'

RATE_LIMIT_SEC = 0.5  # seconds between tickers

# =========================
# Connect to IB
# =========================
ib = IB()
ib.connect(IB_HOST, IB_PORT, clientId=CLIENT_ID)
print("Connected to IB Gateway")

# =========================
# Connect to PostgreSQL
# =========================
engine = sa.create_engine(
    f'postgresql+psycopg2://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}'
)

# =========================
# Load tickers
# =========================
tickers = pd.read_csv(CSV_FILE)['symbol'].drop_duplicates().tolist()

# =========================
# Process each ticker
# =========================
for symbol in tickers:
    print(f"Processing {symbol}...")

    # Get last fetched date
    with engine.connect() as conn:
        result = conn.execute(sa.text(
            "SELECT last_price_date FROM tickers WHERE symbol=:symbol"
        ), {"symbol": symbol})
        last_date = result.scalar()
        if last_date is None:
            last_date = pd.Timestamp('2000-01-01').date()
        else:
            last_date = pd.Timestamp(str(last_date)).date()

    # Fetch daily OHLCV from IB
    contract = Stock(symbol, 'SMART', 'USD')
    bars = ib.reqHistoricalData(
        contract,
        endDateTime='',
        durationStr='10 Y',
        barSizeSetting='1 day',
        whatToShow='TRADES',
        useRTH=True
    )

    if not bars:
        print(f"  No data returned for {symbol}, skipping...")
        continue

    df = util.df(bars)[['date', 'open', 'high', 'low', 'close', 'volume']]
    df.rename(columns={'date': 'ts'}, inplace=True)
    df['ts'] = pd.to_datetime(df['ts']).dt.date
    df = df[df['ts'] > last_date]

    if df.empty:
        print(f"  No new data for {symbol}")
    else:
        # Upsert into price_daily
        with engine.begin() as conn:
            for _, row in df.iterrows():
                conn.execute(sa.text("""
                    INSERT INTO price_daily (symbol, ts, open, high, low, close, volume, source)
                    VALUES (:symbol, :ts, :open, :high, :low, :close, :volume, 'IBKR')
                    ON CONFLICT (symbol, ts) DO UPDATE
                    SET open=EXCLUDED.open,
                        high=EXCLUDED.high,
                        low=EXCLUDED.low,
                        close=EXCLUDED.close,
                        volume=EXCLUDED.volume,
                        source='IBKR'
                """), dict(row, symbol=symbol))

    # Update ticker_status / last_ingest_ts
    with engine.begin() as conn:
        conn.execute(sa.text("""
            INSERT INTO ticker_status(symbol, last_ingest_ts)
            VALUES (:symbol, now())
            ON CONFLICT(symbol) DO UPDATE
            SET last_ingest_ts = EXCLUDED.last_ingest_ts
        """), {"symbol": symbol})

    time.sleep(RATE_LIMIT_SEC)

print("=== Ingestion complete ===")
