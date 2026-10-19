#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" != 0 ]]; then
  echo "Run this installer as root" >&2
  exit 1
fi
install -d -m 755 /opt/tosub2api
install -m 755 "$(dirname "$0")/server-update.sh" /opt/tosub2api/server-update.sh

cat > /etc/systemd/system/tosub2api-update.service <<'UNIT'
[Unit]
Description=Check GitHub and deploy toSub2 updates
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/tosub2api/server-update.sh
TimeoutStartSec=15min
UNIT

cat > /etc/systemd/system/tosub2api-update.timer <<'UNIT'
[Unit]
Description=Check for toSub2 updates every two minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Persistent=true
Unit=tosub2api-update.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now tosub2api-update.timer
systemctl start tosub2api-update.service
