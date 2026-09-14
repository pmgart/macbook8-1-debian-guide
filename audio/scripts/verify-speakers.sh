#!/bin/bash
# Check the installed MacBook8,1 speaker setup after a normal boot. Read-only.
#   sudo bash audio/scripts/verify-speakers.sh
set -u
REPO=$(cd "$(dirname "$0")/../.." && pwd)
K=$(uname -r)
DEST=/lib/modules/$K/updates/mb81-speakers/snd-hda-codec-cirrus.ko
CONF=/etc/modprobe.d/mb81-speakers.conf
[ "$(id -u)" = 0 ] || { echo "Run with sudo (needed for the kernel log and the codec read)."; exit 1; }

fail=0
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  WARN  %s\n' "$1"; }

echo "MacBook8,1 speaker setup check ($(date '+%F %T'), kernel $K)"
echo "[boot]"
[ "$(cat /sys/class/dmi/id/product_name)" = "MacBook8,1" ] && ok "MacBook8,1" || bad "not a MacBook8,1"
grep -q "modprobe.blacklist=snd_hda_intel" /proc/cmdline && bad "snd_hda_intel blacklisted on the kernel line" || ok "normal boot"

echo "[controller]"
want=$(sed -n 's/^options snd_hda_intel .*probe_only=\([^ ]*\).*/\1/p' "$CONF" 2>/dev/null)
have=$(cat /sys/module/snd_hda_intel/parameters/probe_only 2>/dev/null)
[ -n "$want" ] && ok "options file $CONF" || bad "$CONF missing or without probe_only"
case "$have" in "$want",*|"$want") ok "probe_only active ($want)";; *) bad "probe_only active '$have', expected '$want'";; esac
[ "$(cat /sys/module/snd_hda_intel/parameters/single_cmd 2>/dev/null)" = 1 ] && ok "single_cmd=1" || bad "single_cmd not 1"
[ "$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null)" = 0 ] && ok "power_save=0" || bad "power_save not 0"
dmesg | grep -q "0000:00:1b.0: codec_mask forced to 0x1" && ok "no-reset attach on 00:1b.0" \
  || bad "no-reset attach did not happen on 00:1b.0 (controller order changed? re-run install-driver.sh)"

echo "[codec driver]"
[ "$(modinfo -n snd_hda_codec_cirrus 2>/dev/null)" = "$DEST" ] && ok "cirrus module resolves to the speaker build" \
  || bad "cirrus module resolves to $(modinfo -n snd_hda_codec_cirrus 2>/dev/null) (kernel updated? rebuild + reinstall)"
case "$(cat /sys/module/snd_hda_codec_cirrus/taint 2>/dev/null)" in *O*) ok "speaker build loaded";; *) bad "speaker build not loaded";; esac
clk=$(dmesg | grep "MacBook8,1 speakers: codec clock" | tail -1)
case "$clk" in *locked*) ok "driver reports codec clock locked";; "") bad "no clock report from the driver";; *) bad "driver: ${clk#*: }";; esac

echo "[ALSA]"
grep -qE "CS4208 Analog : .*playback 1 : capture 1" /proc/asound/pcm && ok "CS4208 Analog playback + capture" || bad "analog playback/capture missing"
spk=$(grep "CS4208 Speaker" /proc/asound/pcm)
[ -n "$spk" ] && ok "speaker PCM ${spk%%:*}" || bad "CS4208 Speaker PCM missing"
card=$(grep -l "CS4208" /proc/asound/card*/codec#0 2>/dev/null | head -1 | sed -E 's#.*/card([0-9]+)/.*#\1#')
if [ -n "$card" ]; then
  python3 "$REPO/audio/diagnostics/read-codec.py" "/dev/snd/hwC${card}D0" | grep -q "coef 0x1f = 0x0000" \
    && ok "codec clock locked now (coef 0x1f = 0x0000)" || bad "codec clock latched now (speakers will be silent)"
fi

echo
if [ "$fail" = 0 ]; then
  echo "RESULT: SPEAKER DRIVER OK"
  echo "  Manual test, headphones unplugged:"
  echo "    aplay -D plughw:CARD=PCH,DEV=2 /usr/share/sounds/alsa/Front_Center.wav"
  echo "  (if PipeWire already uses the speakers, test with:  pw-play /usr/share/sounds/alsa/Front_Center.wav)"
else
  echo "RESULT: PROBLEM FOUND. Headphones should still work. Undo: sudo bash audio/scripts/restore-stock.sh"
fi
exit "$fail"
