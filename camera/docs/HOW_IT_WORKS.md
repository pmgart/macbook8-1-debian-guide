# How the FaceTime HD camera fix works

This explains *why* each part exists, with the measurements that led to it. For installation see [README.md](README.md).

All measurements were taken on the reference machine (MacBook8,1, Debian 13, kernel `6.12.107+deb13-amd64`) on 2026-09-18.

## 1. Hardware facts

| Item | Value |
|---|---|
| PCI device | `02:00.0` Broadcom 720p FaceTime HD Camera |
| PCI ID | `14e4:1570` |
| USB alias conflict | `bdc_pci` (Broadcom USB Device Controller) claims the same ID; must be blacklisted |
| Sensor | Sony IMX, **active area 848×588** (not the 640×480 fallback) |
| Interface | PCIe, DMA, ISP-based image pipeline |

## 2. Why stock drivers fail

Three independent failures compound:

### 2.1 Firmware 1.43.0 cannot see the sensor

The community's default firmware (extracted from OS X 10.11.5) predates the 12-inch MacBook. dmesg shows:

```
facetimehd: Loaded firmware, size: 1392kb
facetimehd: ISP woke up after 0ms
FWMSG: ERR: Sensor is null after hNVStorage Validate
sensor id: 0000 0000
sensor count: 0
```

The ISP boots perfectly, DDR40 calibrates, PCI links up — but finds no sensor because 1.43.0 does not know the sensor part number.

**Fix:** firmware 5.60.0 from macOS Sierra 10.12.6.

Result:

```
sensor id: 0005 9774
sensor count: 1
```

### 2.2 The 1675_01XX.dat sensor file is nowhere public

With the sensor visible, the driver requests `1675_01XX.dat`. The Boot Camp driver everyone extracts from does not contain it. The 11 sensor set files are in macOS's `AppleCameraAssistant` (the DAL plugin's helper binary), not the kext.

Without the dat file, the ISP reports 640×480 fallback geometry. With it, the real active area is exposed: `[0, 0][848, 588]`.

### 2.3 The hardcoded 1280×720 crop

patjak master (commit `98b55fd`) replaces the hardcoded 1280×720 crop with sensor-detected geometry. Without it:

```
CROP -> [0, 0][1280, 720] within [0, 0][848, 588]
FWMSG: ERR: FlowIC00: SIF errors: sifIrq = 0x804!
facetimehd: IO: timeout
```

The sensor interface faults on every frame because the crop exceeds the active array.

**Important:** commit `98b55fd` is not in any tagged release (0.7.0.2 is the latest tag). Building from master is required for the 12-inch MacBook.

## 3. The verified path

On the reference machine, all three pieces together produce:

```
[facetimehd] Found FaceTime HD camera with device id: 1570
[facetimehd] S2 PCIe link init succeeded
[facetimehd] DDR40 PHY PLL locked on safe settings
[facetimehd] Loaded firmware, size: 1384kb
[facetimehd] ISP woke up after 0ms
[facetimehd] Full memory verification succeeded!
```

v4l2 enumeration:

```
[0]: 'YUYV' (YUYV 4:2:2)
    Size: Discrete 848x588
    Interval: Discrete 0.033s (30.000 fps)
```

Frame capture test: 614400 bytes for 640×480 YUYV (tested with `v4l2-ctl --stream-count=1`).

## 4. Firmware extraction details

Firmware is carved from the macOS 10.12.6 Combo Update (`macOSUpdCombo10.12.6.dmg`, ~1.5 GB download, ~10 MB payload). The payload is `pbzx`-compressed; each range in the Makefile covers one complete xz stream. The `AppleCameraInterface` driver spans two adjacent chunks.

The extraction script validates by SHA-256:
- Driver: `e959244db1e0561f6d5590c8e5000a16816c592e2820bafe89af0bea75556aca`
- Firmware: `240ef2e991f1d089d8228ce11d92b66bfa4b3d7289ec4fee228b64a713024330`

Sensor set files are carved from `AppleCameraAssistant` by offset with known size (all ~18–19 KB each).

## 5. What did not work

| Attempt | Why it failed |
|---|---|
| Firmware 1.43.0 + master driver | `sensor count: 0` — ISP cannot see the sensor |
| Firmware 5.60.0 + 0.7.0.2 driver | `sifIrq = 0x804` + `IO: timeout` — hardcoded crop |
| `bdc_pci` bound to the PCI device | Claims the same PCI ID; `facetimehd` cannot probe |
| Building from distro package (Arch `facetimehd-dkms`) | Built from 0.7.0.2, missing the crop fix |

## 6. Interaction with other fixes

| Fix | Interaction |
|---|---|
| Audio (CS4208) | None. Different subsystem. |
| Sleep (SPI) | None. Camera is on a separate PCI device (`02:00.0` vs `00:15.4`). Survives suspend/resume; hibernate behaves as cold boot. |
| Wi-Fi (brcmfmac) | Shares the `brcmfmac` module family but different PCI device. No conflict. |
| Bluetooth | `bd` module is blacklisted; Bluetooth is unaffected. |

## 7. Verification checklist

- [ ] `lspci` shows `02:00.0 Broadcom 720p FaceTime HD Camera`
- [ ] `ls -l /dev/video0` exists
- [ ] `v4l2-ctl --list-formats-ext -d /dev/video0` shows `Discrete 848x588` (not 640×480)
- [ ] `sudo dmesg \| grep facetimehd` shows `Loaded firmware, size: 1384kb` and no `sifIrq` errors
- [ ] `cheese` or `qv4l2` displays live video with green LED active
- [ ] Frame capture (`v4l2-ctl --stream-count=1`) produces non-zero data
