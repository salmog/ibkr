#✅ Here’s a full working script (fetch_etfs.py) that:

#Downloads the official ETF universe from NasdaqTrader.

#Cleans it into a DataFrame with Symbol + Name.

#Fetches 30-day history from IBKR.

#Filters ETFs by ≥ $25M avg dollar volume.

#Separates leveraged/inverse ETFs automatically.

#Saves results into etfs.csv and leveraged_etfs.csv.



#!/usr/bin/env python3
from ib_insync import IB, Stock, util
import pandas as pd
import time, re, requests
from io import StringIO

# =========================
# Config
# =========================
IB_HOST = '127.0.0.1'
IB_PORT = 4001
CLIENT_ID = 3
RATE_LIMIT_SEC = 0.5
OUTPUT_ETFS = 'etfs.csv'
OUTPUT_LEVERAGED = 'leveraged_etfs.csv'

# =========================
# Connect to IB Gateway
# =========================
ib = IB()
ib.connect(IB_HOST, IB_PORT, clientId=CLIENT_ID)
print("Connected to IB Gateway")

# =========================
# Step 1: Download ETF universe from NasdaqTrader
# =========================
url = "https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt"
print("Downloading ETF list from NasdaqTrader...")
resp = requests.get(url)
resp.raise_for_status()

# Parse CSV from response
df = pd.read_csv(StringIO(resp.text), sep="|")
df = df.rename(columns={"ACT Symbol": "Symbol", "Security Name": "Name"})

# Filter out NaN and test row
df = df[df["Symbol"].notna()]
df = df[df["Symbol"] != "File Creation Time"]

symbols = df["Symbol"].tolist()
print(f"Loaded {len(symbols)} tickers from NasdaqTrader")

# =========================
# Step 2: Liquidity filter
# =========================
valid_etfs = []
leveraged_etfs = []

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
            valid_etfs.append(sym)
            name = df.loc[df['Symbol'] == sym, 'Name'].values[0]

            # Detect leveraged/inverse by name
            if re.search(r'(Ultra|UltraPro|2x|3x|Bull|Bear|Direxion|ProShares)', name, re.IGNORECASE):
                leveraged_etfs.append(sym)
                print(f"[{idx}] {sym} ({name}): ${dollar_vol:,.0f} ✅ LEVERAGED")
            else:
                print(f"[{idx}] {sym} ({name}): ${dollar_vol:,.0f} ✅")
        else:
            print(f"[{idx}] {sym}: ${dollar_vol:,.0f} ❌")

    except Exception as e:
        print(f"[{idx}] {sym}: error {e}")
    time.sleep(RATE_LIMIT_SEC)

# =========================
# Step 3: Save results
# =========================
pd.DataFrame(valid_etfs, columns=['symbol']).to_csv(OUTPUT_ETFS, index=False)
pd.DataFrame(leveraged_etfs, columns=['symbol']).to_csv(OUTPUT_LEVERAGED, index=False)

print(f"Saved {len(valid_etfs)} ETFs -> {OUTPUT_ETFS}")
print(f"Saved {len(leveraged_etfs)} Leveraged ETFs -> {OUTPUT_LEVERAGED}")
