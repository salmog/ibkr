#!/usr/bin/env bash
# enable-novnc-https.sh
# Run as root

set -euo pipefail

# Variables
CERT_DIR=/etc/novnc/certs
SERVICE_FILE=/etc/systemd/system/novnc.service
USER=shay
IP_ADDRESS=$(hostname -I | awk '{print $1}')
PORT=6080
VNC_PORT=5901

# Make sure cert directory exists
mkdir -p "$CERT_DIR"
chown -R $USER:$USER "$CERT_DIR"
chmod 600 "$CERT_DIR"/* || true

# Update systemd service
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=noVNC server on :1
After=x11vnc.service
Requires=x11vnc.service

[Service]
User=$USER
Environment=DISPLAY=:1
ExecStart=/usr/bin/websockify --web /usr/share/novnc/ \\
  --cert=$CERT_DIR/server.crt \\
  --key=$CERT_DIR/server.key \\
  $PORT localhost:$VNC_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload and restart service
systemctl daemon-reload
systemctl restart novnc

echo "✅ noVNC HTTPS enabled on https://$IP_ADDRESS:$PORT/vnc.html"

<<COMMENT
_____________________________
manual way:
1	sudo mkdir -p /etc/novnc/certs	Ensure cert directory exists
2	sudo cp server.crt server.key ca.crt /etc/novnc/certs/	Copy your certs
3	sudo chown -R shay:shay /etc/novnc/certs	Give shay ownership
4	sudo chmod 600 /etc/novnc/certs/*	Restrict permissions
5	Edit systemd file	sudo nano /etc/systemd/system/novnc.service and set:
ini ExecStart=/usr/bin/websockify --web /usr/share/novnc/ --cert=/etc/novnc/certs/server.crt --key=/etc/novnc/certs/server.key 6080 localhost:5901
6	Reload systemd	sudo systemctl daemon-reload
7	Restart noVNC	sudo systemctl restart novnc
8	Check logs	sudo journalctl -u novnc -n 50 --no-pager
9	Test in browser	https://<SERVER_IP>:6080/vnc.html
COMMENT
