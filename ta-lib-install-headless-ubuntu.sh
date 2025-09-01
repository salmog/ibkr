#!/bin/bash
set -e

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install build dependencies
sudo apt-get install -y build-essential wget curl \
    automake autoconf libtool pkg-config python3-venv

# Download TA-Lib source
cd /tmp
wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz

# Extract and build
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib
./configure --prefix=/usr
make
sudo make install

# Cleanup
cd ..
rm -rf ta-lib ta-lib-0.4.0-src.tar.gz

# Create virtual environment (replace path if you want)
cd ~
python3 -m venv ta-env
source ta-env/bin/activate

# Upgrade pip and install ta-lib wrapper
pip install --upgrade pip wheel setuptools
pip install ta-lib

echo "✅ TA-Lib installed inside virtualenv 'ta-env'"
echo "Activate it with: source ~/ta-env/bin/activate"
