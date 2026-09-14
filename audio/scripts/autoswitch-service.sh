#!/bin/bash
# Install or remove the user service that switches the default output when headphones are plugged in/out.
# Run as your user, NO sudo:
#   bash audio/scripts/autoswitch-service.sh install
#   bash audio/scripts/autoswitch-service.sh remove
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
UNIT_DIR=$HOME/.config/systemd/user
UNIT=$UNIT_DIR/mb81-audio-autoswitch.service
BIN=$HOME/.local/bin/mb81-audio-autoswitch
[ "$(id -u)" != 0 ] || { echo "Run WITHOUT sudo."; exit 1; }

case "${1:-}" in
  install)
    install -D -m 0755 "$REPO/audio/scripts/audio-autoswitch.sh" "$BIN"
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT" <<EOF
[Unit]
Description=MacBook8,1 switch audio output between headphones and speakers
After=wireplumber.service pipewire.service
Wants=wireplumber.service

[Service]
ExecStart=$BIN
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now mb81-audio-autoswitch.service
    sleep 3
    systemctl --user --no-pager status mb81-audio-autoswitch.service | head -8
    ;;
  remove)
    systemctl --user disable --now mb81-audio-autoswitch.service 2>/dev/null
    rm -f "$UNIT" "$BIN"
    systemctl --user daemon-reload
    echo "removed mb81-audio-autoswitch.service"
    ;;
  *) echo "usage: $0 install|remove"; exit 1 ;;
esac
