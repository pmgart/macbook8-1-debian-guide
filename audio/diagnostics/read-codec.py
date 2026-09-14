#!/usr/bin/env python3
"""Read-only snapshot of the CS4208 codec state on MacBook8,1.

Run:  sudo python3 audio/diagnostics/read-codec.py [/dev/snd/hwCxD0]
Uses only GET verbs plus SET_COEF_INDEX (selects which coef the next GET reads).
No playback, no module reload, no register value is changed.
Prints the vendor clock coef 0x1f (0x0000 = locked, 0x0400 = latched) and the speaker/headphone nodes.
"""
import datetime, fcntl, glob, os, re, struct, sys

HDA_IOCTL_VERB_WRITE = 0xC0084811  # _IOWR('H', 0x11, struct hda_verb_ioctl)

def find_cs4208():
    for path in sorted(glob.glob("/proc/asound/card*/codec#0")):
        try:
            if "CS4208" in open(path).read(200):
                return "/dev/snd/hwC%sD0" % re.search(r"card(\d+)", path).group(1)
        except OSError:
            pass
    return None


DEV = sys.argv[1] if len(sys.argv) > 1 else find_cs4208()
if not DEV:
    sys.exit("No CS4208 codec found in /proc/asound.")

# Codec coefs recorded right after the EFI chime (upstream efi_recover.py).
EFI = {i: 0 for i in range(0x40)}
EFI.update({0x00: 0x00c4, 0x02: 0x003a, 0x03: 0x0baa, 0x04: 0x0c04, 0x05: 0x1000,
            0x06: 0x9f9f, 0x07: 0x9f9f, 0x08: 0x1f1f, 0x09: 0x1f1f, 0x0a: 0x1f1f,
            0x0b: 0x1f1f, 0x0c: 0x9f9f, 0x0d: 0x9f9f, 0x0e: 0x9f9f, 0x0f: 0x9f9f,
            0x10: 0x1f1f, 0x11: 0x1f1f, 0x12: 0x1f1f, 0x13: 0x1f1f, 0x18: 0x0400,
            0x19: 0x0088, 0x1a: 0x00f3, 0x1b: 0x0002, 0x1c: 0x0103, 0x1d: 0x0bdf,
            0x1e: 0x016d, 0x22: 0x0080, 0x25: 0x0001, 0x33: 0x0821, 0x34: 0x3b21,
            0x36: 0x0034})

if os.geteuid() != 0:
    sys.exit("Run with sudo.")

fd = os.open(DEV, os.O_RDWR)
lines = []


def out(text):
    print(text)
    lines.append(text)


def verb(nid, v, parm=0):
    buf = bytearray(struct.pack("II", (nid << 24) | (v << 8) | parm, 0))
    fcntl.ioctl(fd, HDA_IOCTL_VERB_WRITE, buf)
    return struct.unpack("II", buf)[1]


def coef(i):
    verb(0x24, 0x500, i)
    return verb(0x24, 0xC00, 0)


out(f"MacBook8,1 CS4208 read-only codec snapshot {datetime.datetime.now().isoformat(timespec='seconds')}")
out(f"kernel {os.uname().release}")
c1f = coef(0x1f)
verdict = "CLOCK LOCKED (good)" if c1f == 0 else ("LATCHED CLOCK FAULT" if c1f & 0x400 else "UNEXPECTED")
out(f"*** coef 0x1f = 0x{c1f:04x} -> {verdict}")
out("coef differences vs EFI post-chime reference (0x00-0x3f):")
diffs = 0
for i in range(0x40):
    if i == 0x1f:
        continue
    value = coef(i)
    if value != EFI[i]:
        diffs += 1
        out(f"  0x{i:02x}: now 0x{value:04x}  EFI 0x{EFI[i]:04x}")
out(f"  {diffs} differences")
out("AFG 0x01: power 0x%08x  GPIO data 0x%02x mask 0x%02x dir 0x%02x"
    % (verb(0x01, 0xF05), verb(0x01, 0xF15), verb(0x01, 0xF16), verb(0x01, 0xF17)))
out("VPW 0x24: proc_state 0x%x" % verb(0x24, 0xF03))
for nid in (0x02, 0x0a):
    out("conv 0x%02x: format 0x%04x  stream/ch 0x%02x  power 0x%08x  digital 0x%04x"
        % (nid, verb(nid, 0xA00), verb(nid, 0xF06), verb(nid, 0xF05), verb(nid, 0xF0D)))
for nid in (0x10, 0x1d):
    out("pin  0x%02x: pinctl 0x%02x  power 0x%08x  sense 0x%08x  conn_sel %d"
        % (nid, verb(nid, 0xF07), verb(nid, 0xF05), verb(nid, 0xF09), verb(nid, 0xF01)))

