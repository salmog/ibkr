# Ran talib script first as user shay!! :
# sudo nano talib.sh
# sudo bash talib.sh
#
#Here's the final fixed version of your setup_env.sh script, fully cleaned and updated based on:

#✅ Running as root

#✅ Installs Docker Engine + Compose plugin

#✅ Uses docker compose (not docker-compose)

#✅ Creates project at /home/shay/py-env-ibkr

#✅ Uses 5 sample tickers only

#✅ Skips TA-Lib C install (already done)

#✅ Installs Python deps in new venv (venv-ibkr)

#✅ Prepares Docker + TimescaleDB + Redis

#✅ Creates .env and database schema

# ✅ To save and run: 
#sudo nano /root/setup_env.sh
# sudo chmod +x /root/setup_env.sh
# Run the script as root:
# sudo bash /root/setup_env.sh
# Reboot to apply Docker group change

# Then log in as shay, activate env, and ingest:
# su - shay
# cd ~/py-env-ibkr
# source venv-ibkr/bin/activate
# python ingest_daily.py


#!/bin/bash
set -euo pipefail

USER=shay
HOME_DIR=/home/$USER
PROJECT_DIR=$HOME_DIR/py-env-ibkr
VENV_DIR=$PROJECT_DIR/venv-ibkr
DOCKER_COMPOSE_FILE=$PROJECT_DIR/docker-compose.yml
SCHEMA_FILE=$PROJECT_DIR/schema.sql
TICKERS_FILE=$PROJECT_DIR/tickers.csv

echo "======================================"
echo "STEP 0: Install Docker + Compose Plugin"
echo "======================================"

# Remove older versions
apt-get remove -y docker docker-engine docker.io containerd runc || true

# Install dependencies
apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
ARCH=$(dpkg --print-architecture)
RELEASE=$(lsb_release -cs)
echo \
  "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $RELEASE stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker and Compose plugin
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
usermod -aG docker $USER
systemctl enable docker

echo "======================================"
echo "STEP 1: Create project directory and venv"
echo "======================================"
mkdir -p $PROJECT_DIR
chown -R $USER:$USER $PROJECT_DIR

sudo -u $USER bash -c "
  python3 -m venv $VENV_DIR
  $VENV_DIR/bin/pip install --upgrade pip wheel setuptools
  $VENV_DIR/bin/pip install ib_insync pandas sqlalchemy psycopg2-binary python-dotenv ta-lib
"

echo "======================================"
echo "STEP 2: Setup Docker Compose (TimescaleDB + Redis)"
echo "======================================"
cat > $DOCKER_COMPOSE_FILE <<EOL
version: '3.8'
services:
  timescaledb:
    image: timescale/timescaledb:latest-pg14
    environment:
      POSTGRES_USER: pguser
      POSTGRES_PASSWORD: pgpass
      POSTGRES_DB: stockdb
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
  redis:
    image: redis:7
    ports:
      - "6379:6379"
    volumes:
      - redisdata:/data
volumes:
  pgdata: {}
  redisdata: {}
EOL

chown $USER:$USER $DOCKER_COMPOSE_FILE

sudo -u $USER bash -c "
  cd $PROJECT_DIR
  docker compose up -d
"

echo "======================================"
echo "STEP 3: Setup TimescaleDB Schema"
echo "======================================"
cat > $SCHEMA_FILE <<EOL
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

CREATE TABLE IF NOT EXISTS tickers (
  symbol TEXT PRIMARY KEY,
  added_ts TIMESTAMPTZ DEFAULT now(),
  last_price_date DATE
);

CREATE TABLE IF NOT EXISTS price_daily (
  symbol TEXT NOT NULL,
  ts DATE NOT NULL,
  open DOUBLE PRECISION,
  high DOUBLE PRECISION,
  low DOUBLE PRECISION,
  close DOUBLE PRECISION,
  volume BIGINT,
  source TEXT,
  PRIMARY KEY (symbol, ts)
);

SELECT create_hypertable('price_daily','ts', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS ticker_status (
  symbol TEXT PRIMARY KEY,
  last_ingest_ts TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_price_daily_symbol_ts ON price_daily(symbol, ts DESC);
EOL

chown $USER:$USER $SCHEMA_FILE

CONTAINER_ID=$(docker ps --filter "name=py-env-ibkr-timescaledb-1" -q)
if [ -z "$CONTAINER_ID" ]; then
    echo "❌ TimescaleDB container not found. Exiting."
    exit 1
fi

echo "⏳ Waiting for TimescaleDB to be ready..."
until docker exec -i $CONTAINER_ID pg_isready -U pguser -d stockdb > /dev/null 2>&1; do
    sleep 2
done

docker exec -i $CONTAINER_ID psql -U pguser -d stockdb < $SCHEMA_FILE
echo "✅ TimescaleDB schema created"


echo "======================================"
echo "STEP 4: Create tickers.csv (5 tickers only)"
echo "======================================"
if [ ! -f "$TICKERS_FILE" ]; then
  cat > $TICKERS_FILE <<EOL
symbol
AAPL
MSFT
GOOG
AMZN
TSLA
EOL
  chown $USER:$USER $TICKERS_FILE
fi

echo "======================================"
echo "STEP 5: Create .env file"
echo "======================================"
cat > $PROJECT_DIR/.env <<EOL
IB_HOST=127.0.0.1
IB_PORT=4001
CLIENT_ID=1
CSV_FILE=$TICKERS_FILE
DB_USER=pguser
DB_PASS=pgpass
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=stockdb
RATE_LIMIT_SEC=0.6
EOL

chown $USER:$USER $PROJECT_DIR/.env
chmod 600 $PROJECT_DIR/.env

echo "======================================"
echo "✅ Environment ready"
echo "- Project directory: $PROJECT_DIR"
echo "- Virtualenv: $VENV_DIR"
echo "- TimescaleDB running on port 5432"
echo "- Redis running on port 6379"
echo "- tickers.csv created (5 symbols)"
echo
echo "Next steps:"
echo "1. su - $USER"
echo "2. source $VENV_DIR/bin/activate"
echo "3. Place ingest_daily.py in $PROJECT_DIR"
echo "4. Run: python ingest_daily.py"
