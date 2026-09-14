#!/bin/bash
# Read-only check that the machine is on Debian's stock audio setup (nothing from this repo active).
#   bash audio/scripts/verify-stock.sh
set -u
K=$(uname -r)
fail=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "MacBook8,1 stock audio check ($(date '+%F %T'), kernel $K)"
[ -e "/lib/modules/$K/updates/mb81-speakers" ] && bad "speaker module directory still present" || ok "no speaker module directory"
case "$(/usr/sbin/modinfo -n snd_hda_codec_cirrus 2>/dev/null)" in
  "/lib/modules/$K/kernel/sound/"*) ok "cirrus module is Debian's";;
  *) bad "cirrus module resolves to $(/usr/sbin/modinfo -n snd_hda_codec_cirrus 2>/dev/null)";;
esac
[ -e /etc/modprobe.d/mb81-speakers.conf ] && bad "/etc/modprobe.d/mb81-speakers.conf still present" || ok "no speaker options file"
case "$(cat /sys/module/snd_hda_codec_cirrus/taint 2>/dev/null)" in *O*) bad "out-of-tree cirrus module loaded (reboot needed?)";; *) ok "no out-of-tree cirrus module loaded";; esac
grep -qE "CS4208 Analog : .*playback 1 : capture 1" /proc/asound/pcm && ok "CS4208 Analog playback + capture" || bad "analog playback/capture missing"
for f in "$HOME/.config/wireplumber/wireplumber.conf.d/51-mb81-speakers.conf" "$HOME/.config/pipewire/pipewire.conf.d/52-mb81-speaker-eq.conf" "$HOME/.config/systemd/user/mb81-audio-autoswitch.service"; do
  [ -e "$f" ] && bad "user file still present: $f" || true
done
echo
[ "$fail" = 0 ] && echo "RESULT: STOCK. Test headphones by ear." || echo "RESULT: NOT STOCK. Run: sudo bash audio/scripts/restore-stock.sh, then reboot."
exit "$fail"
