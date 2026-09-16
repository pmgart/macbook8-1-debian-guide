# Sleep and hibernate on MacBook8,1

This explains *why* the sleep setup exists, with the measurements that led to it. For installation see [README.md](README.md).

All measurements were taken on the reference machine (MacBook8,1, Debian 13, kernel `6.12.107+deb13-amd64`) on 2026-09-16.

## 1. Hardware facts

| Item | Value |
|---|---|
| SPI controller | PCI `0000:00:15.4`, Intel LPSS GSPI |
| SPI driver | `spi_pxa2xx_pci` (DesignWare DMA on `00:15.0` blacklisted; PIO fallback) |
| Input driver | `applespi` (out-of-tree, DKMS from `cb22/macbook12-spi-driver`) |
| HDA controller | PCI `0000:00:1b.0`, CS4208 codec |
| Swap | Partition `/dev/nvme0n1p3`, 7.9 GB, priority -2 |

## 2. Why suspend broke the keyboard

With `mem_sleep_default=deep` (S3), the Intel GSPI controller loses IRQ 21 across the resume path. The `applespi` driver then times out on every SPI transfer. The keyboard and trackpad are dead until reboot.

Boot logs on a working system:

```
pxa2xx_spi_pci 0000:00:15.4: no DMA channels available, using PIO
input: Apple SPI Keyboard as /devices/pci0000:00/0000:00:15.4/spi_master/spi1/spi-APP000D:00/input/input4
applespi spi-APP000D:00: modeswitch done.
```

After S3 resume, the IRQ is missing and `applespi` spews `-110` timeouts. The module reload alone does not help because the PCI controller itself is in a bad state.

## 3. Why unbind/rebind works

The sleep hook removes the entire SPI stack before sleep:

```
modprobe -r applespi
echo 0000:00:15.4 > /sys/bus/pci/drivers/pxa2xx_spi_pci/unbind
```

After wake it re-attaches:

```
echo 0000:00:15.4 > /sys/bus/pci/drivers/pxa2xx_spi_pci/bind
modprobe applespi
```

This forces a complete PCI probe and SPI master re-initialisation. The IRQ is re-requested from scratch, so the lost-IRQ state is never entered. The hook polls `/proc/bus/input/devices` for `Apple SPI Keyboard` and retries up to 3 times.

## 4. Why hibernate needs Wi-Fi unload

The Broadcom BCM43602 (`brcmfmac`) driver hangs during the hibernate image write on this machine. The hook unloads `brcmfmac_wcc` and `brcmfmac` before hibernate and reloads them after. This is documented upstream in `channelramble/macbook81-linux` and Debian bug reports.

## 5. Why suspend-then-hibernate

s2idle keeps the SPI controller powered, but still costs battery (~1-5 % per hour on the 39 Wh unit). Hibernate writes RAM to swap and powers off completely (0 W), with the trade-off of a full boot on wake (~10-15 seconds).

The hybrid approach gives the best of both:

| Pause length | Action | Wake time | Battery | Keyboard after wake |
|---|---|---|---|---|
| < 2 hours | s2idle | Instant | ~1-5 %/h | Yes (hook handles it) |
| > 2 hours | Hibernate | ~10-15 s | 0 % | Yes (full boot) |

`HibernateDelaySec=2h` is the compromise. Adjust in `/etc/systemd/logind.conf.d/mb81.conf`.

## 6. Why `HibernateMode=shutdown`

ACPI S4 platform mode (the default) hangs on MacBook8,1. `shutdown` writes the image, calls `reboot` with EFI `HibernateLocation` set, and the firmware boots directly into resume. This is the reliable path documented by multiple owners.

## 7. Interaction with the audio fix

The audio fix (`audio/`) works by keeping the CS4208 codec clock initialised from EFI boot (avoiding HDA link reset). Any suspend/resume path (s2idle or S3) resets the HDA link and latches the clock. Therefore:

- After **s2idle**: internal speakers stay silent until reboot. Headphones work.
- After **hibernate**: speakers work because the full boot re-runs EFI initialisation.

This is not fixable from userspace — it is a driver-level resume callback limitation. The audio fix and sleep fix are compatible; they do not interfere with each other.

## 8. What did not work

| Attempt | Why it failed |
|---|---|
| `rmmod applespi && modprobe applespi` alone after resume | IRQ 21 is lost at the PCI controller level, not the driver level |
| s2idle without the sleep hook | applespi resume callback hangs; same problem as S3 |
| `HibernateMode=platform` | Hangs during ACPI S4 entry |
| zram swap for hibernate | Image write hangs; use a real swap partition |

## 9. Verification checklist

- [ ] `cat /sys/power/mem_sleep` shows `[s2idle] deep`
- [ ] `busctl call org.freedesktop.login1 ... CanHibernate` returns `"yes"`
- [ ] Close lid 30 s, open: keyboard and trackpad work
- [ ] `sudo systemctl hibernate`: machine powers off, boot restores session
- [ ] After hibernate: internal speakers work (EFI clock re-initialised)
- [ ] `/var/log/mb81-sleep.log` shows `applespi restored` after each wake
