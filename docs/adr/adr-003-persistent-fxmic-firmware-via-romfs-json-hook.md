# ADR-003: Persistent FXMic firmware in the ROMFS partition through `/rom/json.py`

**Date:** 2026-10-16
**Status:** Proposed. Feasibility verified on the device (T2, T3, T4 passed on 2026-10-16); the escape hatch (T1) still has to be redone.

## Context
To use the FX MIC with the jack only, the mic must emit an acoustic code for every gesture (ADR-002). So we need our own code on the device, active at every power-on and without USB.

ADR-001 forbade permanent changes. Now the user explicitly asks for a permanent installation, as long as it can be reversed from the app's Settings.

The tests of 2026-10-16 (`logs/TEST_NOTES.md`) showed four things:
- the `/rom` partition (ROMFS, 128 KB) can be rewritten and verified over the USB REPL in 6–10 s, and remounted without a reboot;
- at startup, firmware 1.0.9 always runs the built-in `teenage` module. `/rom/main.py`, `/rom/boot.py` and `boot.py`/`main.py`/`teenage.py` on the disk are **not** run;
- `teenage` runs `import json` as its second statement, and a `json.py` in `/rom` takes the place of the built-in module: **it runs at every power-on**;
- a loop started from there receives the button events and always leaves the console interruptible (Ctrl-C).

Alternatives considered:
- a rebuilt UF2 firmware: the sources of teenage engineering's audio modules are not available;
- a RAM agent loaded over USB at every power-on: it forces you to plug in USB every time;
- files on the FX MIC DISK: they are not run, and the disk proved fragile.

## Decision
We decided to install, **only on explicit request from Settings**, an FXMic firmware made of files added to the ROMFS partition (`json.py`, `fxmic.py`, `fxmic_cfg.py`, `fxmic_factory.mpy`), leaving the factory files unchanged.
- `json.py` is the boot hook. It registers the built-in `json`, starts FXMic and stops the factory code with a dedicated exception, so the callback stays with FXMic (T2).
- The app writes the ROMFS only after checking the firmware version, the partition fingerprint and the free memory. It saves the device's factory partition before the first write, reads the whole partition back to verify it and never uses the soft reboot.
- "Restore factory" rewrites the saved image (fingerprint 264e54d4…f1a1c4 for 1.0.9).
- The 4 audio symbols live in `/fat/.fxmic/`, because `spl.load_wav` only accepts FAT files (T4). The Mac writes them during installation and the restore removes them; the FXMic firmware never writes to the disk.
- The escape hatch is orange held during the first 3 seconds after power-on: FXMic then runs the precompiled factory logic. Reading the buttons at the very moment of boot does not work (T1).

## Consequences

**Positive**
- The mic works with the jack alone at every power-on, without USB, and the code runs on the mic itself: local gestures and LEDs.
- You can go back to factory in a few seconds from the app, or temporarily with orange at power-on.
- The factory files stay intact and the firmware is not reflashed; the disk only gains the hidden `.fxmic` folder.

**Negative**
- It depends on an internal detail of firmware 1.0.9: the import order of `teenage` and the fact that ROMFS comes before the built-in modules. An official update can break it; the app refuses unknown versions.
- A heap of only 64 KB and no `gc`: the firmware must be minimal, and writes must be done in small blocks right after a power-on.
- With FXMic active the mic loses its standalone use as an effects microphone: the factory samples and `config.json` are not used.
- Risk of an unbootable firmware in case of a bug: mitigated by the orange escape hatch, the always-interruptible console and, as a last resort, BOOTSEL with the official UF2 file, still to be obtained.
