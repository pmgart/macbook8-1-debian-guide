#!/usr/bin/env python3
"""Check or clear ONLY the mute bit of the Apple EFI variable SystemAudioVolume (MacBook8,1).

A set mute bit (value byte & 0x80) silences the startup chime; the reference machine had it cleared
before the Linux speaker work. Whether a muted chime prevents the Linux speaker fix was not tested.

  python3 audio/diagnostics/efi-audio-mute.py check        # read-only, no sudo needed
  sudo python3 audio/diagnostics/efi-audio-mute.py apply   # backup, clear bit 0x80, verify readback

The original value is saved to /var/lib/mb81-audio-safety/SystemAudioVolume.before-unmute.bin.
"""

from __future__ import annotations

import argparse
import errno
import os
import subprocess
from pathlib import Path

GUID = "7c436110-ab2a-4bbb-a880-fe41995c9f82"
EXPECTED_NAME = f"SystemAudioVolume-{GUID}"
TARGET = Path("/sys/firmware/efi/efivars") / EXPECTED_NAME
BACKUP = Path("/var/lib/mb81-audio-safety/SystemAudioVolume.before-unmute.bin")
CHATTR = "/usr/bin/chattr"


def validate_target(path: Path) -> None:
    if path.name != EXPECTED_NAME or path.parent != TARGET.parent:
        raise ValueError(f"unexpected EFI variable target: {path}")


def unmuted_bytes(raw: bytes) -> bytes:
    if len(raw) != 5:
        raise ValueError(f"SystemAudioVolume must be exactly 5 bytes, got {len(raw)}")
    if raw[:4] not in (bytes.fromhex("07 00 00 00"), bytes.fromhex("07 00 00 80")):
        raise ValueError(f"unexpected EFI attributes: {raw[:4].hex(' ')}")
    return bytes.fromhex("07 00 00 00") + bytes([raw[4] & 0x7F])


def write_new_backup(path: Path, raw: bytes) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    with path.open("xb") as handle:
        handle.write(raw)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(path, 0o600)


def write_or_verify_backup(path: Path, raw: bytes) -> None:
    if path.exists():
        existing = path.read_bytes()
        if existing != raw:
            raise RuntimeError("existing backup differs from current EFI value")
        return
    write_new_backup(path, raw)


def needs_change(raw: bytes) -> bool:
    if len(raw) != 5:
        raise ValueError(f"SystemAudioVolume must be exactly 5 bytes, got {len(raw)}")
    return bool(raw[4] & 0x80)


def fsync_efivar(fd: int, fsync_func=os.fsync) -> None:
    try:
        fsync_func(fd)
    except OSError as error:
        if error.errno != errno.EINVAL:
            raise


def verify_readback(actual: bytes, requested: bytes) -> None:
    if len(actual) != 5 or len(requested) != 5:
        raise RuntimeError("EFI readback mismatch: unexpected size")
    valid_actual_attrs = (
        bytes.fromhex("07 00 00 00"),
        bytes.fromhex("07 00 00 80"),
    )
    if actual[:4] not in valid_actual_attrs or actual[4] != requested[4]:
        raise RuntimeError(
            f"EFI readback mismatch: expected value 0x{requested[4]:02x}, "
            f"got {actual.hex(' ')}"
        )


def describe(raw: bytes) -> str:
    if len(raw) != 5:
        return f"bytes={raw.hex(' ')} invalid_size={len(raw)}"
    return (
        f"bytes={raw.hex(' ')} value=0x{raw[4]:02x} "
        f"mute_bit={'SET' if raw[4] & 0x80 else 'CLEAR'}"
    )


def inspect() -> int:
    validate_target(TARGET)
    raw = TARGET.read_bytes()
    print(f"target={TARGET}")
    print(describe(raw))
    return 0


def apply() -> int:
    if os.geteuid() != 0:
        raise PermissionError("apply must run as root")
    validate_target(TARGET)
    old = TARGET.read_bytes()
    new = unmuted_bytes(old)
    print(f"before: {describe(old)}")
    if not needs_change(old):
        print("No change needed: mute bit already clear")
        return 0

    write_or_verify_backup(BACKUP, old)
    print(f"backup={BACKUP}")
    subprocess.run([CHATTR, "-i", str(TARGET)], check=True)
    write_succeeded = False
    rollback = bytes.fromhex("07 00 00 00") + old[4:5]
    try:
        with TARGET.open("wb", buffering=0) as handle:
            handle.write(new)
            fsync_efivar(handle.fileno())
        actual = TARGET.read_bytes()
        verify_readback(actual, new)
        write_succeeded = True
    finally:
        if not write_succeeded:
            try:
                with TARGET.open("wb", buffering=0) as handle:
                    handle.write(rollback)
                    fsync_efivar(handle.fileno())
            except Exception as restore_error:
                print(f"CRITICAL: restore attempt failed: {restore_error}")
        subprocess.run([CHATTR, "+i", str(TARGET)], check=True)

    print(f"after:  {describe(TARGET.read_bytes())}")
    print("Mute bit cleared and exact readback verified; reboot is required")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check", "apply"), nargs="?", default="check")
    args = parser.parse_args()
    return inspect() if args.action == "check" else apply()


if __name__ == "__main__":
    raise SystemExit(main())
