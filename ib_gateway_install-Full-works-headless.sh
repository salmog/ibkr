#!/usr/bin/env bash
set -euo pipefail

# 1. Create user shay with sudo and SSH keys
if ! id -u shay >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" shay
    usermod -aG sudo shay
    mkdir -p /home/shay/.ssh
    cp -f /root/.ssh/authorized_keys /home/shay/.ssh/ 2>/dev/null || true
    chown -R shay:shay /home/shay/.ssh
    chmod 700 /home/shay/.ssh
    chmod 600 /home/shay/.ssh/authorized_keys || true
fi

# 2. Install packages
apt update && apt upgrade -y
apt install -y xvfb openbox xterm novnc websockify x11vnc wget unzip

# 3. Passwords
echo "shay:1" | chpasswd
mkdir -p /home/shay/.vnc
echo "2" > /home/shay/.vnc/novnc_passwd
chown -R shay:shay /home/shay/.vnc
chmod 600 /home/shay/.vnc/novnc_passwd
sudo -u shay x11vnc -storepasswd 2 /home/shay/.vnc/passwd

# 4. Xvfb service
tee /etc/systemd/system/xvfb.service >/dev/null <<EOF
[Unit]
Description=Xvfb headless display :1
After=network.target

[Service]
User=shay
Environment=DISPLAY=:1
ExecStart=/usr/bin/Xvfb :1 -screen 0 1280x800x24 -nolisten tcp -ac
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 5. Openbox service (with xterm)
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

# 6. x11vnc (backend for noVNC)
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

# 7. noVNC
tee /etc/systemd/system/novnc.service >/dev/null <<EOF
[Unit]
Description=noVNC server on :1
After=x11vnc.service
Requires=x11vnc.service

[Service]
User=shay
Environment=DISPLAY=:1
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 6080 localhost:5901
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 8. Enable core services
systemctl daemon-reload
systemctl enable --now xvfb.service openbox.service x11vnc.service novnc.service

# 9. Download IB Gateway installer
sudo -u shay bash -c '
cd ~
if [ ! -f ibgateway.sh ]; then
  wget -q https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/ibgateway-stable-standalone-linux-x64.sh -O ibgateway.sh
  chmod u+x ibgateway.sh
fi
'

# 10. Launcher for IB Gateway
sudo -u shay bash -c 'cat > ~/start-ibgateway.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:1
ulimit -n 8192
exec \$HOME/Jts/ibgateway/\$(ls -1 \$HOME/Jts/ibgateway | sort -V | tail -n1)/ibgateway
EOF
chmod +x ~/start-ibgateway.sh
'

# 11. Systemd service for IB Gateway
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

systemctl daemon-reload
systemctl enable ibgateway.service

echo "=================================================="
echo "✅ Setup complete."
echo "Access noVNC at: http://<SERVER_IP>:6080/vnc.html"
echo "Login password: 2"
echo "User shay password: 1"
echo
echo Run installer once via noVNC as user *shay*: su shay
echo Accept defaults (installer will create ~/Jts/ibgateway/<version>).
echo su - shay -c "ln -sfn /home/shay/Jts/ibgateway/<version> /home/shay/Jts/ibgateway/current"
echo "➡️  Run installer once via noVNC': DISPLAY=:1 ~/ibgateway.sh'"
echo "   '(accept defaults so ~/Jts is created)'"
echo "➡️  After that, IB Gateway auto-starts at boot via systemd."
echo "=================================================="
