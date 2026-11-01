# Glossary

The words this project uses, as they are used in the code, the docs and the UI.

## The mic
- **Handle**: the part you hold to talk. Held = recording, released = the take ends. Double click = new line.
- **Orange, white, grey**: the three buttons. Orange = channels, white = slots (skills and commands), grey = actions and the voice command.
- **LEDs**: eight on the mic. Four red (the channel you are on, one lit; all four lit = free) and four white (the slot number in binary, top = 1).
- **KITT**: the sweep of one red LED up and down (0 1 2 3 2 1) while recording.
- **LED mask**: the 8 bits sent to the mic (bits 0–3 red, 4–7 white), logical order. The island draws the same mask.

## What you talk to
- **Channel**: a named destination bound to a red LED (a session, a chat, a document, an app). At most four. Binding = long press on orange with the window in front.
- **Free**: no channel in front. All four red LEDs lit; the voice goes where the cursor is.
- **Page**: a channel position the mic itself lands on (firmware paging over the jack) and reports to the Mac.
- **Profile**: the skills, intents and text format that follow the app in front.
- **Slot**: one of up to fifteen skills or commands, selected with white. Kinds: **run** (grey sends it), **template** (wraps the next dictation), **LLM** (rewrites the next dictation).
- **Slot counter**: the mic's single number 0–15 on the white LEDs; the slot is the one the profile has at that number, if any ([ADR-005](docs/adr/adr-005-one-slot-counter-like-the-mic.md)).
- **Intent**: a named action a profile maps to the app ("stop" = Esc in one app, another shortcut elsewhere).
- **Voice command**: grey pressed while talking (or the Command mode): the sentence becomes actions run by an agent, instead of being typed.

## The island ([One-Pager 006](docs/design-docs/onepager-006-status-island.md))
- **Island**: the black shape at the top of the active screen, growing out of the notch (a **pill** on screens without one).
- **Wing**: the part beside the notch. Left wing holds the pips, right wing holds the time, `2/3` or a glyph.
- **Pips**: the two rows of four dots in the left wing mirroring the LEDs. Lit = a capsule, unlit = a dot.
- **Title row**: what is below the notch: the app icon (or the AI mark), the title and a grey detail.
- **Folded / compact island**: while recording, the title row gone: the two wings, a little thicker than the notch.
- **Notice**: anything the island says for a moment (a result, a message, a card). **Card**: a notice for a selection (channel, slot, mode).
- **Chip**: a pill under the title with an answer ("grey = yes", "shake = no").
- **AI mark**: the ✦ (sparkles) shown instead of the app icon in every step of a voice command.
