# How the MacBook8,1 internal speaker fix works

This explains *why* each part of the audio setup exists, with the measurements that led to it. For installation
see [README.md](README.md); for an AI-driven install see [AI_RUNBOOK.md](AI_RUNBOOK.md).

All measurements were taken on the reference machine (MacBook8,1, Debian 13, kernel `6.12.107+deb13-amd64`)
between 2026-09-13 and 2026-09-14.

---

## 1. Hardware facts

| Item | Value |
|---|---|
| Codec | Cirrus Logic CS4208, vendor `0x10134208`, subsystem `0x106b6400` |
| HDA controller | Intel PCH HD Audio, PCI `0000:00:1b.0` (the HDMI audio controller is `0000:00:03.0`) |
| Internal speakers | **Digital TDM path**: converter node `0x0a` → pin `0x1d` → class-D amplifiers, 4 channels, 44.1 kHz, 16-bit (HDA stream format `0x4013`) |
| Headphones | Analog: DAC `0x02` → jack pin `0x10` |
| Internal microphone | Pin `0x19` |
| Combo-jack mic input | Pin `0x18` |
| Vendor processing widget | Node `0x24` (coefficients) |
| Clock health signal | Vendor coef `0x1f`: `0x0000` = codec PLL locked, `0x0400` = latched clock fault |

The speaker path, format and node numbers were first identified by other MacBook8,1 owners (see Credits in
[README.md](README.md)). The clock signal `0x1f` was described in the thomas-shirley project. What was new here
was measuring it on Debian at every step.

## 2. Why stock Debian has working headphones but silent speakers

The EFI firmware fully initialises the speaker chain at every boot (that is the startup chime). Linux then
destroys that state in two separate places:

| Measurement | coef `0x1f` |
|---|---|
| Boot with `modprobe.blacklist=snd_hda_intel`, read with no driver bound | `0x0000` locked, all coefs equal the post-chime state, `0x0a` format `0x4013` |
| Stock Debian after normal boot | `0x0400` latched |

The analog headphone path keeps working with a latched clock; the TDM speaker path does not.

### 2.1 Cause 1: controller link reset at probe

`snd_hda_intel` resets the HDA link when it attaches (`hda_intel_init_chip(chip, true)`). This wipes the EFI clock
setup. Debian's stock driver can already skip it: the module option **`probe_only`** bit `2` calls
`hda_intel_init_chip(chip, false)` (`sound/pci/hda/hda_intel.c` in 6.12). Without a reset the codec-present bits are
not refreshed, so **`probe_mask=0x101`** forces codec 0. `single_cmd=1` (immediate command mode) makes the un-reset
link enumerate reliably, and `power_save=0` keeps the codec in D0.

These options are **arrays in controller probe order** (PCI address order). On MacBook8,1 index 0 is the HDMI
controller and index 1 is the CS4208 controller, hence `probe_only=0,2 probe_mask=-1,0x101`. Putting `2` in the
first position resets the wrong controller: the options then hit HDMI (its codec fails to probe) and the speakers
stay silent. `install-driver.sh` computes the index from the PCI list.

Result with only this change: clock still latched (`0x0400`), so something later breaks it too.

### 2.2 Cause 2: enabling the combo-jack microphone pin

A logging build of the codec modules read coef `0x1f` after every init step:

```text
cs4208 probe / pre-probe fixup / amp caps / parse_auto_config   0x0000
cs_init: stock cs4208 coef verbs (0x33, 0x34)                   0x0000
gen_init: apply_verbs, multi_out, extra_out, multi_io, aamix    0x0000
gen_init: analog_input                                          0x0400   <- latch
```

`init_analog_input()` only writes pin controls on this codec (there is no loopback mixer). Skipping individual
writes showed the exact culprit:

| Skipped | Clock | Headphones | Internal mic |
|---|---|---|---|
| pin `0x18` and `0x19` | `0x0000` | work | silent |
| pin `0x18` only (Mic jack, target `0x24` = input + VREF 80%) | `0x0000` | work | **work** |

So the **VREF bias on the combo-jack mic pin `0x18` latches the codec clock**. The cost of avoiding it is that an
external microphone on the headphone jack is not supported. Input source setup, digital init, automute and pin
power handling do not latch the clock.

## 3. The driver patch (`audio/driver/mb81-speakers.patch`)

A small patch to Debian's own `sound/pci/hda/patch_cirrus.c`, active only for SSID `106b:6400`:

1. **Pin config override before the generic parser:** pins `0x18` and `0x1d` are marked "not connected"
   (`0x411111f0`). This keeps Linux from ever enabling VREF on `0x18`, and stops the generic driver from claiming
   converter `0x0a` for its own analog PCM. No change to the generic HDA module is needed.
2. **A separate `CS4208 Speaker` PCM** (ALSA device 2): 4 channels, 44.1 kHz only, S16_LE only.
3. **Its `prepare()` mirrors the EFI chime playback sequence** (known to be audible from the driverless
   verification tone in the thomas-shirley project):
   - converter `0x0a` → D0, then restore EFI coefs `0x33 = 0x0821`, `0x34 = 0x3b21` (the stock init writes
     `0x0001`/`0x1c01`);
   - converter channel count = 4 (`SET_CVT_CHAN_COUNT 3`);
   - `snd_hda_codec_setup_stream()`, then read back and fix the format / stream tag **only if stale**
     (a needless format rewrite mid-stream de-syncs the TDM link);
   - pin `0x1d`: connection 0, `PIN_OUT`;
   - vendor verb `0x7f0 = 1` on node `0x24` (TDM enable);
   - GPIO mask `0x09`, direction `0x01`, data `0x01` (EFI values while playing).
4. **One log line** after init: `MacBook8,1 speakers: codec clock locked (coef 0x1f=0x0000)` or `LATCHED`.

Verified readback during playback: `0x0a fmt=0x4013 conv=0x50 chcnt=0x3 D0 | 0x1d pinctl=0x40 | tdm=1 |
gpio 0x01/0x09/0x01`, clock `0x0000` before, during and after.

## 4. PipeWire / WirePlumber

- The speaker PCM is not part of any ALSA card profile (ACP/UCM), so `51-mb81-speakers.conf` switches only the
  CS4208 card (`alsa_card.pci-0000_00_1b.0`) to raw-PCM mode. WirePlumber then creates one node per PCM,
  event-driven, so the speaker node appears whenever the card does (a static adapter can lose a race with the
  card at cold boot). Nodes: `MacBook Speakers` (device 2, 4ch, stereo upmixed to all four), `MacBook Headphones`
  (device 0 playback), `MacBook Microphone` (device 0 capture). HDMI keeps its normal profile.
- The optional EQ (`speaker-eq.sh`) is a PipeWire filter-chain from the thomas-shirley project, derived from
  macOS layout100. **Do not set `node.dont-reconnect` on its playback stream:** at PipeWire start the raw
  speaker node does not exist yet; with dont-reconnect the stream fails and the filter-chain module unloads
  itself without an error message.
- Raw-PCM mode has no jack-based port availability, so `audio-autoswitch.sh` watches the ALSA
  `Headphone Jack` control and changes the default output on each plug/unplug. Streams follow the default
  (WirePlumber `linking.follow-default-target`). It never changes the saved default at login.

## 5. What did not work (so nobody repeats it)

| Attempt | Why it failed |
|---|---|
| Replacing codec driver only (several variants) | The stock controller reset had already latched the clock |
| Replaying a captured macOS verb sequence after generic init | Headphones went silent too, and the clock latch (caused earlier) remained |
| Three patched modules at once, installed without measurement | No way to tell which part failed |
| `speaker-test -t wav` on the speaker PCM | The ALSA sample files are 48 kHz; the PCM accepts only 44.1 kHz. Use `-t pink` or `aplay -D plughw:...` |
| Driving codec GPIO 4/5 as amplifier enables | Not needed here; also reported as unnecessary by another MacBook8,1 owner |

## 6. Known limitations

- **Suspend/resume:** the resume path resets the HDA link (`hda_intel_init_chip(chip, true)`), which latches
  the clock; speakers stay silent until reboot. (On the reference machine sleep also breaks the Apple SPI
  keyboard/trackpad, so this is a separate project.)
- **Kernel updates:** the module is built per kernel. After a kernel update the new kernel boots with Debian's
  stock codec module (headphones work, speakers silent) until you rebuild and reinstall.
- **External microphone on the combo jack:** not supported (its VREF latches the clock).
- The patch targets the Debian 6.12 layout (`sound/pci/hda/patch_cirrus.c`). Kernels from 6.17 moved this code
  to `sound/hda/codecs/cirrus/`; the patch would need porting.
