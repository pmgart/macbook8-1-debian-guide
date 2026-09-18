# MacBook8,1 FaceTime HD camera

This section documents the verified FaceTime HD camera setup for the 12-inch MacBook (Early 2015, MacBook8,1) running Debian 13.

## What was broken

The Broadcom 720p FaceTime HD camera (PCI `14e4:1570`) is visible in `lspci` but no `/dev/video0` appears. Three separate pieces were missing:

| Missing piece | Symptom |
|---|---|
| **Firmware 5.60.0** (from macOS 10.12.6) | The common 1.43.0 firmware reports `sensor count: 0` — the ISP cannot see the sensor |
| **`1675_01XX.dat`** sensor calibration | Without it, the ISP falls back to 640×480 and cannot enable the sensor interface |
| **DKMS driver from master** (not 0.7.0.2) | The hardcoded 1280×720 crop triggers `SIF errors: sifIrq = 0x804` followed by `IO: timeout` |

## Verified result

- **Resolution:** 848×588 @ 30 fps (active sensor area, not 480p)
- **Format:** YUYV 4:2:2
- **Device:** `/dev/video0`
- **Kernel module:** `facetimehd`, built via DKMS from pinned upstream commit
- **Firmware:** 5.60.0, SHA-256 verified

## Files

| File | Destination | Purpose |
|---|---|---|
| `scripts/install-camera.sh` | Run manually | Firmware extraction + DKMS install + verification |
| `scripts/restore-camera.sh` | Run manually | Complete removal |
| `docs/README.md` | This file | Human guide |
| `docs/HOW_IT_WORKS.md` | — | Technical root cause and measurements |

## Installation

### Prerequisites

```bash
sudo apt install dkms gcc make linux-headers-amd64 curl xz-utils v4l-utils cheese
```

### Step 1: Extract firmware (one-time, needs internet)

Firmware is not redistributable. Extract it from Apple's public macOS 10.12.6 update:

```bash
# Clone the vendored firmware tool
sudo apt install build-essential xz-utils curl
cd /tmp
git clone https://github.com/patjak/facetimehd-firmware.git
cd facetimehd-firmware
make FW_VER=5.60.0
```

This downloads the macOS 10.12.6 Combo Update from Apple's CDN, extracts `firmware.bin` (5.60.0), and carves out all 11 sensor calibration files including `1675_01XX.dat`.

Copy the results to the repository:

```bash
mkdir -p camera/firmware
cp /tmp/facetimehd-firmware/firmware.bin /tmp/facetimehd-firmware/*_01XX.dat camera/firmware/
```

### Step 2: Install

```bash
sudo bash camera/scripts/install-camera.sh
```

### Verification

```bash
# 1. Video device exists
ls -l /dev/video0

# 2. Correct resolution (848x588, not 640x480 fallback)
v4l2-ctl --list-formats-ext -d /dev/video0

# 3. Firmware loaded
sudo dmesg | grep facetimehd | grep "Loaded firmware"

# 4. Test capture
cheese  # or: ffplay /dev/video0
```

Expected `v4l2-ctl` output:

```
[0]: 'YUYV' (YUYV 4:2:2)
    Size: Discrete 848x588
        Interval: Discrete 0.033s (30.000 fps)
```

## After hibernate/sleep

The camera survives suspend/resume with no additional configuration. The DKMS module reloads automatically on boot. After hibernate the PCI link re-initialises from scratch, same as a cold boot.

## Revert

```bash
sudo bash camera/scripts/restore-camera.sh
sudo reboot
```

## Source and credits

- `patjak/facetimehd` — out-of-tree V4L2 driver
- `patjak/facetimehd-firmware` — firmware extraction tool (SHA-256 verified)
- `leifliddy` — 480p patch and sensor file discovery (MacBook9,1, 2019)
- `randyg939` — MacBook8,1 verification on Ubuntu 24.04, kernel 6.8
- `doctor` — complete 848×588 writeup (MacBook10,1, 2026-08-17)
- `channelramble/macbook81-linux` — DKMS packaging and bdc_pci blacklist
