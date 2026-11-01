# One-Pager 006 — The status island

> Date: 2026-11-01 · Status: **Implemented** (`HUD.swift`, 2026-10-30 to 2026-10-31); tried by the user on a notch screen for recording, channels, slots and results; the voice command states and the fix that keeps the island up when grey is pressed while talking are not yet confirmed on the real mic
> Replaces the island description in TDD v1 §3.9 and `docs/GESTURES.md` ("Status pill and icon"), which are now short pointers to this page
> References: One-Pager 001 (slots), One-Pager 004 (channels and commands), TDD voice command agent, ADR-005, `app/Sources/FXMicBridge/HUD.swift`, `app/Sources/FXMicBridge/AppDelegate.swift`

This page is the **single reference for what the island looks like and says**. The site (`site/src/components/MacScreen.astro`), the README art (`docs/readme/build_art.py`) and the video redraw it by hand: when this page changes, they change with it.

## 1. Problem
The island used to be one line of text (`RECORDING · CLAUDE · SOME LONG SESSION TITLE…`) next to two columns of LED dots. The text was in uppercase mono, so a session title was cut off after a few words; channel and slot choices were announced with a label and a sentence ("SLOT 3 · LLM ON THE NEXT DICTATION"); the result of a dictation was a word that vanished in under a second; and a voice command showed one step at a time with no sign of what had been understood or how far along it was. In jack mode the island is the main feedback, so it has to carry more with less text.

## 2. Anatomy

```
 left wing         notch          right wing
┌──────────────┬──────────────┬──────────────┐
│ ● ▬ ● ●      │              │   ✓  1.2 s   │   ← wings: same height as the notch
│ ● ● ▬ ●      │              │              │
├──────────────┴──────────────┴──────────────┤
│        [icon]  Title that can fade         │   ← title row (28 pt, more with a detail)
│          grey detail, up to 2 lines        │
└────────────────────────────────────────────┘
```

- **Left wing: the pips.** Two rows of four, centred in the wing. Top row red = channel, bottom row white = slot. They **mirror the logical LED mask** that `LedAnimator` sends to the device (bits 0–3 red, 4–7 white), so the island and the mic always agree, including the recording sweep.
  - Lit pip: a capsule 12 × 6 pt (red `#E3242B` or white) with a soft glow. Unlit: a 6 pt dot.
  - Unlit red: dim red (45 %) if a channel is bound there, nearly off if not. While you are free (all four lit) the bound ones are drawn brighter.
  - Unlit white: grey (`#6E6E6A` at 55 %).
  - Every pip has its own 12 pt cell (3 pt gap, 4 pt between rows), so a sweep moves without shifting its neighbours.
- **Right wing:** one of: the elapsed time (mono, `0:05`); a short text (`2/3`, `2/6`, `MODE`); a glyph (slot kind ▶ run, ✎ template, ✦ LLM; ✕ cancelled; mic-off no speech; ⚠ failure in red); the **check in a ring** with the latency; the **countdown ring**. Centred in the wing.
- **Title row** (below the notch): the app icon (16 pt) and the title, centred together; under them a grey **detail** (12 pt, 50 % white, centred, up to two lines) or the **answer chips**.
- **Notch screens:** a black shape with a flat top that grows out of the notch. **Other screens:** a black pill under the menu bar with a 1 px light rule; pips on the left, right wing on the right, icon and title between.
- **Type:** Barlow SemiBold 14 for titles (sentence case, as written), Barlow SemiBold 12 for details, IBM Plex Mono SemiBold 11 for numbers and short texts. A title longer than 300 pt **fades out at the end** instead of ending in an ellipsis. The island is never wider than 460 pt.
- **Colour:** island black, text white, **red only for the mic's red LEDs, the recording dot and failures**. No orange on the island (the orange of the identity is for the mic's button and the pages).

## 3. States

| State | Pips | Right wing | Title row | How long |
|---|---|---|---|---|
| **Recording** | KITT sweep on the red row, slot bits on the white row | time; after the title row folds, a red dot (breathing, 1 s) before the time | app icon + channel name (the part after the app: `Claude · Plan` → `Plan`); free: the front app | until the handle is released; the row **folds away after 1.2 s** |
| **Recording, folded** | same | red dot + time | none: the island is the two wings, **6 pt taller than the notch** | until release |
| **Transcribing / processing** | `1+3 / 2+4` alternating on red | — | icon + "Transcribing" / "Processing" | until done |
| **Written** | idle mask | check in a ring + latency (`1.2 s`) | icon + "Written" | 0.9 s |
| **Channel card** | the channel you landed on | `2/3` | icon + channel name | 1.0 s |
| **Slot card** | slot number in binary | slot-kind glyph | slot name; "No slot" with none | 1.0 s |
| **Mode card** | — | `MODE` | mode name | 1.0 s |
| **Message** (cancelled, no speech, discarded…) | idle mask | muted glyph | title; "Title: detail" becomes title + grey detail | 0.9 s, or 2–6 s with a detail |
| **Failure** | all red blinking (the mic's error blink) | red ⚠ | title (+ detail) | as above |
| **Plain notice** (no channel, protected field…) | idle mask | — | title | 0.9 s |

**Reading time** for a notice with a detail: `min(6, max(2, 1.5 + 0.05 × characters))` seconds. A new press of the handle replaces the notice at once.

### 3.1 Voice command
A dictation becomes a command with the profile's Command mode, or with **grey pressed while you talk** (the island stays up and takes the command look; the timer keeps running).

| Step | Pips | Right wing | Title row |
|---|---|---|---|
| **Recording** | as above | time | AI mark ✦ (white SF Symbol `sparkles`) + channel name, detail "Voice command" |
| **At work** | processing pattern | step count (`2/6`) | ✦ + the step now ("Selecting the paragraph"), detail: what you said in curly quotes |
| **Confirm** | all red blinking | **ring** that empties over `agent.confirmTimeoutMs` | ✦ + the action ("Delete 3 files?"), two chips: `● grey = yes` and `shake = no` with a mic drawn with vibration arcs |
| **Done** | idle mask | check in a ring + time taken | ✦ + "Done", detail: the summary (2 lines), 2–6 s |
| **Failure** | all red blinking | red ⚠ | "Command not recognised" (or the other failure), detail: the reason |

The confirmation stays until you answer or the ring runs out.

## 4. Motion
- **Notch screens:** a damped spring (underdamped, a few points of overshoot) grows the shape out of the notch and follows every size change; it retracts into the notch when it closes. The height **never goes below the notch**, whatever the spring does. Contents fade in once the shape is mostly open and out before it closes.
- **Pill:** critically damped (no overshoot), grows in from slightly smaller and a little higher while fading; it never shrinks to a tiny empty shape.
- **Pips** step like the hardware, no easing. The recording dot breathes (opacity 1 → 0.35, 1 s). The check draws itself (ring 0.2 s, tick 0.15 s, starting as the island opens); the countdown ring empties linearly.
- **Reduce Motion:** only a short fade; no spring, no dot, no drawing check.
- The panel never takes focus and ignores the mouse; the island appears on the screen under the pointer.

## 5. Decisions and why
- **Pips instead of the 8-LED columns and a sentence.** Position says "which channel / which slot" faster than text, and it is the same code as the mic, so there is nothing to learn twice.
- **Mirror the mask, do not recompute it.** What the island shows is what was sent to the device (with the jack, what the firmware shows). It cannot disagree with the LEDs. See ADR-005 for the slot counter this needed.
- **Fold the title row while recording.** The title answers "where does my voice go" for a second; after that the island should get out of the way. The 6 pt of extra height is not decoration: without it the spring overshoot took the island under the notch and its edge showed.
- **No orange rule or app square.** They said "done" and "recording" with a colour that carries no meaning elsewhere on the island. The check and the red dot say it with shapes people already know.
- **The AI mark for commands.** An app icon says where the text goes; a command is the agent acting, so it wears its own mark (`sparkles`) in every step.
- **Titles in sentence case, numbers in mono.** Mono uppercase made every notice look like a status line and made names unreadable; it is kept only for numbers, where the fixed width helps.

## 6. Where it lives in the code
- `HUD.swift`: the view (`show`, `toast`, `card`, `setLEDs`, `setChannels`), the spring, `PipsView`, `ChipsView`, `CheckView`, `CountdownView`, `RecDotView`.
- `AppDelegate.show(_:)` maps each dictation phase to a notice; `announceResult` splits "Title: detail" and picks the glyph; `mirrorLEDs` feeds the pips; `hudTarget` gives the icon and the title of the channel.
- `DictationController.Phase`: `.working(step, request, step, steps)` and `.commandDone(summary, seconds)` carry what the island shows for a command; `isCommand` and the re-emitted `.recording` keep the island up when grey is pressed.
- Texts: `L.t` in `translations.py` (`grey = yes`, `shake = no`, `Done`, `Voice command`…).

## 7. Checks and open points
- Rendered offscreen for: recording (open, folded), working, confirm, done, failure, written, channel, slot. **To try on the real mic:** KITT phase against the mic's own sweep (they start from different clocks, a fraction of a second apart), the confirmation ring against `confirmTimeoutMs`, grey pressed while talking.
- `2/6` counts model steps against the budget, so it can end early; if it misleads, keep only the dots.
- Not done: a two-part version of the longest notices ("No channel 3: long-press orange on a window to add it") with a hint shown only the first times.
