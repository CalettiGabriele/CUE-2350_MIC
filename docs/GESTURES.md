# CUE-2350 MIC gestures and commands

> The single reference for the EP-2350 FX MIC gestures and the actions behind them.
> Updated 2026-10-23: channels on orange, skills and commands on white, voice command on grey ([One-Pager 004](design-docs/onepager-004-channels-and-commands.md)). Updated 2026-10-25: the voice command is an agent with tools and confirmation on the mic ([TDD voice command agent](design-docs/tdd-v1-voice-command-agent.md)).
> **Interface language:** English by default, changeable in Settings › General › Language (English, Italiano, Français, Español, Português, Deutsch, 中文, 日本語, Русский) or in `config.json` (`ui.language`).
> Channels, skills, intents and gestures are configured in Settings (the **Channels** and **Profiles** chapters) or in `~/Library/Application Support/FXMicBridge/config.json`. This file describes the **defaults**. The reference code is `app/Sources/FXMicCore/Config.swift` (`Profile.defaults`) and `GestureRecognizer.swift` (`GestureSettings`).
> This is the current gesture reference. One-pagers record proposals in their original context; accepted ADRs govern architecture until explicitly superseded. For repeatable validation, see [smoke checks](SMOKE-CHECKS.md). For acoustic codes and timing, see [the jack channel](JACK-CHANNEL.md) and the [receiver implementation](../app/Sources/FXMicBridge/JackTransport.swift).

## At a glance

| Button | Role | Tap | Double tap | Long press | Other |
|---|---|---|---|---|---|
| **Handle** | talk | — | new line (⇧↩) | hold and talk | — |
| **Orange** | **channels**: where the voice goes | next channel | previous channel | adds the window in front | **held 3 s: clears the channels** |
| **White** | **skills and commands** | next | previous | none | — |
| **Grey** | **send and interrupt** | runs the command, otherwise Return | undoes the last insertion | **interrupt** (Esc) | **pressed while you talk: voice command** |

## What each connection carries

| Connection | What it carries | What it enables |
|---|---|---|
| **USB-C** (data) | MicroPython serial console, plus power | All gestures and LEDs. The app installs a RAM-only agent (ADR-001). |
| **3.5 mm jack** | Analogue voice and acoustic gesture codes | With the installed [FXMic firmware](INSTALL-FIRMWARE.md), a USB audio interface with an input carries voice and supported gestures; see [the jack channel](JACK-CHANNEL.md). Original firmware and the USB RAM-only agent do not provide this acoustic channel. The Mac's headset jack with a TRS→TRRS adapter was tried without success: the Mac detects the microphone but gets no signal. |
| **Mac keyboard** | Keyboard mic handle and grey gestures | Hold **right Option** to talk; double click it for a new line. **Right Command alone** acts as grey; press and release it while right Option stays held for a voice command. |

The keyboard mic works alongside the FX-MIC. The source that starts a take owns the handle until
it releases it: pressing or releasing another source's handle cannot start or stop that take.
If the owning USB connection goes away or the jack listener stops, the take is cancelled and the
keyboard mic remains available. Heartbeat silence alone does not end a jack take: the FX-MIC
does not send heartbeats while its handle is held.
Right Option uses the same click timing and profile actions as the physical handle; holding left
Option at the same time does not prevent a right Option release from ending the take.

### Grey on the keyboard mic

Right Command uses the same grey profile actions and gesture thresholds as the FX-MIC:

| Keyboard gesture | Result |
|---|---|
| Right Command tap, at most 450 ms | Run the selected command, otherwise Return; waits for the 300 ms double-tap window |
| Two right Command taps within the double-tap window | Undo the last insertion |
| Right Command held for at least 600 ms, then released | Interrupt, Esc by default |
| Right Option held, then right Command pressed and released | Voice command; release Command before Option so the chord commits before recording ends |
| Right Command tap during confirmation | Approve |
| Right Command held for at least 600 ms, then released during confirmation | Refuse |

Unlike the physical grey button, right Command stays provisional until it is released.
Long press and chord therefore fire on release, not while held. This preserves ordinary shortcuts
even when another key is pressed after the long-press threshold. Any other key pressed during the
Command hold cancels its grey gesture; all keyboard events pass through unchanged. Left Command
never acts as grey. Releasing right Option before Command cancels the candidate chord and ends the
dictation normally, without a stray Return or Esc. A hold longer than 450 ms but shorter than 600 ms
is neither tap nor long press, as on the mic.

These keys work both in the app's own windows and in other apps. Observing keys in other apps needs
the app's Accessibility grant; Secure Keyboard Entry can prevent delivery.

## The voice goes where you are

When you hold the handle, the app looks at the window in front of you:

- if it belongs to a **channel**, the voice goes to that channel and its red LED is lit;
- otherwise you are **free**: all four red LEDs are lit and the voice goes **where your cursor is**, in any app, with no jump and nothing to set up.

The profile, that is the white button's skills and the intents, always follows the app in front of you. The pill says where the voice goes: "Recording · Claude · api" on a channel, "Recording · Free · Mail" elsewhere.

## The three buttons

### Orange: channels (red LEDs, one per channel)
A **channel** is a place you want to get back to with one tap: a Claude Code or Codex session, a Claude chat or project, a document (for example a `TODO.md` in VS Code), a window or a whole app. Up to **4 channels**, each with a red LED.

- **Tap:** jumps to the next channel (from free, to the first) and brings its window to the front.
- **Double tap:** jumps to the previous channel (from free, to the last).
- **Long press:** adds the window in front of you as a channel. It takes the first empty channel; if all four are taken it replaces the one you are on (or the last, if you are free). If the window is already a channel, it updates it.
- **Held for 3 seconds:** **clears all channels**. It is slow on purpose, so it is not triggered by mistake. From the menu › Channel you can undo it ("Restore the cleared channels") until you bind something else.

How the app finds a channel again:

| Channel | How it is recognised | How the app returns to it |
|---|---|---|
| Claude Code session | session id, read from Claude's log | `claude://code/continue?session=…` |
| Codex thread | thread id, read from Codex's log | `codex://threads/…` |
| Claude chat or project | page address, read through Accessibility | `claude://claude.ai/chat/…` (or `/project/…`) |
| Document | the window's `AXDocument` | brings the app and the window to the front |
| Window | window title | brings the app and the window to the front |
| Whole app | the app (any window) | brings the app to the front |

If a window belongs to more than one channel, the most specific wins (a session or a chat before a document, then a title, then a whole app). Other apps with several sessions in one window can be added with an adapter in `config.json` (`sessionAdapters`). Channels can also be managed from the menu › Channel and from Settings › Channels (rename, reorder, remove, add a whole app, clear with confirmation).

### White: skills and commands (white LEDs in binary)
Up to **15 per profile**. The 4 white LEDs show the number in binary, with the top LED = 1, then 2, 4, 8. **All off = none.** The pill always shows the name. The list follows the app in front of you, so on a channel it is the list of that channel's app.

| Type | What happens |
|---|---|
| **Command** | **Grey** runs it at once: keys or text, for example `/compact` + Return. |
| **Skill / template** | The **next dictation** is placed into the text in place of `{{text}}` (for example "Summarize: {{text}}" or a skill's prompt). |
| **LLM rewrite** | The **next dictation** is transformed by the model with the instruction (for example "Rewrite as an email"). |

- **Tap:** next (none → 1 → 2 → … → none). **Double tap:** previous. **Long press:** none.
- **After use** the selection goes back to "none".
- The **names** are also what you say in a voice command ("run the review").

### Grey: send, interrupt, voice command
- **Tap:** runs the selected command; if there is none it presses **Return**.
- **Double tap:** undoes the last insertion (⌘Z, within 30 s, same app).
- **Long press:** **interrupt** (the profile's `interrupt` intent, **Esc** by default).
- **Pressed once while you hold the handle and talk: voice command.** The sentence is not typed: an agent on the local model turns it into actions, calling tools step by step and checking its work ([TDD voice command agent](design-docs/tdd-v1-voice-command-agent.md)). It works in any language, with no keywords to remember. Possible actions:
  - **text and keys** in the focused field: "new line", "delete the last word", "bullet list", "write good morning everyone";
  - **selection:** when text is selected, "translate it into English", "make it shorter", "turn it into a bullet list" replace it with the transformed version; "delete it" removes it;
  - **channels:** "switch to the api project", "go to Codex" (part of the name is enough);
  - **skills and commands:** "run the review", "do the compact";
  - **profile intents:** "stop", "new session" (see *Intents*);
  - **select and format:** "make the word urgent bold", "italic", "make it a list" (⌘B/⌘I in rich text, `**…**` in Markdown fields, nothing in terminals: the profile's *Text format*);
  - **the app's interface:** "click Share", "export as PDF", "reply all" (buttons and menu commands), "open Notes", "close this window";
  - **your own tools:** macros and Shortcuts app shortcuts from Settings › Voice command › *My tools*.

  **Confirmation on the mic:** before a risky action (sending, deleting, closing, a click on «Delete», a shortcut) the pill shows `Confirm … · grey = yes · shake = no` and the red LEDs blink. **Grey tap = yes**, a short shake or a grey long press = no, no answer within 10 s = no. Quitting apps, logging out, shutting down are never done; ⌘Q, ⌘W and similar stay blocked.

  If the command is unclear nothing happens, and the pill says so. A simple command takes about 1.5 s with the default local model. Settings › Voice command has the limits, a switch and a risk level for every tool, your own tools, and *Test a voice command* (a dry run that shows every step).

## Handle and accelerometer
| Gesture | Action |
|---|---|
| Hold the handle, talk, release | Dictation: the text goes where you are (see above), with the selected skill if there is one |
| Grey pressed while you talk | Voice command |
| Quick double click on the handle | New line (⇧↩) |
| Short shake | Cancels the dictation in progress |
| Strong shake for at least 2 s | Clears the whole field (⌘A ⌫; in terminals Ctrl+E Ctrl+U) |

## Status pill and icon

- **Pill at the top:**
  - **MacBook (notch, Dynamic Island style, no border):**
    - left of the notch, the status dot: red with a **radar** effect while recording, pulsing white while processing;
    - on the right, the **recorded time**;
    - below, a line with phase, destination and skill, for example "Recording · Claude · api · Summarize" or "Recording · Free · Mail".
  - **Other screens:** a black pill under the menu bar with a thin light border: [dot] text [time].
  - Short cards (channel change "Channel 2/3 · Codex", skill "Slot 3 · /review", "Voice command", "Written", errors) show only the text. They fade in and out.
- **Menu bar icon:** it is **always the one you chose** (menu › Menu bar icon) and does not change while recording, because macOS already shows its own microphone indicator. The status is in the tooltip and in the first line of the menu.

## LEDs
| State | Red LEDs | White LEDs |
|---|---|---|
| Idle | The channel you are on (one LED), or **all four when you are free** | Skill in binary, or off |
| Recording | **KITT**: one LED sweeping up and down | Unchanged |
| Transcribing and processing | Alternating 1+3 / 2+4 | Unchanged |
| Error | The 4 red LEDs blink for about 1 s | — |

- **LED map:** `device.ledMap` in `config.json` says which physical index matches [red 1…4, white 1…4]. The default `[0,1,2,3,4,5,6,7]` was verified on the device on 2026-10-16. Settings › Device › **Test LEDs** lights the LEDs one at a time in this logical order, so you can tell whether the map is right.
- **Animation speed:** set with `device.ledAnimationMs`, 120 ms by default.

## Default profiles
| Profile | Apps | Skills and commands |
|---|---|---|
| **Claude** | Claude desktop app | New chat ⌘N · Stop response Esc · Summarize · Translate to English · Explain simply · Brainstorm |
| **Coding agent** | Terminal, iTerm2, Ghostty, VS Code, Warp | /compact · /clear · /review · Bug report · Commit message (LLM) |
| **General** | All the others | Email · Translate to English · Bullet list · Shorter (all LLM) |

## Intents
An **intent** is a named action that the profile maps to the app: this way "stop" means Esc in Claude and another shortcut elsewhere. They are defined per profile in Settings › Profiles › *Voice command* or in `config.json`, under `intents`. Intents without a mapping answer "not available here".

| Intent | Default |
|---|---|
| `interrupt` | Esc key (also the grey long press) |
| others (for example `newSession`, `approve`) | to be defined per profile: `"intents": {"newSession": {"type": "key", "keys": ["cmd+n"]}}` |

## Configurable actions
| `type` | Effect |
|---|---|
| `key` (`keys`: list) | Sends combinations such as `cmd+a`, `shift+return`, `escape` |
| `text` (`text`) | Types the text; a trailing `\n` also presses Return |
| `nextChannel` / `previousChannel` / `bindChannel` / `clearChannels` | Channels (orange) |
| `nextSlot` / `previousSlot` / `clearSlot` | Skills and commands (white) |
| `runSlot` | Runs the selected command, otherwise Return |
| `intent` (`name`) | Runs the profile's intent |
| `editSelection` | Voice command (the name is kept for compatibility) |
| `undoLastInsertion`, `reinsertLast`, `cancel`, `none` | Undo the last insertion, retype the last text, cancel the dictation, nothing |
| `cycleMode` / `resetMode` | Superseded: the old interaction modes, read only from old configuration files |

## Gesture thresholds
| Parameter | Value |
|---|---|
| `tapMaxMs` · `doubleTapMs` · `longPressMs` · `veryLongPressMs` | 450 · 300 · 600 · 3000 ms |
| `handleClickMaxMs` · `handleDoubleClickGapMs` | 280 · 400 ms |
| `shakeThreshold` · `shakeHoldMs` · `shakeHoldToleranceMs` | 0.5 · 2000 ms · 400 ms |
