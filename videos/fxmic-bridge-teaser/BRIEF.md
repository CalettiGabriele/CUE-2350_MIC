---
workflow: product-launch-video
flow: automation
storyboard: yes
message: "Your FX-MIC, now a voice remote for your coding agent"
destination: linkedin-feed
aspect: 1080x1080
language: en
audience: "software engineers running agentic workflows (Claude Code), tinkerers"
length: 26s
angle: "Chapter 8 — an unofficial new chapter of the EP-2350 user guide"
---

## Intent

Teaser for FXMic Bridge, an open-source macOS app that turns the teenage engineering
EP-2350 FX-MIC into a voice + gesture controller for the computer, and above all for
agentic software workflows (Claude Code, terminal agents).

Concept chosen: **"Chapter 8"** — the video plays as an unofficial new chapter of the
EP-2350 user guide, `((8)) talking to your agent`. It celebrates the product's design and
what teenage engineering made, and presents FXMic Bridge as an extension of their work.
Three beats + close:
1. hold the handle, red LEDs sweep (KITT), dictate;
2. white button picks a slot (e.g. `/review`), white LEDs show it in binary;
3. grey button sends it — a terminal shows Claude Code receiving the command;
4. close: "FXMic Bridge" wordmark, "open source · macOS", unofficial line.

Must read well muted (LinkedIn autoplays silent): callouts and on-screen text tell the story.

## Customizations

- Music bed (lo-fi electronic) with cuts on its beat, plus SFX: button clicks, LED blips.
- Visual language derived from the EP-2350 guide: off-white canvas, grey dot-grille device,
  orange/red accents, orange "PRESS" arrow callouts, grey chapter header bars, technical
  all-caps type, `((N))` chapter numbering.
- The FX-MIC is **redrawn from scratch as animatable vector SVG** (grille, 3 buttons,
  4 red + 4 white LEDs, handle/lever, curly cable) so LEDs and buttons can animate.

- Revision 1 (user feedback): opening chapter card keeps only the title (no body copy);
  new scene "((8.1)) orange button" shows the 4 interaction modes (dictate, enhanced,
  command, computer use — coming soon) with the red LEDs.
- Music bed from the HeyGen library (lo-fi electronic), fade-out at the end.
- Revision 2 (2026-10-23, new UX of the app, renamed CUE-2350 MIC): the orange scene now
  shows **channels** (claude code, claude chat, codex, notes; one red LED each; "free" with
  all red LEDs off), the talk scene runs free ("your words land where you are"), a new scene
  shows the **voice command** (grey pressed while talking: the selected sentence is
  translated in place), white shows **skills & commands**, the end card reads "cue-2350 mic."
  Length 26 s: the 22 s music bed is extended by a crossfaded second pass (`bgm-tail`).

## Notes

- Do NOT use teenage engineering's illustrations, photos or logo. Style homage only;
  do not trace any specific guide illustration.
- Must include the line "unofficial · not affiliated with teenage engineering".
- Product name may be used descriptively ("for the EP-2350 FX-MIC").
- Terminal commands large and short (max 2–3 words per line) for the square format.
- Product facts source: docs/GESTURES.md (profiles: Coding agent → /compact, /clear,
  /review, bug report, commit message; grey tap = run slot / Enter; shake = cancel;
  handle hold = dictate; red LEDs = 4 channels, all off when free; white LEDs = skill number
  in binary; grey while talking = voice command). Vocabulary: One-Pager 004 §15.
- Project is open source.
