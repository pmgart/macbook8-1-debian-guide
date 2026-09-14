# AI runbook: install MacBook8,1 internal speaker audio on Debian 13

This file is written for AI coding agents (Claude Code, Codex, Gemini CLI, Copilot, …) that help a user install
the audio setup from this repository. Humans can follow it too. Read [HOW_IT_WORKS.md](HOW_IT_WORKS.md) before
changing anything that is not described here.

## Rules

1. **The user types every sudo password.** Never ask for, store, or handle passwords or tokens.
2. **One gate at a time.** Run the gate's check, compare with the expected result, report it to the user, then
   continue. If a check fails, follow its *On failure* line. Never skip a gate.
3. **Ask before** installing packages, installing the driver, rebooting, or writing EFI variables. Ask again for
   each such action.
4. **Never edit the patch or scripts to force a result** (e.g. `patch --force`, removing checks, changing
   `probe_only` by hand). If the patch does not apply or a gate fails twice, stop and report.
5. **Claims need evidence.** Say "speakers work" only after the user heard sound in gate 7. Detected ALSA or
   PipeWire devices are not proof of audio.
6. **Recovery first.** The user must be able to reach a working state again: `restore-stock.sh`, an older
   kernel in GRUB "Advanced options", or a Debian live USB.
7. Keep private data out of anything published (hostnames, IPs, usernames, serial numbers).

Commands below assume the repository root as the working directory.

---

## Gate 0: identity and baseline (read-only)

```bash
cat /sys/class/dmi/id/product_name
grep PRETTY_NAME /etc/os-release
uname -r
grep -o 'initcall_blacklist=dw_pci_driver_init' /proc/cmdline
grep CS4208 /proc/asound/pcm
bash audio/scripts/verify-stock.sh
```

**Expected:** `MacBook8,1`; Debian 13 (trixie); kernel `6.12.*`; the Apple SPI parameter present (see the main
README section 6); `CS4208 Analog : ... playback 1 : capture 1`; `RESULT: STOCK`.
Ask the user to confirm headphones play sound now.

**On failure:** wrong model or kernel series → stop, this setup does not apply. `NOT STOCK` → an earlier
install exists; run gate 8 (restore), reboot, start again.

## Gate 1: recovery path

Confirm with the user:
- another kernel is installed (`ls /boot/vmlinuz-*` shows more than one), **or** a Debian live USB is available;
- they know that `sudo bash audio/scripts/restore-stock.sh` + reboot returns to stock audio.

## Gate 2 (optional): EFI startup-chime mute bit

```bash
python3 audio/diagnostics/efi-audio-mute.py check
```

**Expected:** `mute_bit=CLEAR`. The reference machine had it clear. If `SET`, explain that the setup was never
tested with a muted chime; clearing it is optional and needs the user's approval:
`sudo python3 audio/diagnostics/efi-audio-mute.py apply` (backs up, changes only bit `0x80`, then reboot).

## Gate 3: packages (ask first)

```bash
sudo apt install build-essential linux-headers-$(uname -r) linux-source-6.12 alsa-utils python3
dpkg-query -W -f='${Version}\n' linux-image-$(uname -r) linux-source-6.12
```

**Expected:** both versions identical.
**On failure:** versions differ → `sudo apt full-upgrade`, reboot into the newest kernel, repeat gate 3.

## Gate 4: build (no sudo)

```bash
bash audio/scripts/build-driver.sh
```

**Expected:** ends with `BUILD OK`, vermagic equals `uname -r`.
**On failure:** `the patch does not apply` → stop and report the kernel version (the kernel source changed; the
patch needs a human port). Compile error → report `audio/build/<kernel>/build.log`.

## Gate 5: install driver (ask first), then reboot (ask first)

```bash
sudo bash audio/scripts/install-driver.sh
```

**Expected:** `[1/6]`…`[6/6]`, `INSTALLED`, the options line (on MacBook8,1:
`options snd_hda_intel single_cmd=1 power_save=0 probe_only=0,2 probe_mask=-1,0x101`).
**On failure:** any `ABORT` leaves the system unchanged; report the message. Then reboot normally (no GRUB edits).

## Gate 6: verify driver (after reboot)

```bash
sudo bash audio/scripts/verify-speakers.sh
```

**Expected:** every line `OK`, `RESULT: SPEAKER DRIVER OK`, including `codec clock locked`.
Then, headphones unplugged, ask the user to listen:

```bash
aplay -D plughw:CARD=PCH,DEV=2 /usr/share/sounds/alsa/Front_Center.wav
```

**On failure:** see the table below. If the clock is latched or the no-reset attach failed and the table does not
explain it, collect `sudo dmesg | grep -iE 'hda|cs4208|MacBook8,1'` and `sudo python3 audio/diagnostics/read-codec.py`,
then run gate 8. Do not retry with modified options.

## Gate 7: desktop audio (no sudo)

```bash
bash audio/scripts/pipewire-speakers.sh install       # MacBook Speakers / Headphones / Microphone
bash audio/scripts/speaker-eq.sh install              # optional: macOS-style EQ (downloads EQ values, needs internet)
bash audio/scripts/autoswitch-service.sh install      # headphone plug/unplug switches the output
```

**Expected:** `OK: 'MacBook Speakers' exists`, `OK: 'MacBook Speakers (EQ)' is available`, service `active`.
Ask the user to check, in order: YouTube/music plays from the speakers; the volume slider works; plugging in
headphones moves sound to them and unplugging moves it back; the microphone level meter moves.

**On failure:**
- Sound goes to headphones or nowhere: check `wpctl status`; the stream may be on another output. Select
  `MacBook Speakers (EQ)` or run the autoswitch installer.
- `aplay ... DEV=2` says "Device or resource busy" after gate 7: expected, PipeWire holds the speakers. Use
  `pw-play /usr/share/sounds/alsa/Front_Center.wav`.
- EQ output missing: `bash audio/scripts/speaker-eq.sh remove`, report `journalctl --user -u pipewire --since -5min`.

Report success to the user only after they confirm what they heard.

## Gate 8: restore (whenever needed)

```bash
sudo bash audio/scripts/restore-stock.sh
# reboot
bash audio/scripts/verify-stock.sh
```

**Expected:** `RESULT: STOCK`; headphones play.

---

## Troubleshooting table

| Symptom | Likely cause | Action |
|---|---|---|
| `no-reset attach did not happen on 00:1b.0` | controller order changed (e.g. HDMI audio disabled) | re-run `install-driver.sh` (recomputes the index), reboot |
| `cirrus module resolves to .../kernel/sound/...` | kernel updated | gates 3–6 for the new kernel |
| `driver reports codec clock LATCHED` | a link reset happened (suspend/resume, module reload, wrong options) | reboot; avoid suspend; check options |
| Speakers silent after sleep | known limitation (resume resets the link) | reboot |
| `speaker-test -t wav` fails on DEV=2 | sample files are 48 kHz | use `-t pink`, `aplay -D plughw:...`, or `pw-play` |
| No sound in headphones, speakers keep playing | default output not switched | install/restart the autoswitch service; select `MacBook Headphones` |
| External mic on the headphone jack not detected | by design (its VREF latches the clock) | use the internal mic or a USB/Bluetooth mic |

## After every kernel update

The new kernel boots with Debian's stock codec module: headphones work, speakers are silent. Run gates 3–6 again
(the PipeWire files and services from gate 7 stay in place). Remove old builds with
`rm -rf audio/build/<old-kernel>`; old kernel module directories are removed by `restore-stock.sh` or with the
kernel package.
