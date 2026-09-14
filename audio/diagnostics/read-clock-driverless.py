#!/usr/bin/env python3
"""Read CS4208 clock coef 0x1f with NO audio driver bound (MacBook8,1).

Purpose: tell whether EFI leaves the codec clock locked (0x1f = 0x0) before Linux
touches the link. Only valid on a boot where snd_hda_intel was NOT loaded, e.g.
GRUB 'e' -> add `modprobe.blacklist=snd_hda_intel` to the linux line (one boot only).

Run:  sudo python3 audio/diagnostics/read-clock-driverless.py

Safety: never resets or powers the link. If the link is not already running
(GCTL.CRST = 0) it aborts instead of bringing it up. Uses the controller's
immediate-command registers (ICOI/ICII/ICIS) to send read verbs plus
SET_COEF_INDEX. No stream, no PCI power change, no register value is written.
"""
import datetime, mmap, os, struct, sys, time

PCIDEV = "/sys/bus/pci/devices/0000:00:1b.0"
GCTL, ICOI, ICII, ICIS = 0x08, 0x60, 0x64, 0x68

if os.geteuid() != 0:
    sys.exit("Run with sudo.")
if os.path.exists(f"{PCIDEV}/driver") or os.path.exists("/sys/module/snd_hda_intel"):
    sys.exit("ABORT: snd_hda_intel is loaded/bound. This reading is only meaningful on a boot "
             "with modprobe.blacklist=snd_hda_intel.")

with open(f"{PCIDEV}/config", "rb") as cfg:
    cfg.seek(4)
    command = struct.unpack("<H", cfg.read(2))[0]
if (command & 0x2) == 0:
    sys.exit(f"ABORT: controller memory decoding is off (PCI command 0x{command:04x}); not touching it.")

fd = os.open(f"{PCIDEV}/resource0", os.O_RDWR | os.O_SYNC)
bar = mmap.mmap(fd, 0x4000)
rd32 = lambda o: struct.unpack_from("<I", bar, o)[0]
rd16 = lambda o: struct.unpack_from("<H", bar, o)[0]
wr32 = lambda o, v: struct.pack_into("<I", bar, o, v)
wr16 = lambda o, v: struct.pack_into("<H", bar, o, v)

gctl = rd32(GCTL)
if (gctl & 1) == 0:
    sys.exit(f"ABORT: HDA link is in reset (GCTL 0x{gctl:08x}); refusing to bring it up.")


def icmd(word):
    for _ in range(1000):
        if not (rd16(ICIS) & 1):
            break
        time.sleep(0.0001)
    else:
        raise TimeoutError("immediate command busy")
    wr16(ICIS, 0x2)          # clear previous result-valid flag
    wr32(ICOI, word)
    wr16(ICIS, 0x1)          # send
    for _ in range(1000):
        status = rd16(ICIS)
        if not (status & 1):
            if not (status & 2):
                raise IOError(f"no response to 0x{word:08x}")
            return rd32(ICII)
        time.sleep(0.0001)
    raise TimeoutError(f"timeout on 0x{word:08x}")


def verb(nid, v, payload=0):         # 12-bit verb, 8-bit payload
    return icmd((nid << 20) | (v << 8) | payload)


def verb16(nid, v, payload):         # 4-bit verb, 16-bit payload (coef index)
    return icmd((nid << 20) | (v << 16) | payload)


def coef(i):
    verb16(0x24, 0x5, i)
    return verb(0x24, 0xC00)


lines = [f"MacBook8,1 driverless clock read {datetime.datetime.now().isoformat(timespec='seconds')}",
         f"kernel {os.uname().release}  GCTL 0x{gctl:08x}  cmdline: {open('/proc/cmdline').read().strip()}",
         f"vendor id 0x{verb(0x00, 0xF00, 0x00):08x}"]
c1f = coef(0x1f)
lines.append(f"*** coef 0x1f = 0x{c1f:04x} -> " + ("CLOCK LOCKED (EFI state intact)" if c1f == 0 else "LATCHED CLOCK FAULT"))
for i in (0x00, 0x03, 0x33, 0x34):
    lines.append(f"coef 0x{i:02x} = 0x{coef(i):04x}")
lines.append("GPIO data/mask/dir 0x%02x/0x%02x/0x%02x" % (verb(0x01, 0xF15), verb(0x01, 0xF16), verb(0x01, 0xF17)))
lines.append("conv 0x0a format 0x%04x stream/ch 0x%02x" % (verb(0x0a, 0xA00), verb(0x0a, 0xF06)))
print("\n".join(lines))
