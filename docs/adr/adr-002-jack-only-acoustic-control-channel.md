# ADR-002: Acoustic control channel at 12–19 kHz, with gestures recognised on the mic

**Date:** 2026-10-16 (rev. 2)
**Status:** Proposed, subject to tests T4 and T5 of One-Pager 002

## Context
ADR-001 carries events and LEDs over the USB serial line. The user wants to be able to use the FX MIC connected to the Mac **with the 3.5 mm jack only**, which carries a single audio signal from the mic to the Mac: it must carry both the voice and the commands.

With the factory firmware only the grey button makes a sound, while orange and white are silent. With the FXMic firmware (ADR-003), instead, the mic can play a sample for every gesture.

Whisper works at 16 kHz and discards everything above 8 kHz. Each code lasts about 180 ms: if the mic sent raw presses and releases, the Mac would receive them late and queued up, and double taps and long presses could no longer be recognised.

## Decision
We decided that with the jack-only connection:
- **gestures are recognised on the mic** by the FXMic firmware, with the same rules and thresholds as `GestureRecognizer`, copied at install time;
- each gesture (and a periodic heartbeat carrying the version) is sent as an **acoustic message** of 3 two-tone symbols in the **12–19 kHz** band, chosen from 4 symbols loaded into the mic's sample positions;
- **state stays on the Mac** (mode, slot, profiles): the mic keeps no state, so a lost message is the same as a button not pressed;
- the Mac records continuously at 48 kHz, decodes the messages and passes the voice to Whisper without extra filters;
- a single versioned codebook generates the symbol WAVs, the firmware configuration and the decoder table;
- the transport is chosen automatically (USB if the serial line is there, jack if the heartbeat arrives) or by hand (`device.transport`).

## Consequences

**Positive**
- Every gesture and dictation feature stays available with the jack alone; only the Mac-driven LEDs are lost.
- The codes are outside Whisper's band, and their structure (preamble, two tones, parity) cannot be produced by a voice.
- The Mac reuses profiles, modes, slots, LLM and the island unchanged, through an adapter from messages to actions.

**Negative**
- One-way channel: mode, slot, processing and errors are not shown on the LEDs, only in the island.
- About 180 ms of extra latency per command, and the gesture thresholds require reinstalling the firmware when they change.
- Recording always on on the Mac in jack mode: continuous power use and the macOS microphone indicator always lit.
- It depends on the frequency response of the mic's and the audio interface's audio chain, still to be measured (T5).
