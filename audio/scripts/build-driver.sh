#!/bin/bash
# Build the MacBook8,1 speaker driver (patched snd-hda-codec-cirrus) for the RUNNING Debian 13 kernel.
# Runs as a normal user (no sudo). Nothing is installed.
#
# Prerequisites (once):
#   sudo apt install build-essential linux-headers-$(uname -r) linux-source-6.12
#
# Usage:
#   bash audio/scripts/build-driver.sh
#   bash audio/scripts/build-driver.sh --source /path/to/linux-source-6.12.tar.xz   # use a specific tarball
#
# Output: audio/build/<kernel>/snd-hda-codec-cirrus.ko + SHA256SUMS
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
K=$(uname -r)
TARBALL=/usr/src/linux-source-6.12.tar.xz
CUSTOM_SOURCE=0
if [ "${1:-}" = "--source" ]; then TARBALL=${2:?path to linux-source tarball}; CUSTOM_SOURCE=1; fi
OUT=$REPO/audio/build/$K
PATCH=$REPO/audio/driver/mb81-speakers.patch
FILES="patch_cirrus.c hda_local.h hda_generic.h hda_auto_parser.h hda_jack.h hda_beep.h"

die() { echo "ABORT: $*" >&2; exit 1; }
# modinfo lives in /usr/sbin, which is not in a normal Debian user's PATH
MODINFO=$(command -v modinfo || echo /usr/sbin/modinfo)

echo "== MacBook8,1 speaker driver build for $K"
[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" = "MacBook8,1" ] || die "this is not a MacBook8,1"
case "$K" in 6.12.*) ;; *) die "the patch targets Debian 6.12 kernels (sound/pci/hda); running $K";; esac
[ -e "/lib/modules/$K/build/Makefile" ] || die "kernel headers missing: sudo apt install linux-headers-$K"
command -v make >/dev/null && command -v gcc >/dev/null || die "build tools missing: sudo apt install build-essential"
[ -s "$TARBALL" ] || die "$TARBALL not found: sudo apt install linux-source-6.12"

if [ "$CUSTOM_SOURCE" = 0 ]; then
  img=$(dpkg-query -W -f='${Version}' "linux-image-$K" 2>/dev/null || true)
  src=$(dpkg-query -W -f='${Version}' linux-source-6.12 2>/dev/null || true)
  [ -n "$img" ] && [ "$img" = "$src" ] || die "linux-source-6.12 ($src) does not match linux-image-$K ($img). Update both, reboot into the new kernel, retry."
  echo "  kernel package $img = source package $src"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
echo "== extracting HDA sources (this takes a minute)"
patterns=()
for f in $FILES; do patterns+=("*/sound/pci/hda/$f"); done
tar -xf "$TARBALL" -C "$OUT" --wildcards --strip-components=4 "${patterns[@]}"
for f in $FILES; do [ -s "$OUT/$f" ] || die "could not extract $f from $TARBALL"; done
echo "  base patch_cirrus.c sha256: $(sha256sum "$OUT/patch_cirrus.c" | cut -d' ' -f1)"

echo "== applying patch"
patch --dry-run -s -p4 -d "$OUT" < "$PATCH" >/dev/null \
  || die "the patch does not apply to this kernel's patch_cirrus.c (kernel source changed). Do not force it; report the kernel version."
patch -s -p4 -d "$OUT" < "$PATCH"
cp "$REPO/audio/driver/Makefile" "$OUT/Makefile"

echo "== compiling"
make -C "/lib/modules/$K/build" M="$OUT" modules > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; die "compile failed (full log: $OUT/build.log)"; }
ko=$OUT/snd-hda-codec-cirrus.ko
[ -s "$ko" ] || die "module not produced"
vermagic=$("$MODINFO" -F vermagic "$ko")
case "$vermagic" in "$K "*) ;; *) die "vermagic '$vermagic' does not match $K";; esac
grep -aq "MacBook8,1 speakers: codec clock" "$ko" || die "built module does not contain the speaker code"
(cd "$OUT" && sha256sum snd-hda-codec-cirrus.ko > SHA256SUMS)

echo
echo "BUILD OK: $ko"
echo "  vermagic: $vermagic"
echo "  sha256:   $(cut -d' ' -f1 "$OUT/SHA256SUMS")"
echo "Next: sudo bash audio/scripts/install-driver.sh"
