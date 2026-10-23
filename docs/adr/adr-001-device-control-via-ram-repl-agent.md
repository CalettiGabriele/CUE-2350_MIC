# ADR-001: Control the EP-2350 with a RAM-only agent through the serial REPL

**Date:** 2026-10-15
**Status:** Accepted for the USB-C connection. The "nothing permanent on the mic" constraint is superseded by [ADR-003](adr-003-persistent-fxmic-firmware-via-romfs-json-hook.md) only for the explicit installation of the FXMic firmware; with FXMic installed, restoring the agent uses `fxmic.resume()` instead of `python_callback`.

## Context
FXMic Bridge must receive button, handle and accelerometer events from the FX-MIC, and drive its LEDs. An explicit constraint is that the device must always be restorable to its factory state.

The exploratory tests (`logs/TEST_NOTES.md`) showed three things:
- firmware 1.0.9 exposes a free MicroPython console over USB while the mic is working;
- all the button logic lives in `/rom/main.py` and receives events through `ui.callback(python_callback)`;
- a replacement callback installed in RAM receives every event, forwards the rest to the factory code and removes itself cleanly.

The other options cost more:
- a custom firmware means reflashing the mic;
- `config.json` and the samples mean writing to FX MIC DISK, and they send no events to the Mac;
- recognising audio codes from the jack works in one direction only and uses up the sample slots.

## Decision
We decided to control the mic by installing, on every connection, a small Python agent **in RAM only** through the REPL's paste mode. The agent:
- intercepts `ui.callback`;
- hides the buttons from the factory code when the app handles them;
- answers a poll for the handle and the accelerometer;
- accepts a closed list of commands, such as `ui.leds` and `fx.load_preset`.

The app never writes to the flash, the ROM or FX MIC DISK. Restoring is explicit, with `ui.callback(python_callback)` when the app quits, and guaranteed anyway by switching the mic off. Firmware versions outside the compatibility list work read-only.

## Consequences

**Positive**
- No risk of damaging the device: switching it off and on brings it back to its factory state.
- Low-latency events (about 4 ms between events) and LED control in both directions.
- No flashing tool is needed, nor any knowledge of the firmware beyond the public Python API.

**Negative**
- It depends on internal firmware names (`python_callback`, `fx_pos`, `sam_pos`, the `ui` and `fx` modules), which an official update could change.
- The agent must be reinstalled at every power-on or connection, and the serial port cannot be shared with other programs.
- Audio does not go through this channel: a separate source is needed (the jack with an audio interface, or the Mac's mic) until the possible M4 spike.
