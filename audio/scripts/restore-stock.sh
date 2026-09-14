#!/bin/bash
# Remove everything the MacBook8,1 audio setup installed and return to Debian's stock audio
# (headphones and microphone work, internal speakers silent).
#   sudo bash audio/scripts/restore-stock.sh     then reboot
# Nothing is deleted: removed files are moved to /var/backups/mb81-audio/restore-<timestamp>/.
# Works from any installed kernel (e.g. an older kernel picked in GRUB "Advanced options").
set -euo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
Q=/var/backups/mb81-audio/restore-$STAMP
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
mkdir -p "$Q"
exec > >(tee -a "$Q/restore.log") 2>&1
echo "== MacBook8,1 audio restore $STAMP (running $(uname -r))"

moved=0
quarantine() {
  local src=$1 dest="$Q$1"
  mkdir -p "$(dirname "$dest")"
  mv "$src" "$dest"
  echo "  moved $src"
  moved=1
}

echo "[1/3] speaker driver modules (all kernels)"
for d in /lib/modules/*/updates/mb81-speakers; do
  [ -d "$d" ] || continue
  k=$(basename "$(dirname "$(dirname "$d")")")
  quarantine "$d"
  depmod -a "$k"
  echo "  $k: snd_hda_codec_cirrus -> $(modinfo -k "$k" -n snd_hda_codec_cirrus)"
done

echo "[2/3] snd_hda_intel options"
[ -e /etc/modprobe.d/mb81-speakers.conf ] && quarantine /etc/modprobe.d/mb81-speakers.conf
# Do not touch other files: list any remaining options so a human can judge them.
remaining=$(grep -rnE '^[[:space:]]*options[[:space:]]+snd[_-]hda[_-]intel' /etc/modprobe.d/ 2>/dev/null || true)
[ -n "$remaining" ] && { echo "  other snd_hda_intel options still present (left unchanged):"; echo "$remaining" | sed 's/^/    /'; }

echo "[3/3] user-level PipeWire/WirePlumber files"
U=${SUDO_USER:-}
if [ -n "$U" ] && [ "$U" != root ]; then
  UH=$(getent passwd "$U" | cut -d: -f6)
  for f in "$UH/.config/wireplumber/wireplumber.conf.d/51-mb81-speakers.conf" \
           "$UH/.config/pipewire/pipewire.conf.d/52-mb81-speaker-eq.conf" \
           "$UH/.config/systemd/user/default.target.wants/mb81-audio-autoswitch.service" \
           "$UH/.config/systemd/user/mb81-audio-autoswitch.service" \
           "$UH/.local/bin/mb81-audio-autoswitch"; do
    if [ -e "$f" ] || [ -L "$f" ]; then quarantine "$f"; fi
  done
else
  echo "  run via sudo from your normal user to also remove the per-user PipeWire files"
fi

echo
[ "$moved" = 1 ] && echo "DONE. Files are in $Q. Reboot now." || echo "Nothing to remove; already stock."
echo "After reboot, check: bash audio/scripts/verify-stock.sh"
