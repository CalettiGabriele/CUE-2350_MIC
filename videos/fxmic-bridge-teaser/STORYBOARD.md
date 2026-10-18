---
format: 1080x1080
duration: 21s
message: "Your FX-MIC, now a voice remote for your coding agent"
arc: "Demo Loop — hook (chapter title) → hold+talk → pick a skill → send to agent → brand"
audience: "software engineers running agentic workflows (Claude Code), tinkerers — LinkedIn feed"
mode: collaborative
music: "lo-fi electronic, mechanical, playful, upbeat, ~105 bpm, punchy start"
---

## Frame 1 — ((8)) talking to your agent

- scene: A guide-style grey chapter bar types "((8)) talking to your agent" on the off-white page
- duration: 2.5s
- poster: 2.0s
- transition_in: cut
- status: animated
- src: compositions/frames/01-chapter.html
- blueprint: typewriter-reveal
- voiceover: none
- onscreen: "((8)) talking to your agent" · kicker "EP–2350 FX–MIC · user guide · unofficial chapter" (no body copy — user feedback: too much text to read)
- asset_candidates: chapter-bar
- sfx: typewriter keys

Cold open as if we turned a page of the EP-2350 manual and found a chapter that was never
printed. The hook is the recognition ("wait, chapter 8?") — for anyone who owns the mic, and
curiosity for everyone else. Paper register, technical uppercase chrome, no product yet.

**Shot sequence**
- Scene 1 (0.0–0.4s): paper ground; top chrome kicker fades up; grey chapter bar wipes in from the left (scaleX, power3).
- Scene 2 (0.4–1.9s): "((8))" lands, then the title types on with an orange caret → `discrete-text-sequence` + `context-sensitive-cursor`.
- Scene 3 (1.8–2.5s): hold, caret blink only.

## Frame 2 — ((8.1)) Pick a mode

- scene: Guide-style table of the 4 interaction modes beside the mic; each row lights with its red LED, then two presses of the orange button settle on "enhanced"
- duration: 4s
- poster: 3.4s
- transition_in: cut
- status: animated
- src: compositions/frames/02-modes.html
- blueprint: fixed-anchor-cycle
- voiceover: none
- onscreen: chrome "((8.1)) orange button" / "mode n / 4" · rows "dictate — as spoken", "enhanced — polished by a local llm", "command — voice → shortcuts", "computer use — coming soon" · callout "PRESS"
- asset_candidates: fxmic-device, press-callout
- sfx: key-press per row, button click per press

Added on user feedback: show the interaction modes driven by the orange button and the red LEDs.
Computer Use is honestly marked "coming soon" (not implemented yet in FXMic Bridge).

**Shot sequence**
- Scene 1 (0.0–0.5s): mic rises in on the left, chrome in.
- Scene 2 (0.45–2.0s): the 4 rows reveal one by one; the active row gets the orange bar and its red LED lights on the mic.
- Scene 3 (2.05–3.2s): PRESS callout; two presses of the orange button → dictate → enhanced (mode 2 / 4).
- Scene 4 (3.2–4.0s): hold.

## Frame 3 — Hold the handle. Talk.

- scene: The redrawn FX-MIC slides in; an orange PRESS callout points at the handle, red LEDs sweep KITT-style while a status pill shows "● recording · enhanced"
- duration: 3.5s
- poster: 2.8s
- transition_in: cut
- status: animated
- src: compositions/frames/03-talk.html
- blueprint: device-surface-showcase
- voiceover: none
- onscreen: callout "HOLD + TALK" · pill "● 0:02 · recording · enhanced" · caption "dictate anywhere on your mac"
- asset_candidates: fxmic-device, press-callout, notch-pill
- sfx: button click

First look at the product as a designed object — the mic is the hero, drawn big in the guide's
flat vector language. The handle goes down, the red LEDs run the KITT sweep (real behaviour of
FXMic Bridge while recording), and the Dynamic-Island-style pill confirms the recording.

**Shot sequence**
- Scene 1 (0.0–0.6s): the mic rises into frame from below on a long-tail settle (power3); grille LEDs off.
- Scene 2 (0.6–1.2s): HOLD + TALK callout slides in from the left, arrow extends → then the handle rotates down (press) → `press-release-spring`.
- Scene 3 (1.2–3.4s): recording pill drops in from the top; red dot glows; KITT sweep on the 4 red LEDs (stepped, finite, ~8 steps/s); timer ticks 0:00→0:02.
- Scene 4 (2.2–3.0s): caption types "dictate anywhere on your mac".
- Scene 5 (3.4–4.0s): handle releases, KITT stops on LED 2 (mode: enhanced), pill text swaps to "written ✓".

## Frame 4 — Pick a skill

- scene: PRESS callout jumps to the white button; the 4 white LEDs count in binary 0001→0010→0011 while the slot name swaps /compact → /clear → /review
- duration: 3.5s
- poster: 2.8s
- transition_in: cut
- status: animated
- src: compositions/frames/04-slot.html
- blueprint: fixed-anchor-cycle
- voiceover: none
- onscreen: callout "PRESS" on white button · slot label cycles "/compact", "/clear", "/review" · caption "15 slots per app, in 4 LEDs"
- asset_candidates: fxmic-device, press-callout
- sfx: button click

The cleverest detail of the plugin: the white LEDs encode the slot in binary, and the slot is a
command or a skill for the agent. The device stays anchored; only the LEDs and the label move,
on the beat. Lands on "/review".

**Shot sequence**
- Scene 1 (0.0–0.4s): device holds (cut from frame 2, mic shifted left); chrome kicker in.
- Scene 2 (0.4–2.4s): three taps on the white button (press-release-spring) on the beat; PRESS callout pulses on each; white LEDs step 0001→0010→0011; binary readout and slot label hard-cut swap /compact → /clear → /review → `discrete-text-sequence` (in-place token cycle).
- Scene 3 (2.4–3.5s): caption "15 slots per app · in 4 leds" reveals; /review gets an orange underline sweep → `css-marker-patterns`; hold.

## Frame 5 — Send it to the agent

- scene: PRESS on the grey button; the camera slides to a dark terminal where "> /review" types and Claude Code starts working (status lines tick, a check lands)
- duration: 4s
- poster: 3.6s
- transition_in: cut
- status: animated
- src: compositions/frames/05-agent.html
- blueprint: prompt-type-submit-generate
- voiceover: none
- onscreen: callout "PRESS" on grey button · terminal "> /review" · agent lines "reviewing 4 files…", "✓ 2 suggestions" · caption "no keyboard. just the mic."
- asset_candidates: fxmic-device, press-callout, terminal-window
- sfx: button click, success chime

The payoff for the target audience: the mic drives an agentic coding workflow. Dark register
for the terminal only (the one surface that lives on the dark side). Commands large and short
for the square feed.

**Shot sequence**
- Scene 1 (0.0–0.5s): smaller mic on the left, terminal panel slides in from the right (power3).
- Scene 2 (0.5–1.0s): PRESS chip pops beside the grey button; grey button press-release-spring.
- Scene 3 (1.0–1.8s): "> /review" types into the terminal with caret → `discrete-text-sequence`.
- Scene 4 (1.8–3.6s): agent status lines appear one by one, spinner dot pulses (finite), then "✓ 2 suggestions" lands in green → `dynamic-content-sequencing`.
- Scene 5 (3.4–4.5s): caption "no keyboard. just the mic." types; hold.

## Frame 6 — FXMic Bridge

- scene: Back to the paper page; "FXMic Bridge" wordmark locks up with the mic silhouette, tagline and open-source line, small unofficial line at the bottom
- duration: 3.5s
- poster: 2.6s
- transition_in: cut
- status: animated
- src: compositions/frames/06-brand.html
- blueprint: titlecard-reveal
- voiceover: none
- onscreen: "FXMic Bridge" · "voice + gestures for your coding agent" · "open source · macOS" · footer "unofficial · not affiliated with teenage engineering"
- asset_candidates: fxmic-device, chapter-bar
- sfx: button click

Brand close in the same guide language as the opener (the chapter ends). Hold the lockup to the
final frame so the LinkedIn loop restarts cleanly on Frame 1.

**Shot sequence**
- Scene 1 (0.0–0.5s): paper ground, chrome in; small mic slides in from the left.
- Scene 2 (0.5–1.3s): "FXMic" / "Bridge" lines rise in, per-line stagger (power3) → `dynamic-content-sequencing`.
- Scene 3 (1.3–2.2s): tagline two lines, then "open source · macOS" in orange; red LED 1 on the mic blinks once.
- Scene 4 (2.2–3.5s): unofficial footer fades in; hold to the end (loop-friendly).

## Video direction

- One camera, one feel: the guide page is the world. Paper register everywhere except the terminal.
- Motion: power3 long-tail settles, no bounce; buttons use a short press + spring recovery (tactile, not playful).
- LEDs are the rhythm section: KITT sweep, binary steps and blinks land on the music grid (~105 bpm, 1 beat ≈ 0.57s).
- Cuts between frames are hard cuts on the beat (transition_in: cut); the mic keeps its identity across frames 2→3→4 (same drawing, new scale/position).
- Muted-first: every beat is legible from callouts + captions alone.
