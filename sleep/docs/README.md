# MacBook8,1 sleep and hibernate fix

This section documents the verified sleep/wake and hibernate setup for the 12-inch MacBook (Early 2015, MacBook8,1) running Debian 13.

## What was broken

| Symptom | Root cause |
|---|---|
| After closing the lid (suspend to RAM / S3 deep), the Apple SPI keyboard and touchpad are dead until reboot | The Intel GSPI controller (PCI `00:15.4`) loses IRQ 21 across the S3 resume path. The `applespi` driver times out repeatedly. |
| After any suspend/resume (S3 or s2idle), the internal speakers stay silent | The HDA link reset in the resume path latches the CS4208 codec clock. This is documented in `audio/` and cannot be fixed from Linux userspace. |
| Hibernate image write hangs | ACPI S4 platform mode + Broadcom Wi-Fi (brcmfmac) during image write. |

## The solution: suspend-then-hibernate hybrid

We configure **s2idle** as the default suspend mode for short periods (lid closed briefly), with an automatic fallback to **hibernate** after a delay. This gives:

- **Fast wake** for short pauses (s2idle)
- **Zero battery drain** for long pauses (hibernate writes RAM to swap and powers off completely)
- **Working keyboard + trackpad** after every wake
- **Working speakers** after hibernate (EFI re-initialises the codec clock from scratch)

## Files

| File | Destination | Purpose |
|---|---|---|
| `scripts/mb81-applespi` | `/usr/lib/systemd/system-sleep/mb81-applespi` | systemd sleep hook: detach SPI controller before sleep, re-attach after wake; unload Wi-Fi before hibernate image write |
| `scripts/mb81-sleep.conf` | `/etc/systemd/sleep.conf.d/mb81.conf` | `SuspendState=s2idle`, `HibernateMode=shutdown` |
| `scripts/mb81-logind.conf` | `/etc/systemd/logind.conf.d/mb81.conf` | `HandleLidSwitch=suspend-then-hibernate`, `HibernateDelaySec=2h` |
| GRUB parameters | `/etc/default/grub` | `mem_sleep_default=s2idle resume=UUID=<swap-uuid>` |

## Installation

```bash
# 1. Install the sleep hook
sudo install -m 0755 -o root -g root sleep/scripts/mb81-applespi /usr/lib/systemd/system-sleep/mb81-applespi

# 2. Install systemd sleep configuration
sudo mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
sudo install -m 0644 -o root -g root sleep/scripts/mb81-sleep.conf /etc/systemd/sleep.conf.d/mb81.conf
sudo install -m 0644 -o root -g root sleep/scripts/mb81-logind.conf /etc/systemd/logind.conf.d/mb81.conf

# 3. Add kernel parameters to GRUB
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mem_sleep_default=s2idle resume=UUID=63275bb6-4990-4e65-a1db-74b5fe0cdb45"/' /etc/default/grub
sudo update-grub
sudo update-initramfs -u

# 4. Reboot to activate
sudo reboot
```

**Note:** Replace the swap UUID in step 3 with your actual swap partition UUID (find it with `sudo blkid /dev/nvme0n1p3` or check `/etc/fstab`).

## Verification after reboot

```bash
# 1. s2idle is now the default
cat /sys/power/mem_sleep
# Expected: [s2idle] deep

# 2. Hibernate is available
busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate
# Expected: s "yes"

# 3. Suspend-then-hibernate is available
busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspendThenHibernate
# Expected: s "yes"

# 4. Test short sleep (s2idle)
# Close the lid for 30 seconds, open it. Keyboard and trackpad must work.

# 5. Test hibernate manually
sudo systemctl hibernate
# Machine powers off completely. Press power button. Session is restored.
```

## How the hook works

The sleep hook runs in `/usr/lib/systemd/system-sleep/` before and after every sleep state:

**Before sleep (pre):**
- `modprobe -r applespi` — unload the Apple SPI input driver
- `echo 0000:00:15.4 > /sys/bus/pci/drivers/pxa2xx_spi_pci/unbind` — unbind the SPI controller from its PCI driver
- If hibernating: `modprobe -r brcmfmac_wcc brcmfmac` — unload Broadcom Wi-Fi

**After wake (post):**
- `echo 0000:00:15.4 > /sys/bus/pci/drivers/pxa2xx_spi_pci/bind` — re-bind the SPI controller
- `modprobe applespi` — reload the Apple SPI driver
- Retry up to 3 times with polling until `Apple SPI Keyboard` appears in `/proc/bus/input/devices`
- If hibernating: reload Wi-Fi

This avoids the IRQ-lost deadlock because the SPI controller makes a clean PCI re-probe instead of trying to resume from a broken state.

## Audio after sleep

- **s2idle resume:** speakers stay silent (HDA link reset latches the codec clock). Headphones still work.
- **Hibernate resume:** speakers work because the EFI boot chime re-initialises the codec clock.

To restore speakers after s2idle without rebooting, you can manually reload the HDA driver with the no-reset options (see `audio/README.md`), but this is not automated yet.

## Revert

To remove the sleep fix:

```bash
sudo rm /usr/lib/systemd/system-sleep/mb81-applespi
sudo rm /etc/systemd/sleep.conf.d/mb81.conf
sudo rm /etc/systemd/logind.conf.d/mb81.conf
sudo sed -i 's/ mem_sleep_default=s2idle resume=UUID=[^ ]*//' /etc/default/grub
sudo update-grub
sudo update-initramfs -u
sudo reboot
```

## Source and credits

- `channelramble/macbook81-linux` — sleep hook design and hibernate fixes
- `JadeJitsu/macbook81-cachyos-spi-fix` — CachyOS adaptation
- `matthiasjg` (basecamp/omarchy#1954) — root cause analysis
- Upstream kernel patch series: "[PATCH v4 0/3] Input/SPI: fixes for MacBook8,1" (linux-input, July 2026)
