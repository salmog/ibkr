#!/usr/bin/env bash
set -euo pipefail

# --- 0. Update & upgrade system ---
apt update && apt upgrade -y

# --- 1. Add cronjob for auto updates ---
tee /etc/cron.d/apt-autoupdate >/dev/null <<EOF
0 */4 * * * root /usr/bin/apt update -y >> /var/log/apt-cron.log 2>&1
EOF

# --- 2. Create user shay with sudo + SSH ---
if ! id -u shay >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" shay
    usermod -aG sudo shay
    mkdir -p /home/shay/.ssh
    cp -f /root/.ssh/authorized_keys /home/shay/.ssh/ 2>/dev/null || true
    chown -R shay:shay /home/shay/.ssh
    chmod 700 /home/shay/.ssh
    chmod 600 /home/shay/.ssh/authorized_keys || true
fi

# --- 3. Install required packages ---
apt install -y xvfb openbox xterm novnc websockify x11vnc wget unzip

# --- 4. Passwords ---
echo "shay:1" | chpasswd
mkdir -p /home/shay/.vnc
echo "2" > /home/shay/.vnc/novnc_passwd
chown -R shay:shay /home/shay/.vnc
chmod 600 /home/shay/.vnc/novnc_passwd
sudo -u shay x11vnc -storepasswd 2 /home/shay/.vnc/passwd

# 5. Openbox service (with xterm + IB Gateway)
tee /etc/systemd/system/openbox.service >/dev/null <<'EOF'
[Unit]
Description=Openbox WM on :1
After=xvfb.service
Requires=xvfb.service

[Service]
User=shay
Environment=DISPLAY=:1
ExecStart=/bin/sh -c '
    /usr/bin/openbox --sm-disable &
    sleep 2
    /usr/bin/xterm &
    if [ -x /home/shay/start-ibgateway.sh ]; then
        /home/shay/start-ibgateway.sh &
    fi
    wait
'
Restart=always

[Install]
WantedBy=multi-user.target
EOF


# --- 6. Openbox service ---
tee /etc/systemd/system/openbox.service >/dev/null <<'EOF'
[Unit]
Description=Openbox WM on :1
After=xvfb.service
Requires=xvfb.service

[Service]
User=shay
Environment=DISPLAY=:1
ExecStart=/bin/sh -c '/usr/bin/openbox --sm-disable & exec /usr/bin/xterm'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- 7. x11vnc service ---
tee /etc/systemd/system/x11vnc.service >/dev/null <<EOF
[Unit]
Description=x11vnc on :1 (for noVNC)
After=openbox.service
Requires=openbox.service

[Service]
User=shay
Environment=DISPLAY=:1
ExecStart=/usr/bin/x11vnc -display :1 -rfbauth /home/shay/.vnc/passwd -rfbport 5901 -localhost -shared -forever -o /home/shay/.vnc/x11vnc.log
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- 8. noVNC service ---
sudo tee /etc/systemd/system/novnc.service >/dev/null <<EOF
[Unit]
Description=noVNC server on :1
After=x11vnc.service
Requires=x11vnc.service

[Service]
User=shay
Environment=DISPLAY=:1
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 6080 0.0.0.0:5901
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# --- 9. Enable base services ---
systemctl daemon-reload
systemctl enable --now xvfb.service openbox.service x11vnc.service novnc.service

# --- 10. Download & silent install IB Gateway ---
sudo -u shay bash -c '
cd ~
if [ ! -f ibgateway.sh ]; then
  wget -q https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/ibgateway-stable-standalone-linux-x64.sh -O ibgateway.sh
  chmod u+x ibgateway.sh
fi

# Silent install (no GUI clicks needed)
./ibgateway.sh -q -dir /home/shay/Jts

# Wait until installer creates at least one version folder
for i in {1..20}; do
  if [ -d ~/Jts/ibgateway ] && [ "$(ls -1 ~/Jts/ibgateway | wc -l)" -gt 0 ]; then
    break
  fi
  echo "⏳ Waiting for IB Gateway installation to finish ($i/20)..."
  sleep 3
done

# Symlink "current" to latest version
if [ -d ~/Jts/ibgateway ]; then
  latest=$(ls -1 ~/Jts/ibgateway | sort -V | tail -n1)
  ln -sfn /home/shay/Jts/ibgateway/$latest /home/shay/Jts/ibgateway/current
fi
'


# --- 11. Launcher for IB Gateway ---
sudo -u shay bash -c 'cat > ~/start-ibgateway.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:1
ulimit -n 8192
exec \$HOME/Jts/ibgateway/current/ibgateway
EOF
chmod +x ~/start-ibgateway.sh
'

# --- 12. Systemd service for IB Gateway ---
tee /etc/systemd/system/ibgateway.service >/dev/null <<EOF
[Unit]
Description=IBKR Gateway (headless)
After=novnc.service network-online.target
Wants=network-online.target

[Service]
User=shay
Environment=DISPLAY=:1
WorkingDirectory=/home/shay
LimitNOFILE=8192
ExecStart=/home/shay/start-ibgateway.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# --- 13. Finalize ---
systemctl daemon-reload
systemctl enable ibgateway.service

echo "=================================================="
echo "✅ Setup complete."
echo "Access noVNC at: http://<SERVER_IP>:6080/vnc.html"
echo "noVNC password: 2"
echo "User 'shay' password: 1"
echo
echo "➡️ IB Gateway installed silently to ~/Jts"
echo "➡️ Symlink: ~/Jts/ibgateway/current → latest version"
echo "➡️ Service: ibgateway.service enabled (autostarts at boot)"
echo
echo "⚠️ IMPORTANT: First time, log in once via noVNC so ibgateway.ini is created."
echo "   After that, service will run fully headless."
echo "=================================================="
