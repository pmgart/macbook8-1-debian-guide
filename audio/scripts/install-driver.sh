#!/bin/bash
# Install the MacBook8,1 speaker driver built by build-driver.sh for the RUNNING kernel.
#   sudo bash audio/scripts/install-driver.sh
# Then reboot normally and run: sudo bash audio/scripts/verify-speakers.sh
# Undo: sudo bash audio/scripts/restore-stock.sh   (then reboot)
#
# Changes exactly two things:
#   /lib/modules/<kernel>/updates/mb81-speakers/snd-hda-codec-cirrus.ko   (new)
#   /etc/modprobe.d/mb81-speakers.conf                                    (new; snd_hda_intel options)
# Previous state is saved under /var/backups/mb81-audio/<timestamp>/.
# It does not touch initramfs, GRUB, other kernels, the generic HDA module or PipeWire.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
K=$(uname -r)
BUILD=$REPO/audio/build/$K
KO=$BUILD/snd-hda-codec-cirrus.ko
DEST_DIR=/lib/modules/$K/updates/mb81-speakers
CONF=/etc/modprobe.d/mb81-speakers.conf
CS4208_PCI=0000:00:1b.0
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/var/backups/mb81-audio/install-$STAMP

die() { echo "ABORT: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
[ "$(cat /sys/class/dmi/id/product_name)" = "MacBook8,1" ] || die "this is not a MacBook8,1"
grep -q "modprobe.blacklist=snd_hda_intel" /proc/cmdline && die "this boot has snd_hda_intel blacklisted; boot normally first"

mkdir -p "$BACKUP"
exec > >(tee -a "$BACKUP/install.log") 2>&1
echo "== MacBook8,1 speaker driver install $STAMP (kernel $K)"

echo "[1/6] verify the built module"
[ -s "$KO" ] && [ -s "$BUILD/SHA256SUMS" ] || die "no build for $K: run 'bash audio/scripts/build-driver.sh' first"
(cd "$BUILD" && sha256sum -c --quiet SHA256SUMS) || die "module checksum mismatch"
# no "cmd | grep -q" under pipefail: grep exiting early would fail the pipeline spuriously
name=$(modinfo -F name "$KO"); vermagic=$(modinfo -F vermagic "$KO"); aliases=$(modinfo -F alias "$KO")
[ "$name" = snd_hda_codec_cirrus ] || die "wrong module name '$name'"
case "$vermagic" in "$K "*) ;; *) die "vermagic '$vermagic' is not $K";; esac
case $'\n'"$aliases"$'\n' in *$'\n''hdaudio:v10134208r*a01*'$'\n'*) ;; *) die "CS4208 alias missing";; esac
grep -aq "MacBook8,1 speakers: codec clock" "$KO" || die "not the speaker build"
echo "  ok: sha256 $(cut -c1-16 "$BUILD/SHA256SUMS")…"

echo "[2/6] safety checks"
hda_in_initrd=$(lsinitramfs "/boot/initrd.img-$K" | grep -c "snd-hda" || true)
[ "$hda_in_initrd" = 0 ] || die "initramfs contains HDA modules ($hda_in_initrd); this installer assumes it does not"
others=$(ls /boot/vmlinuz-* | grep -vc "vmlinuz-$K$" || true)
[ "$others" -ge 1 ] && echo "  ok: $others other kernel(s) installed as GRUB fallback" \
  || echo "  WARNING: no other kernel installed; keep a Debian live USB for recovery"
[ -e "/sys/bus/pci/devices/$CS4208_PCI" ] || die "CS4208 HDA controller $CS4208_PCI not found"

echo "[3/6] controller index for the no-reset option"
# snd_hda_intel options are per-controller arrays in probe order (= PCI address order).
mapfile -t ctrls < <(for d in /sys/bus/pci/devices/*; do
  [ "$(cat "$d/class")" = 0x040300 ] && basename "$d"; done | sort)
idx=-1
for i in "${!ctrls[@]}"; do [ "${ctrls[$i]}" = "$CS4208_PCI" ] && idx=$i; done
[ "$idx" -ge 0 ] || die "could not find $CS4208_PCI among HDA controllers: ${ctrls[*]}"
probe_only=""; probe_mask=""
for i in "${!ctrls[@]}"; do
  if [ "$i" = "$idx" ]; then v1=2; v2=0x101; else v1=0; v2=-1; fi
  probe_only+="${probe_only:+,}$v1"; probe_mask+="${probe_mask:+,}$v2"
done
echo "  HDA controllers: ${ctrls[*]} -> CS4208 is index $idx"
echo "  probe_only=$probe_only probe_mask=$probe_mask"

echo "[4/6] backup"
[ -e "$CONF" ] && cp -a "$CONF" "$BACKUP/"
[ -e "$DEST_DIR" ] && cp -a "$DEST_DIR" "$BACKUP/"
for f in $(grep -rl "snd_hda_intel" /etc/modprobe.d/ 2>/dev/null || true); do cp -a "$f" "$BACKUP/"; done
echo "  saved to $BACKUP"
others_opts=$(grep -rhE '^[[:space:]]*options[[:space:]]+snd[_-]hda[_-]intel' /etc/modprobe.d/ 2>/dev/null | grep -v "^#" || true)
if [ -n "$others_opts" ] && ! grep -q "probe_only" "$CONF" 2>/dev/null; then
  echo "  WARNING: other snd_hda_intel options exist and may conflict:"
  grep -rnE '^[[:space:]]*options[[:space:]]+snd[_-]hda[_-]intel' /etc/modprobe.d/ | sed 's/^/    /'
fi

echo "[5/6] install module"
install -d -m 0755 "$DEST_DIR"
install -m 0644 -o root -g root "$KO" "$DEST_DIR/snd-hda-codec-cirrus.ko"
depmod -a "$K"
resolved=$(modinfo -k "$K" -n snd_hda_codec_cirrus)
[ "$resolved" = "$DEST_DIR/snd-hda-codec-cirrus.ko" ] || die "module resolves to $resolved; run restore-stock.sh"
echo "  snd_hda_codec_cirrus  -> $resolved"
echo "  snd_hda_codec_generic -> $(modinfo -k "$K" -n snd_hda_codec_generic) (stock)"

echo "[6/6] controller options"
tmp=$(mktemp "$CONF.XXXXXX")
cat > "$tmp" <<EOF
# MacBook8,1 CS4208 internal speakers (audio/scripts/install-driver.sh, $STAMP).
# single_cmd=1  immediate command mode (needed for the no-reset attach to enumerate reliably)
# power_save=0  keep the codec and the EFI-powered speaker amplifier in D0
# probe_only / probe_mask are per-controller arrays in PCI order: ${ctrls[*]}
#   CS4208 controller $CS4208_PCI (index $idx): probe_only=2 = attach WITHOUT link reset
#   (a reset latches the codec clock), probe_mask=0x101 = force codec 0.
options snd_hda_intel single_cmd=1 power_save=0 probe_only=$probe_only probe_mask=$probe_mask
EOF
chmod 0644 "$tmp"; chown root:root "$tmp"; mv "$tmp" "$CONF"
grep "^options" "$CONF"

echo
echo "INSTALLED. Reboot normally, then run: sudo bash audio/scripts/verify-speakers.sh"
echo "Undo: sudo bash audio/scripts/restore-stock.sh  then reboot."
