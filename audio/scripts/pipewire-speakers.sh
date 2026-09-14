#!/bin/bash
# Add or remove the PipeWire outputs "MacBook Speakers" / "MacBook Headphones" / "MacBook Microphone".
# Run as your normal user, NO sudo. Requires the speaker driver (install-driver.sh + reboot).
#   bash audio/scripts/pipewire-speakers.sh install
#   bash audio/scripts/pipewire-speakers.sh remove
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
DIR=$HOME/.config/wireplumber/wireplumber.conf.d
CONF=$DIR/51-mb81-speakers.conf
[ "$(id -u)" != 0 ] || { echo "Run WITHOUT sudo (this configures your user's PipeWire)."; exit 1; }

case "${1:-}" in
  install)
    grep -q "CS4208 Speaker" /proc/asound/pcm || { echo "ABORT: no 'CS4208 Speaker' PCM. Install the driver and reboot first."; exit 1; }
    mkdir -p "$DIR"
    install -m 0644 "$REPO/audio/config/51-mb81-speakers.conf" "$CONF"
    echo "installed $CONF"
    ;;
  remove)
    rm -f "$CONF" && echo "removed $CONF"
    ;;
  *) echo "usage: $0 install|remove"; exit 1 ;;
esac

systemctl --user restart wireplumber pipewire pipewire-pulse
sleep 4
wpctl status | sed -n '/^Audio/,/^Video/p' | sed -n '/Sinks:/,/Filters:/p'
if [ "$1" = install ]; then
  if wpctl status | grep -q "MacBook Speakers"; then
    echo "OK: 'MacBook Speakers' exists. Select it in your desktop's sound settings (or: wpctl set-default <id>)."
  else
    echo "PROBLEM: 'MacBook Speakers' did not appear. Undo: bash $0 remove"
    exit 1
  fi
fi
