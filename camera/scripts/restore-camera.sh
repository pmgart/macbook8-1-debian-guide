#!/bin/bash
# Undo the FaceTime HD camera setup on MacBook8,1.
# Removes the DKMS module, firmware files, and modprobe blacklist.

set -euo pipefail

VER=0.7.0.1
FWDIR=/usr/lib/firmware/facetimehd
[ -d /usr/lib/firmware ] || FWDIR=/lib/firmware/facetimehd

echo "Removing DKMS module..."
dkms remove -m facetimehd -v "$VER" --all 2>/dev/null || true
rm -rf "/usr/src/facetimehd-$VER"

echo "Removing firmware..."
rm -rf "$FWDIR"

echo "Removing blacklist..."
rm -f /etc/modprobe.d/macbook81-facetimehd.conf

echo "Unloading module..."
modprobe -r facetimehd 2>/dev/null || true

echo "Camera removed. Reboot to restore stock behaviour."
