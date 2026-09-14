#!/bin/bash
# MacBook8,1: follow the headphone jack. Plugged in -> default output = MacBook Headphones,
# unplugged -> MacBook Speakers (EQ sink if installed, otherwise the raw speaker sink).
# Installed as ~/.local/bin/mb81-audio-autoswitch and run by the systemd user service
# mb81-audio-autoswitch.service (see audio/scripts/autoswitch-service.sh). Streams that follow the default
# output move with it (WirePlumber linking.follow-default-target).
set -u

HP_NODE="alsa_output.pci-0000_00_1b.0.playback.0.0"
SPEAKER_NODES="mb81_speakers_eq mb81_speakers"
last=""

node_id() {  # node.name -> PipeWire object id (empty if not present)
  pw-dump 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
for o in json.load(sys.stdin):
    p = (o.get("info") or {}).get("props") or {}
    if o.get("type", "").endswith(":Node") and p.get("node.name") == want:
        print(o["id"]); break
' "$1"
}

jack_state() {
  amixer -c PCH cget iface=CARD,name='Headphone Jack' 2>/dev/null | sed -n 's/.*: values=//p'
}

apply() {
  local state target id name
  state=$(jack_state)
  [ -n "$state" ] || return
  [ "$state" = "$last" ] && return
  if [ "$state" = on ]; then
    target=$HP_NODE
  else
    target=""
    for name in $SPEAKER_NODES; do
      [ -n "$(node_id "$name")" ] && { target=$name; break; }
    done
  fi
  [ -n "$target" ] || { echo "jack=$state: no speaker node yet"; return; }
  id=$(node_id "$target")
  [ -n "$id" ] || { echo "jack=$state: $target not present yet"; return; }
  if wpctl set-default "$id"; then
    echo "jack=$state -> default output $target (id $id)"
    last=$state
  fi
}

# At start only remember the current jack state: WirePlumber restores the user's saved default
# output (e.g. an external monitor), and this service must not override it at every login.
# The default is changed only when the jack state actually changes.
for _ in $(seq 1 15); do
  last=$(jack_state)
  [ -n "$last" ] && break
  sleep 2
done
echo "start: jack=${last:-unknown}, leaving the saved default output alone"

# Re-check on every control event of the PCH card (cheap; ignores the event text format).
stdbuf -oL /usr/sbin/alsactl monitor hw:PCH | while read -r _; do
  sleep 0.3
  apply
done
