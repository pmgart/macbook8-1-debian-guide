# MacBook8,1 audio on Debian 13: internal speakers, headphones and microphone

> **Status:** verified working on the reference machine, 2026-09-14
> **Kernel:** Debian `6.12.107+deb13-amd64` · PipeWire `1.4.2` · WirePlumber `0.5.8`
> Want an AI assistant to do it? Point it at [AI_RUNBOOK.md](AI_RUNBOOK.md).

## What works

| Function | Status | Notes |
|---|---|---|
| Internal speakers | **Working** | 4-channel TDM path, optional macOS-style EQ |
| Headphones (3.5 mm) | **Working** | automatic switching on plug/unplug |
| Internal microphone | **Working** | |
| HDMI / USB-C display audio | Working | unchanged by this setup |
| External mic on the combo jack | **Not supported** | enabling it breaks the speaker clock (see [HOW_IT_WORKS.md](HOW_IT_WORKS.md)) |
| Sound after suspend/resume | **Not working** | reboot restores it; sleep also affects Apple SPI input on this model |
| Kernel updates | Manual step | rebuild + reinstall the driver (section 6) |

Stock Debian plays headphones but not the speakers. The reason, measured on the hardware: Linux resets the audio
link at boot and enables the headphone-jack microphone bias, and both destroy the codec clock that the EFI firmware
set up for the speakers. This setup avoids both, adds a proper speaker device to the Cirrus codec driver, and wires it
into PipeWire. Details: [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

## 1. Before you start

- Exact model `MacBook8,1` (`cat /sys/class/dmi/id/product_name`), Debian 13, kernel `6.12.*`.
- The Apple SPI keyboard/trackpad fix from the [main guide](../../README.md#6-apple-spi-keyboard-and-touchpad-the-critical-issue) is in place.
- Headphones already work on stock Debian.
- A way back: a second kernel in GRUB, or a Debian live USB. Everything here is undone by one script.

Get the repository:

```bash
git clone https://github.com/pmgart/macbook8-1-debian-guide.git
cd macbook8-1-debian-guide
```

## 2. Build the driver (no sudo for the build)

```bash
sudo apt install build-essential linux-headers-$(uname -r) linux-source-6.12 alsa-utils python3
bash audio/scripts/build-driver.sh
```

The script refuses to build if the machine, the kernel series or the source package version does not match, or if
the patch does not apply cleanly. Output: `audio/build/<kernel>/snd-hda-codec-cirrus.ko`.

## 3. Install the driver

```bash
sudo bash audio/scripts/install-driver.sh
sudo reboot
```

It installs exactly two things:

| File | Purpose |
|---|---|
| `/lib/modules/<kernel>/updates/mb81-speakers/snd-hda-codec-cirrus.ko` | Debian's Cirrus codec driver + speaker patch |
| `/etc/modprobe.d/mb81-speakers.conf` | `snd_hda_intel` options: attach to the CS4208 controller without a link reset |

No initramfs, GRUB or other-kernel changes. Backups and a log go to `/var/backups/mb81-audio/`.

After the reboot:

```bash
sudo bash audio/scripts/verify-speakers.sh
aplay -D plughw:CARD=PCH,DEV=2 /usr/share/sounds/alsa/Front_Center.wav     # headphones unplugged
```

## 4. Desktop sound (no sudo)

```bash
bash audio/scripts/pipewire-speakers.sh install      # outputs: MacBook Speakers / Headphones / Microphone
bash audio/scripts/speaker-eq.sh install             # optional: "MacBook Speakers (EQ)", louder and fuller
bash audio/scripts/autoswitch-service.sh install     # plug in headphones -> they play; unplug -> speakers
```

Choose **MacBook Speakers (EQ)** (or **MacBook Speakers**) in your desktop's sound settings. Note that a running
browser tab keeps its current output until the default changes or playback restarts.

`speaker-eq.sh` downloads the EQ values from the
[thomas-shirley/macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver) project at a
pinned commit and checks its checksum (that project has no license, so its file is not copied into this repository).

## 5. Uninstall / back to stock

```bash
sudo bash audio/scripts/restore-stock.sh
sudo reboot
bash audio/scripts/verify-stock.sh
```

Removed files are kept under `/var/backups/mb81-audio/restore-<timestamp>/`. If a boot misbehaves, pick an older
kernel in GRUB "Advanced options" and run the same script there.

## 6. After a Debian kernel update

The new kernel starts with Debian's stock codec driver: headphones keep working, speakers are silent until you run:

```bash
sudo apt install linux-headers-$(uname -r) linux-source-6.12     # versions must match the new kernel
bash audio/scripts/build-driver.sh
sudo bash audio/scripts/install-driver.sh
sudo reboot
sudo bash audio/scripts/verify-speakers.sh
```

## 7. Troubleshooting

| Symptom | What to do |
|---|---|
| `verify-speakers.sh` reports `codec clock LATCHED` | Reboot (a suspend/resume or a driver reload latches it). If it persists, run `restore-stock.sh` and open an issue with the verify output. |
| `no-reset attach did not happen on 00:1b.0` | Re-run `install-driver.sh` (it recomputes the controller order), reboot. |
| No sound from YouTube, but `aplay ... DEV=2` works | Select **MacBook Speakers (EQ)** as output; install `pipewire-speakers.sh`. |
| `aplay ... DEV=2`: "Device or resource busy" | Normal once PipeWire uses the speakers; test with `pw-play /usr/share/sounds/alsa/Front_Center.wav`. |
| `speaker-test -t wav` fails on device 2 | The sample files are 48 kHz, the speaker PCM is 44.1 kHz only. Use `speaker-test -D hw:CARD=PCH,DEV=2 -c 4 -r 44100 -F S16_LE -t pink`. |
| Headphones silent, speakers keep playing | `systemctl --user status mb81-audio-autoswitch`; or pick **MacBook Headphones** manually. |

Diagnostics (read-only):

```bash
sudo python3 audio/diagnostics/read-codec.py          # clock coef 0x1f and speaker/headphone node state
python3 audio/diagnostics/efi-audio-mute.py check     # EFI startup-chime mute bit
```

`audio/diagnostics/read-clock-driverless.py` reads the clock with no driver loaded; it is only meaningful on a
one-time boot with `modprobe.blacklist=snd_hda_intel` added in the GRUB editor.

## 8. Repository layout (audio)

```text
audio/driver/mb81-speakers.patch     patch for Debian 6.12 sound/pci/hda/patch_cirrus.c (GPL-2.0-only)
audio/driver/Makefile                out-of-tree module build
audio/scripts/build-driver.sh        extract sources from linux-source-6.12, patch, build
audio/scripts/install-driver.sh      install module + snd_hda_intel options (sudo)
audio/scripts/verify-speakers.sh     post-reboot checks (sudo, read-only)
audio/scripts/restore-stock.sh       undo everything (sudo)
audio/scripts/verify-stock.sh        confirm stock state (read-only)
audio/scripts/pipewire-speakers.sh   WirePlumber rule: speaker/headphone/mic outputs (user)
audio/scripts/speaker-eq.sh          optional EQ output (user, downloads EQ values)
audio/scripts/autoswitch-service.sh  headphone jack auto-switch service (user)
audio/scripts/audio-autoswitch.sh    the auto-switch program
audio/config/51-mb81-speakers.conf   WirePlumber rule installed by pipewire-speakers.sh
audio/diagnostics/                   read-codec.py, read-clock-driverless.py, efi-audio-mute.py
```

## Credits

This setup builds on public work by other owners of these machines:

- [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) (GPL-2.0): CS4208 reverse engineering on Apple hardware.
- [leifliddy/macbook12-audio-driver](https://github.com/leifliddy/macbook12-audio-driver) and
  [leifliddy/macbook8-1-audio-driver-test](https://github.com/leifliddy/macbook8-1-audio-driver-test): CS4208 drivers for 12" MacBooks.
- The MacBook8,1 owner who reported the digital TDM speaker path (`0x0a` → `0x1d`, 4ch / 44.1 kHz, stream-tag binding,
  `power_save=0`) in [leifliddy/macbook8-1-audio-driver-test issue #2](https://github.com/leifliddy/macbook8-1-audio-driver-test/issues/2).
- [thomas-shirley/macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver): the clock
  latch analysis (coef `0x1f`), the driverless EFI tone sequence and the layout100 EQ.

The driver patch, scripts and documentation in this repository were written for Debian 13 and verified on one
MacBook8,1. No code from the unlicensed projects above is included.
