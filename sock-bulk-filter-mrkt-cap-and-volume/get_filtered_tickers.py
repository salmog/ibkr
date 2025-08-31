#!/usr/bin/env python3
from ib_insync import IB, Stock, util
import pandas as pd
import time

IB_HOST = '127.0.0.1'
IB_PORT = 4001
CLIENT_ID = 2
OUTPUT_CSV = 'tickers.csv'
RATE_LIMIT_SEC = 0.5

ib = IB()
ib.connect(IB_HOST, IB_PORT, clientId=CLIENT_ID)
print("Connected to IB Gateway")

# --- Load NASDAQ list from file ---
df = pd.read_csv("nasdaq.csv", sep="|")
symbols = df['Symbol'].dropna().tolist()

print(f"Loaded {len(symbols)} NASDAQ tickers")

valid_symbols = []

for idx, sym in enumerate(symbols, start=1):
    try:
        contract = Stock(sym, 'SMART', 'USD')
        bars = ib.reqHistoricalData(
            contract,
            endDateTime='',
            durationStr='30 D',
            barSizeSetting='1 day',
            whatToShow='TRADES',
            useRTH=True
        )
        if not bars:
            print(f"[{idx}] {sym}: no data ❌")
            continue

        df_bars = util.df(bars)[['close','volume']]
        avg_price = df_bars['close'].mean()
        avg_volume = df_bars['volume'].mean()
        dollar_vol = avg_price * avg_volume

        if dollar_vol >= 25_000_000:
            valid_symbols.append(sym)
            print(f"[{idx}] {sym}: ${dollar_vol:,.0f} ✅")
        else:
            print(f"[{idx}] {sym}: ${dollar_vol:,.0f} ❌")

    except Exception as e:
        print(f"[{idx}] {sym}: error {e}")
    time.sleep(RATE_LIMIT_SEC)

pd.DataFrame(valid_symbols, columns=['symbol']).to_csv(OUTPUT_CSV, index=False)
print(f"Saved {len(valid_symbols)} tickers -> {OUTPUT_CSV}")
