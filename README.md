# Debian 13 on the 12-inch Retina MacBook (MacBook8,1)

> A reproducible installation, recovery, and hardware-status guide for the early-2015 12-inch Retina MacBook (`MacBook8,1`).
>
> **Document status:** working system snapshot, updated 2026-09-14  
> **Audience:** Linux users, maintainers, and AI agents  
> **Scope:** Debian 13 (trixie), desktop-agnostic base system, Cinnamon reference desktop, Apple SPI input recovery, internal speaker audio
>
> **Using an AI assistant?** Point it at [`AGENTS.md`](AGENTS.md). Audio install for agents: [`docs/audio/AI_RUNBOOK.md`](docs/audio/AI_RUNBOOK.md).

---

## 0. Quick start: order of work on a new MacBook8,1

| Step | What | Where | Result |
|---|---|---|---|
| 1 | Install Debian 13 with `non-free-firmware` enabled, Broadcom Wi-Fi firmware | [Section 4](#4-fresh-install-baseline) | Booting system with Wi-Fi |
| 2 | Fix the Apple SPI keyboard and touchpad (GRUB parameter) | [Section 6](#6-apple-spi-keyboard-and-touchpad-the-critical-issue) | Internal keyboard and touchpad work after every reboot |
| 3 | Optional: SSH + Tailscale for remote recovery | [Section 5](#5-optional-but-strongly-recommended-tailscale--ssh-recovery-access) | A second way into the machine |
| 4 | Get this repository on the MacBook: `sudo apt install git` then `git clone https://github.com/pmgart/macbook8-1-debian-guide.git` | — | Scripts available locally |
| 5 | Internal speakers, headphone switching, microphone | [docs/audio/README.md](docs/audio/README.md) | Working audio |

With an AI assistant: open the cloned repository in the assistant and ask it to follow [`AGENTS.md`](AGENTS.md).
It will work through the steps above and the gated audio runbook, asking you before every privileged action.

---

## 1. Purpose and boundaries

This is a practical guide for rebuilding or recovering a Debian system on an **Apple MacBook8,1**. It documents the configuration that was verified on a real working installation, including a boot-time workaround for an Apple SPI keyboard/trackpad failure.

It is intentionally explicit about three categories:

- **Verified working:** confirmed on the reference machine after reboot.
- **Known limitation:** detected but not solved in this guide.
- **Not claimed:** configuration details that were not recorded during the original installation must not be invented or treated as historical facts.

The guide is **desktop-environment agnostic**. Cinnamon is the reference desktop because it was chosen for a complete, practical desktop experience while keeping resource use reasonable on this low-power, 8 GB machine. The keyboard/trackpad fix, firmware setup, bootloader configuration, Wi-Fi, graphics driver, and recovery workflow are system-level steps; they do not depend on Cinnamon.

> [!IMPORTANT]
> Do **not** apply the Apple SPI workaround to a different Mac model merely because it has an Apple keyboard or touchpad. First verify that the DMI product name is exactly `MacBook8,1`.

---

## 2. Reference machine: verified hardware and software

### 2.1 Hardware

| Component | Verified value | Status |
|---|---|---|
| Vendor / model | Apple Inc. `MacBook8,1`, version `1.0` | Supported by this guide |
| Product family | 12-inch Retina MacBook, early 2015 generation | Supported by this guide |
| CPU | Intel Core M-5Y31 @ 0.90 GHz | Working |
| Memory | 8 GB class (7.7 GiB visible to Linux) | Working |
| Internal storage controller | Apple S1X NVMe Controller (`106b:2001`) | Working |
| GPU | Intel HD Graphics 5300 (`8086:161e`) | Working with `i915` |
| Wi-Fi | Broadcom BCM4350 802.11ac (`14e4:43a3`) | Working with `brcmfmac` + firmware |
| Keyboard | Apple SPI Keyboard | Working with PIO workaround |
| Touchpad | Apple SPI Touchpad | Working with PIO workaround |
| Camera | Broadcom 720p FaceTime HD Camera (`14e4:1570`) | **Not working yet**; no `/dev/video0` device |
| Audio: internal speakers | Cirrus Logic CS4208 (`10134208`, SSID `106b6400`), 4-channel TDM amplifier path | **Working** with the patched codec driver and options in [`docs/audio`](docs/audio/README.md) |
| Audio: headphones / internal mic | CS4208 analog path | **Working** (stock Debian already plays headphones); automatic headphone/speaker switching with [`docs/audio`](docs/audio/README.md) |
| Audio: mic on the combo jack | CS4208 pin `0x18` | **Not supported**: enabling it breaks the speaker clock |

### 2.2 Verified software baseline

| Layer | Verified value |
|---|---|
| Distribution | Debian GNU/Linux 13 (trixie), `13.6` |
| Kernel | `6.12.107+deb13-amd64` (`6.12.107-1`) |
| Kernel architecture | `x86_64` |
| Boot configuration | GRUB configuration is present and updated with `/usr/sbin/update-grub` |
| Desktop reference | Cinnamon `6.4.10-2`, full `cinnamon-desktop-environment` / `task-cinnamon-desktop` |
| Display manager | LightDM `1.32.0-6+b2` |
| Display server in the reference session | Xorg (`xserver-xorg 1:7.7+24+deb13u1`) |
| Audio session stack | PipeWire `1.4.2` + WirePlumber `0.5.8-2` |
| Broadcom firmware package | `firmware-brcm80211 20250410-2` |
| APT components enabled | `main` and `non-free-firmware` for `trixie`, `trixie-updates`, and `trixie-security` |

The reference host was using only **13 GB of 221 GB** on the root filesystem at the time of verification. This is useful context, not a partitioning recommendation.

---

## 3. What is working and what is not

### Working after the verified reboot

- Debian boots to the graphical target.
- Cinnamon starts through LightDM/Xorg.
- Intel graphics are driven by `i915`.
- Broadcom Wi-Fi is connected using `brcmfmac` and `firmware-brcm80211`.
- Internal NVMe storage works.
- Apple SPI keyboard works.
- Apple SPI touchpad works.
- The Apple SPI boot is clean: no Apple SPI/SPI timeout or failure message was found in the current boot kernel log.
- Internal speakers, headphones and the internal microphone work after installing the audio setup in [`docs/audio/README.md`](docs/audio/README.md) (verified after reboot, 2026-09-14).

### Deliberately not marked as solved

- **FaceTime HD webcam:** the PCI device is visible but no V4L2 node such as `/dev/video0` exists. No webcam driver or userspace bridge is configured by this guide.
- **Suspend/resume:** not working on the reference machine. After sleep the Apple SPI keyboard and touchpad stop working (owner report, 2026-09-14) and the internal speakers stay silent because the resume path resets the HDA link. Reboot instead of suspending.
- **External microphone on the combo jack:** not supported by the audio setup (enabling it breaks the speaker clock).
- **Bluetooth:** not evaluated in this guide.
- **Battery-life tuning:** not evaluated in this guide.

---

## 4. Fresh-install baseline

The original installer choices, partition layout, usernames, and encryption choices were not preserved as a full transcript. Do not fabricate them.

For a new build, use the current Debian 13 installer and choose a standard EFI/GPT installation. The following are the important reproducible decisions from the working machine.

### 4.1 Use Debian 13 and enable firmware packages

The Broadcom BCM4350 Wi-Fi adapter requires non-free firmware. Ensure that your APT sources include `non-free-firmware`.

Example `/etc/apt/sources.list` entries:

```text
deb http://deb.debian.org/debian/ trixie main non-free-firmware
deb http://security.debian.org/debian-security trixie-security main non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main non-free-firmware
```

Then install/confirm the firmware package:

```bash
sudo apt update
sudo apt install firmware-brcm80211
```

Verify the Wi-Fi driver and connection:

```bash
lspci -nnk | grep -A3 -Ei 'network|wireless'
nmcli device status
```

Expected direction:

```text
Kernel driver in use: brcmfmac
```

> [!TIP]
> Have wired Ethernet through a compatible USB adapter, or a known-working external Wi-Fi adapter, available during initial setup. It is useful for recovery even when internal Wi-Fi later works.

### 4.2 Desktop choice: Cinnamon reference, desktop-agnostic system

The reference machine uses Cinnamon because it prioritizes:

1. **A complete desktop system**: familiar settings, file management, notifications, power/session controls, app integration, and normal everyday workflows.
2. **Practical performance**: it remains usable on the Core M / 8 GB platform without turning the machine into a minimal or manually assembled desktop.
3. **Maintainability**: Debian packages, LightDM, Xorg, and Cinnamon are straightforward to reinstall and diagnose.

Install the complete reference desktop on a base Debian installation:

```bash
sudo apt update
sudo apt install task-cinnamon-desktop lightdm xserver-xorg
sudo systemctl set-default graphical.target
sudo reboot
```

During package installation, select LightDM if Debian asks which display manager should be the default.

### 4.3 Desktop-agnostic alternatives

The following are **not required** for the SPI fix:

- Cinnamon versus GNOME, XFCE, MATE, KDE Plasma, LXQt, or a window manager.
- LightDM versus another display manager.
- Xorg versus Wayland, provided the chosen session works correctly on the device.

If another desktop is preferred, install it normally. Keep the sections on firmware, GRUB, Apple SPI diagnosis, and PIO validation unchanged.

The reference configuration used Xorg because that is what LightDM launched for the working Cinnamon session. This guide does **not** claim that Xorg is the cause of input stability; the input issue occurs below the desktop layer during kernel/device initialization.

---

## 5. Optional but strongly recommended: Tailscale + SSH recovery access

Tailscale is not required for Debian, Cinnamon, Wi-Fi, or the Apple SPI fix. It is strongly recommended as an **out-of-band recovery path** for a laptop whose internal keyboard and touchpad can fail before a workaround is active.

The reference MacBook and its Linux workstation were verified online in the same Tailnet. On the MacBook, `tailscaled` and the SSH service are both enabled and active.

### Why this matters

If an input regression happens after a kernel update or an unsuccessful boot configuration change, a second trusted Tailnet device can still:

- SSH to the MacBook without depending on the local LAN.
- Read `/proc/cmdline`, input-device state, module state, and the boot log.
- Restore a backed-up GRUB configuration.
- Run `/usr/sbin/update-grub` and reboot **only with explicit approval**.

This avoids turning a keyboard/trackpad failure into a physical-recovery-only situation.

### Minimal implementation

Install Tailscale and OpenSSH server from Debian packages or the official Tailscale repository according to your organization’s policy. Then authenticate Tailscale interactively on the MacBook and verify both services:

```bash
sudo systemctl enable --now tailscaled
sudo systemctl enable --now ssh

tailscale status
systemctl is-active tailscaled
systemctl is-active ssh
```

From another approved Tailnet device:

```bash
ssh <macbook-linux-user>@<macbook-tailnet-hostname>
```

> [!CAUTION]
> Do not publish your Tailnet hostname, Tailscale IP address, SSH username, ACL policy, public keys, or internal network topology in a public repository. Use placeholders in documentation and restrict SSH with normal system hardening and Tailnet ACLs.

---

## 6. Apple SPI keyboard and touchpad: the critical issue

### 6.1 Symptoms

On this MacBook8,1, the internal keyboard and touchpad could fail after boot or reboot. A problematic boot may have one or both of these characteristics:

- `applespi` appears loaded, yet input is unresponsive.
- The Apple SPI keyboard exists but the touchpad may be missing.
- The behaviour may vary between boots.
- Reloading `applespi` is not a reliable permanent remedy.

This is not a keyboard layout issue, a Cinnamon setting, or an application-level problem.

### 6.2 Identify the machine before changing anything

Run:

```bash
cat /sys/class/dmi/id/sys_vendor
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/product_version
```

The workaround in this document is intended only when the output includes:

```text
Apple Inc.
MacBook8,1
1.0
```

Also inspect the SPI device path and the input devices:

```bash
readlink -f /sys/bus/spi/devices/spi-APP000D:00 2>/dev/null || true
grep -E '^N: Name="Apple SPI (Keyboard|Touchpad)"' /proc/bus/input/devices
lsmod | grep -E '^(applespi|spi_pxa2xx|dw_dmac)'
```

### 6.3 Root cause and why this workaround exists

MacBook8,1 uses the Apple SPI keyboard/touchpad over an Intel LPSS SPI controller. Kernel development discussion for this model identifies a boot-time DMA handshake/interrupt-routing failure that can make the keyboard and trackpad unresponsive.

The working approach is to use **PIO (Programmed I/O)** rather than the problematic DMA initialization path for the affected SPI controller.

A Linux kernel patch series specifically targets MacBook8,1 with a future DMI-based PIO quirk. Until an appropriate Debian kernel includes that quirk, the reference system uses a GRUB kernel-parameter workaround:

```text
initcall_blacklist=dw_pci_driver_init
```

This prevents initialization of the problematic DesignWare PCI DMA path early in boot, allowing the Apple SPI path to use PIO.

> [!WARNING]
> `initcall_blacklist=dw_pci_driver_init` is a targeted workaround, not the ideal long-term upstream design. It affects initialization of that driver rather than expressing a device-specific kernel quirk. Use it only on a confirmed MacBook8,1, keep a backup of GRUB, and retest after future kernel upgrades.

### 6.4 Apply the persistent fix safely

#### Preconditions

- Confirm the exact DMI model is `MacBook8,1`.
- Have an external USB keyboard available in case the internal keyboard is unavailable.
- Ensure you have a recovery path: SSH over working Wi-Fi/Ethernet, a live USB, or physical console access.

#### Step 1: Back up GRUB

```bash
sudo cp -a /etc/default/grub "/etc/default/grub.before-macbook8-spi-pio.$(date +%Y%m%d-%H%M%S)"
```

#### Step 2: Edit the kernel command line

Open the file:

```bash
sudoedit /etc/default/grub
```

Set the line to include the parameter. Preserve any existing useful options. For the reference system, the final line is:

```text
GRUB_CMDLINE_LINUX_DEFAULT="initcall_blacklist=dw_pci_driver_init quiet"
```

#### Step 3: Generate GRUB configuration and reboot

Use the full path to avoid a non-root `PATH` difference:

```bash
sudo /usr/sbin/update-grub
sudo reboot
```

### 6.5 Verify success after reboot

Run all checks below. Do not assume success simply because `applespi` is listed as a module.

```bash
# 1. The kernel parameter must be active.
cat /proc/cmdline

# 2. Both internal devices must exist.
grep -E '^N: Name="Apple SPI (Keyboard|Touchpad)"' /proc/bus/input/devices

# 3. The critical PCI DMA module should not be active.
lsmod | grep -E '^dw_dmac(_pci)?' || true

# 4. Look for boot-time SPI failures.
sudo journalctl -b -k --no-pager | grep -Ei 'applespi|spi-APP000D|spi.*(timeout|error|fail)' || true
```

Expected result on the reference system:

```text
# /proc/cmdline contains:
initcall_blacklist=dw_pci_driver_init

# Both names appear:
Apple SPI Keyboard
Apple SPI Touchpad

# Important distinction:
dw_dmac_pci  -> absent
dw_dmac      -> may still be present; this is expected

# SPI timeout/error matches:
none in the verified boot
```

The exact Linux event numbers can change between boots. On the verified boot they were `event4` for the Apple SPI keyboard and `event5` / `mouse0` for the Apple SPI touchpad. Do not hard-code those event numbers in scripts.

### 6.6 Validate stability, not only one successful boot

A single successful boot demonstrates that the workaround can work. It does not prove every power-state path.

Use this test matrix before calling the installation stable:

| Test | What to verify |
|---|---|
| Normal reboot | Keyboard and touchpad work at login and after sign-in |
| Cold boot | Shut down fully, wait briefly, start again, and retest both devices |
| Repeated reboot | Repeat at least 2–3 times |
| Suspend/resume | Known broken on the reference machine (keyboard/touchpad and speakers fail after sleep); avoid suspend |
| Kernel update | Re-run the validation commands after every new kernel |

### 6.7 Temporary boot recovery if the persistent change is not active

If input fails and the persistent GRUB setting is absent or broken:

1. Use an external USB keyboard or SSH to reach the system.
2. At the GRUB menu, select the Debian entry and press `e`.
3. Append the following to the line beginning with `linux`:

   ```text
   initcall_blacklist=dw_pci_driver_init
   ```

4. Boot the one-time edited entry with the key shown by GRUB, commonly `Ctrl+X` or `F10`.
5. Once booted, apply the persistent configuration using section 6.4.

### 6.8 Roll back the workaround

If the workaround causes an unexpected regression, restore the timestamped backup created in section 6.4:

```bash
sudo cp -a /etc/default/grub.before-macbook8-spi-pio.YYYYMMDD-HHMMSS /etc/default/grub
sudo /usr/sbin/update-grub
sudo reboot
```

Replace `YYYYMMDD-HHMMSS` with the actual backup suffix.

Alternatively, remove only `initcall_blacklist=dw_pci_driver_init` with `sudoedit /etc/default/grub`, regenerate GRUB, and reboot.

---

## 7. What was tried, what worked, and what should not be mistaken for the fix

| Action | Result | Guidance |
|---|---|---|
| Confirming `applespi` was loaded | Insufficient by itself | A loaded module does not prove both input devices initialized correctly |
| Reloading `applespi` | At best temporary diagnostic action | Do not rely on it as a boot-stability fix |
| Rebooting without a kernel change | Input failure could recur | Confirms the issue is boot-path related, not a desktop setting |
| Identifying DMI model | Crucial | The device is `MacBook8,1`, not a MacBook Pro model |
| Blocking `dw_pci_driver_init` through GRUB | Successful | Both Apple SPI keyboard and touchpad were created after reboot; no SPI failure was found in the boot log |
| Cinnamon / keyboard-layout changes | Not a hardware fix | Desktop configuration does not repair low-level SPI initialization |

---

## 8. Hardware verification commands for humans and AI agents

Run this read-only collection before proposing changes. It is suitable for support tickets and agent-run diagnostics; review the output before sharing it publicly because hostnames, paths, and network details can be sensitive.

```bash
printf '=== OS ===\n'
cat /etc/os-release

printf '\n=== Kernel / boot command line ===\n'
uname -a
cat /proc/cmdline

printf '\n=== Exact Apple model ===\n'
cat /sys/class/dmi/id/sys_vendor
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/product_version

printf '\n=== CPU / memory ===\n'
lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core|Architecture'
free -h

printf '\n=== PCI devices and drivers ===\n'
lspci -nnk

printf '\n=== Apple SPI inputs ===\n'
grep -E '^N: Name="Apple SPI (Keyboard|Touchpad)"' /proc/bus/input/devices || true
lsmod | grep -E '^(applespi|spi_pxa2xx|dw_dmac)' || true

printf '\n=== Relevant boot log ===\n'
sudo journalctl -b -k --no-pager | grep -Ei 'applespi|spi-APP000D|dw_dmac|spi.*(timeout|error|fail)' || true

printf '\n=== Camera nodes ===\n'
ls -l /dev/video* 2>/dev/null || true

printf '\n=== Audio topology ===\n'
wpctl status || true
```

### Agent safety rules

An AI agent should:

1. Read and verify DMI identity before recommending a MacBook8,1-specific workaround.
2. Preserve the current GRUB configuration with a timestamped backup before modifying it.
3. Never claim keyboard/trackpad success from module presence alone; verify both named input devices after reboot.
4. Never claim webcam or audio is solved merely because PCI, ALSA, PipeWire, or a package is present; audio success requires the user hearing it (see [`docs/audio/AI_RUNBOOK.md`](docs/audio/AI_RUNBOOK.md)).
5. Never reboot a remote machine without explicit current-turn approval and a confirmed recovery channel.
6. Re-check the workaround after a kernel update and remove it only after the upstream DMI PIO quirk is confirmed in the installed kernel.

---

## 9. Webcam: known unsupported state

The reference system detects this PCI device:

```text
Broadcom 720p FaceTime HD Camera [14e4:1570]
```

However, there is no `/dev/video0` device. That means the normal V4L2 userspace interface is not available and the webcam should be considered **non-functional**.

Do not add random DKMS drivers or firmware blobs based only on a similar Mac model. A future webcam effort should begin with:

```bash
lspci -nnk | grep -A3 -Ei 'camera|multimedia'
lsusb
ls -l /dev/video* 2>/dev/null || true
sudo dmesg | grep -Ei 'facetime|camera|broadcom|v4l2|uvc'
```

Record the exact kernel version and device IDs with any solution.

---

## 10. Audio: internal speakers, headphones, microphone

Stock Debian plays the headphones but not the internal speakers. On MacBook8,1 the speakers are driven by a
4-channel TDM stream from the CS4208 codec, clocked by a PLL that the EFI firmware leaves locked. Linux breaks
that clock twice during boot: with an HDA link reset, and by enabling the microphone bias on the combo-jack pin.

The audio setup in this repository:

1. attaches `snd_hda_intel` to the CS4208 controller **without** a link reset (stock module options);
2. installs Debian's Cirrus codec driver with a small patch: the combo-jack mic pin stays disabled and a
   4-channel **CS4208 Speaker** device is added;
3. adds PipeWire outputs (**MacBook Speakers**, optional macOS-style **EQ**, **MacBook Headphones**,
   **MacBook Microphone**) and automatic switching when headphones are plugged in.

| Guide | For |
|---|---|
| [`docs/audio/README.md`](docs/audio/README.md) | Install, verify, uninstall, kernel updates, troubleshooting |
| [`docs/audio/AI_RUNBOOK.md`](docs/audio/AI_RUNBOOK.md) | AI agents: gated install with expected outputs and rollback |
| [`docs/audio/HOW_IT_WORKS.md`](docs/audio/HOW_IT_WORKS.md) | Root cause, measurements, design decisions |

Verified on the reference machine (kernel `6.12.107+deb13-amd64`, PipeWire 1.4.2, WirePlumber 0.5.8) after reboot:
speakers (desktop apps and `aplay`), headphones with automatic switching, internal microphone, HDMI audio unchanged.
Not working: audio after suspend/resume, external microphone on the combo jack.

---

## 11. Maintenance and upgrade policy

### After every kernel upgrade

1. Boot the new kernel.
2. Confirm the kernel parameter is still present:

   ```bash
   cat /proc/cmdline
   ```

3. Confirm both Apple SPI devices are present.
4. Test keyboard and touchpad physically.
5. Check the current boot’s kernel log for Apple SPI/DMA errors.
6. If the audio setup is installed: the new kernel boots with Debian's stock codec driver (speakers silent). Rebuild and reinstall it as described in [`docs/audio/README.md`](docs/audio/README.md#6-after-a-debian-kernel-update).

### Watch for the upstream solution

The preferred future end state is a Debian kernel containing the upstream DMI-specific PIO quirk for MacBook8,1. When a new kernel claims to include it:

1. Read the Debian changelog or relevant upstream commit.
2. Boot and test the new kernel **with the GRUB workaround still in place**.
3. Temporarily remove the workaround for one controlled test.
4. Test cold boot, reboot, and suspend/resume.
5. Only then permanently remove the workaround and retain the GRUB backup until confidence is established.

---

## 12. Appendix: reference sources

- [Debian 13 (trixie) release notes](https://www.debian.org/releases/stable/release-notes/)
- [Debian package: firmware-brcm80211](https://packages.debian.org/trixie/firmware-brcm80211)
- [Debian Wiki: Broadcom brcm80211](https://wiki.debian.org/brcm80211)
- [Linux kernel configuration reference: Apple SPI keyboard and trackpad](https://cateee.net/lkddb/web-lkddb/KEYBOARD_APPLESPI.html)
- [Linux kernel patch discussion: force PIO mode on MacBook8,1](https://patchew.org/linux/20260711055247.5412-1-fourdollars@debian.org/)
- [thomas-shirley/macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver): MacBook8,1 speaker clock analysis and layout100 EQ (credited in [`docs/audio/README.md`](docs/audio/README.md#credits))
- [leifliddy/macbook8-1-audio-driver-test issue #2](https://github.com/leifliddy/macbook8-1-audio-driver-test/issues/2): report of the TDM speaker path
- [Field report: Debian/Arch-style MacBook8,1 PIO workaround](https://openwebcraft.com/archive/2026/omarchy-4-on-12-macbook8-1) — useful corroboration, but not an authoritative substitute for kernel or Debian documentation.

---

## 13. Quick recovery card

**Use this only after confirming `MacBook8,1`:**

```bash
# Check model
cat /sys/class/dmi/id/product_name

# Backup GRUB
sudo cp -a /etc/default/grub "/etc/default/grub.before-macbook8-spi-pio.$(date +%Y%m%d-%H%M%S)"

# Edit /etc/default/grub and include:
# GRUB_CMDLINE_LINUX_DEFAULT="initcall_blacklist=dw_pci_driver_init quiet"
sudoedit /etc/default/grub

# Apply and reboot
sudo /usr/sbin/update-grub
sudo reboot

# Verify after boot
cat /proc/cmdline
grep -E '^N: Name="Apple SPI (Keyboard|Touchpad)"' /proc/bus/input/devices
lsmod | grep -E '^dw_dmac(_pci)?' || true
```

If both `Apple SPI Keyboard` and `Apple SPI Touchpad` are present, and `dw_dmac_pci` is absent, test the physical keyboard and touchpad. Then repeat through cold boot and regular reboot before declaring success.
