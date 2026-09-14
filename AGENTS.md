# Instructions for AI agents

This repository documents Debian 13 on the 12-inch Retina MacBook (**MacBook8,1**, early 2015) and ships
scripts that change a real laptop's boot and audio configuration. Treat every step as operating on someone's
only computer.

## Start here

| User wants | Read and follow |
|---|---|
| Keyboard/trackpad working (Apple SPI) | [README.md](README.md) section 6 |
| Internal speakers / headphones / microphone | [docs/audio/AI_RUNBOOK.md](docs/audio/AI_RUNBOOK.md) (gated steps) |
| Understand or port the audio fix | [docs/audio/HOW_IT_WORKS.md](docs/audio/HOW_IT_WORKS.md) |
| Hardware status / collecting diagnostics | [README.md](README.md) sections 2, 3 and 8 |

## Non-negotiable rules

1. **Verify the machine first:** `cat /sys/class/dmi/id/product_name` must print exactly `MacBook8,1`. Other Mac
   models need different fixes; do not apply these.
2. **The user types all passwords.** Never request, store or echo passwords, tokens or keys.
3. **Ask before** every `apt install`, driver install, GRUB/EFI change and reboot, each time. A remote reboot
   requires a confirmed recovery path (SSH that comes back, a second kernel, or a live USB).
4. **Run the repository's scripts instead of re-typing their steps.** They contain safety checks (model, kernel,
   checksums, controller order). Never bypass a check, `--force` a patch, or edit options by hand to "make it work".
5. **Evidence before claims.** Loaded modules, ALSA devices or PipeWire nodes do not prove sound. Report success
   only after the user confirms what they heard or saw, and after a reboot for boot-level changes.
6. **One change at a time.** If a gate fails, stop, report the exact output, and offer the documented rollback.
   Do not stack experimental fixes.
7. **Keep private data out** of commits, issues and pasted logs: hostnames, IP addresses, Tailnet names,
   usernames, serial numbers.

## Repository map

```text
README.md                    main guide: install baseline, Apple SPI fix, status, diagnostics
docs/audio/README.md         human audio guide
docs/audio/AI_RUNBOOK.md     step-by-step audio install for agents (gates, expected output, rollback)
docs/audio/HOW_IT_WORKS.md   root cause, measurements, design decisions
audio/driver/                kernel patch (GPL-2.0-only) + Makefile
audio/scripts/               build, install, verify, restore, PipeWire, EQ, auto-switch
audio/config/                WirePlumber rule
audio/diagnostics/           read-only codec/clock readers, EFI mute-bit tool
```

## Scope of support

Verified: Debian 13 (trixie), kernel `6.12.107+deb13-amd64`, PipeWire 1.4 / WirePlumber 0.5, Cinnamon on Xorg.
Other 6.12 Debian kernels should work if the patch applies (the build script checks). Kernels ≥ 6.17 moved the HDA
codec sources and are **not** supported without porting. Suspend/resume is not working for audio (or reliably for
Apple SPI input) and is out of scope.
