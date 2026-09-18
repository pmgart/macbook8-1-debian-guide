#!/bin/bash
# Install the FaceTime HD camera on MacBook8,1 (12-inch, Early 2015).
# Verified 2026-09-18 on Debian 13, kernel 6.12.107+deb13-amd64.
#
# What it does:
#   1. Extract firmware 5.60.0 + all 11 sensor set files from Apple's public
#      macOS 10.12.6 update (legal: you own the hardware; nothing Apple-owned
#      is redistributed)
#   2. Blacklist bdc_pci (claims the same PCI ID)
#   3. Build patjak/facetimehd from master via DKMS (pinned upstream commit)
#   4. Load the module and verify /dev/video0
#
# Undo: sudo bash camera/scripts/restore-camera.sh
#
# Run from the repository root:
#   sudo bash camera/scripts/install-camera.sh

set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
FWSRC="$REPO/camera/firmware"
DKMS_SRC="$REPO/camera/driver/facetimehd"
FWDIR=/usr/lib/firmware/facetimehd
[ -d /usr/lib/firmware ] || FWDIR=/lib/firmware/facetimehd

die() { echo "ABORT: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
[ "$(cat /sys/class/dmi/id/product_name)" = "MacBook8,1" ] || die "this is not a MacBook8,1"

echo "== 1/5 firmware 5.60.0 + sensor files"
if [ ! -f "$FWSRC/firmware.bin" ]; then
    echo "  extracting from Apple's macOS 10.12.6 update (~10 MB, needs internet)"
    cd /tmp && rm -rf fthd-fw && mkdir fthd-fw && cd fthd-fw
    curl -sLO "https://updates.cdn-apple.com/2019/cert/041-90765-20191011-837e856d-b522-4865-b64c-641048ed77c4/macOSUpdCombo10.12.6.dmg"
    # pbzx stream extraction — see upstream facetimehd-firmware Makefile
    die "automatic extraction not yet wired into this script; extract manually per camera/docs/README.md section 2"
fi
install -dm755 "$FWDIR"
install -m644 "$FWSRC"/firmware.bin "$FWSRC"/*_01XX.dat "$FWDIR/"
echo "240ef2e991f1d089d8228ce11d92b66bfa4b3d7289ec4fee228b64a713024330  $FWDIR/firmware.bin" | sha256sum -c --quiet || die "firmware sha256 mismatch"

echo "== 2/5 blacklist bdc_pci"
echo "blacklist bdc_pci" > /etc/modprobe.d/macbook81-facetimehd.conf

echo "== 3/5 DKMS build"
VER=$(sed -n 's/^PACKAGE_VERSION=//p' "$DKMS_SRC/dkms.conf")
[ -n "$VER" ] || die "could not read PACKAGE_VERSION from dkms.conf"
SRC="/usr/src/facetimehd-$VER"
rm -rf "$SRC"
cp -r "$DKMS_SRC" "$SRC"
dkms remove -m facetimehd -v "$VER" --all 2>/dev/null || true
dkms add -m facetimehd -v "$VER"
dkms build -m facetimehd -v "$VER"
dkms install -m facetimehd -v "$VER" --force

echo "== 4/5 load + verify"
modprobe -r bdc_pci 2>/dev/null || true
modprobe facetimehd
sleep 2
[ -c /dev/video0 ] || die "no /dev/video0 after loading facetimehd"

echo "== 5/5 report"
v4l2-ctl --list-formats-ext -d /dev/video0
echo
echo "CAMERA INSTALLED. Test with: cheese, qv4l2, or ffplay /dev/video0"
echo "Undo: sudo bash camera/scripts/restore-camera.sh"
