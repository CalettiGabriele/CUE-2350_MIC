# One-Pager 004 — Channels (orange), actions (grey), prompts and skills (white) and voice commands

> Date: 2026-10-22 (rev. 2, after the §10 checks) · rev. 3 of 2026-10-23 (§14–§15) · Status: **Partly implemented** (channels, voice commands, Settings); the hooks (status LEDs, answering permissions) and the external model remain, see §14
> Replaces One-Pager 001 for the orange button; white and the manual LEDs stay, with new names
> **Some choices changed during implementation compared with §3–§6:** §14 prevails.
> **The voice command (§6) and the external LLM (§7) are now an agent (implemented 2026-10-25)** in [TDD v1 — voice command agent](tdd-v1-voice-command-agent.md) ([ADR-004](../adr/adr-004-voice-command-as-tool-calling-agent.md)).
> References: One-Pager 001, TDD v1 §3.2–3.3, `docs/GESTURES.md`, `app/Sources/FXMicCore/Config.swift`, `app/Sources/FXMicCore/ProfileEngine.swift`, `app/Sources/FXMicBridge/DictationController.swift`

## 1. Problem
The orange button's four modes (Dictate, Enhanced, Command, Computer Use) do not work well for the device's main use, that is **working with AI agents** such as Claude Code and Codex:
- **Enhanced** is of little use: whoever receives the text is already an LLM, and the local model adds waiting and mangles technical terms;
- **Command** as a persistent mode is hidden state: you dictate believing you are typing and instead you run keys;
- **Computer Use** is a placeholder;
- the LLM is called even when it is not needed, and the latency shows.

What is missing instead is what people working with several agents at once really need:
- moving from one session to another without the mouse;
- knowing which agent is waiting for an answer;
- giving voice commands without remembering keywords.

## 2. Goals
1. **No LLM in the normal path:** basic dictation is Whisper → text in the channel, with no waiting.
2. **Orange picks who I am talking to** (channels), not how my speech is processed.
3. **Voice commands are explicit and physical:** handle + grey. No keywords to learn.
4. **Generic:** it works with Claude Code and Codex (app or terminal), with other harnesses and with classic apps such as Word, Mail or a `.md` in an editor. No app is hard-coded.
5. **Multilingual:** Whisper detects the language by itself (`speech.language = "auto"`, already the case), and the LLM prompts do not assume a language.
6. **Local by default**, with the option of connecting an external model compatible with the OpenAI standard.

Out of scope for now: voice feedback (speech synthesis), a message queue, capturing into a notes file, literal formatters, Computer Use.

## 3. The new mapping

| Button | Tap | Double tap | Long press | During dictation |
|---|---|---|---|---|
| **Handle** | hold and talk: brings the channel to the front and types the raw text | new line (⇧↩) | — | — |
| **Orange** · channels | next channel; if an agent is waiting for you, it jumps to that one first | previous channel | **binds** the active window to the current channel | — |
| **Grey** · actions | runs the selected Run slot; with no slot, **Return** | undoes the last insertion | **Interrupt** (Esc, or the profile's action) | **the sentence becomes a command** (§6) |
| **White** · prompts and skills | next slot | previous slot | no slot | — |

Short shake (cancels the dictation in progress) and strong shake (clears everything) stay as today.

## 4. Orange: channels

### 4.1 What a channel is
A channel is a **named destination**, tied to one of the 4 red LEDs. It can be:
- an agent session (Claude Code desktop, Codex, a terminal session, another harness);
- a classic app (Mail, Word);
- an open document (a `TODO.md` in VS Code or another editor).

Four channels are enough (decided with the user).

When you talk, the app **brings the channel's window to the front** and types there. This is intended: the user immediately sees what is being transcribed and can correct it.

### 4.2 Binding a channel
No mandatory configuration, just a gesture:
1. bring the window you want to the front;
2. hold orange;
3. the pill confirms, for example "Channel 2 → Claude · api-project".

The app saves a **fingerprint**, which lets it find the window again even after a restart:

| Destination | Fingerprint |
|---|---|
| Classic app | bundle id |
| Document | bundle id + file path (`AXDocument` where the app exposes it) or, failing that, the window title |
| Agent session | bundle id + **session id** + project folder (`cwd`) and title, to recognise it if the id changes |

The channel's **profile** (slots, intents, hints for the LLM) is derived from the bundle id, as today.

**Binding an agent session.** At bind time the app must work out *which* session is in front. It does so by reading the session index (§4.3) and picking the one with the most recent activity in the active app. If the result is ambiguous, the pill offers the latest sessions by title and you choose with white.

### 4.3 Several sessions in the same window: deep links and the session index
Claude Code desktop and Codex show several sessions in one window, with a sidebar. The checks of 2026-10-22 showed that **both apps have a deep link to open a specific session**. So there is no need to click in the sidebar.

| App | Deep link to open the session | Session index (read only) | Id used by the hooks |
|---|---|---|---|
| **Claude desktop** (`com.anthropic.claudefordesktop`) | `claude://code/continue?session=local_<id>` | `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`, with `sessionId`, `cliSessionId`, `cwd`, `title`, `isArchived`, `lastActivityAt` | `cliSessionId` (verified: it matches the hooks' `session_id`) |
| **Codex desktop** (`com.openai.codex`) | `codex://threads/<id>` | `~/.codex/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`, first line `session_meta` with `id`, `cwd`, `originator` | `session_id` = thread id (to be confirmed) |
| **Terminal agent** (Claude Code CLI, codex CLI, others) | none: the terminal window or tab is brought to the front | — | the hook's `session_id`, associated with the window at bind time |

Other useful Claude desktop deep links:
- `claude://code/needs-input`: opens the sessions waiting for the user;
- `claude://code/new?folder=<path>`: opens a new session in a folder, useful for the `newSession` intent.

Rules for the session index:
- **Read only.** The files are internal to the apps, undocumented, and may change. The reader ignores missing fields and, if the format is no longer recognised, the channel falls back to the app alone (bundle id).
- **The map is built from the hooks.** When an event arrives, the app looks up the `session_id` in the index, finds the session (`local_…` for Claude, the thread id for Codex) and from there the channel and the deep link.
- **Last resort:** if an app offers no deep link, the session is opened with a click on the sidebar entry through Accessibility.

### 4.4 Agent status on the red LEDs

| Red LED | Meaning |
|---|---|
| steady | selected channel |
| off | channel not selected and idle |
| slow breathing | the agent is working |
| **blinking** | **the agent is waiting for you**: a permission, a question, or it has finished |
| KITT (sweep) | recording in progress, as today |

The status comes from the agents' **hooks**, not from reading the screen. Each hook calls a small app command, `fxmic-notify`, passing it the event JSON. The command forwards it to the app, which finds the channel by session id (§4.3).

| LED status | Claude Code | Codex |
|---|---|---|
| working | `UserPromptSubmit` | `UserPromptSubmit` |
| waiting for you: permission | `PermissionRequest` (or `Notification` with `permission_prompt`) | `PermissionRequest` |
| waiting for you: question | `Notification` with `elicitation_dialog` or `agent_needs_input` | — (to be checked) |
| finished | `Stop` | `Stop` |

Both agents pass `session_id`, `cwd` and `hook_event_name` to every hook.

- **Other harnesses:** the same command, if they expose hooks. Without hooks the channel works but has no status.
- **Classic apps:** no status, the LED is only steady or off.

**Installing the hooks.** The app offers it from Settings, showing first what it writes:
- Claude Code: `~/.claude/settings.json`, adding entries next to the existing ones without touching hooks already there;
- Codex: `~/.codex/hooks.json`. Codex asks to approve unmanaged hooks before running them. **The `notify` already in `config.toml` is not touched**, because Codex's Computer Use relies on it.

## 5. Grey and white

### 5.1 Grey: actions on the channel
- **Tap:** runs the Run slot, otherwise Return on the channel.
- **Double tap:** undoes the last insertion, with the right method for the app (⌘Z in apps, other keys in terminals, depending on the profile).
- **Long press:** Interrupt. The profile decides the key: Esc for Claude Code and Codex, nothing for classic apps.
- **Pressed during dictation:** command (§6).

Grey must stay reliable even when the voice is misheard: that is why its actions never go through the LLM.

### 5.2 White: prompts and skills, as today but per channel
- The slots stay those of One-Pager 001 (up to 15, white LEDs in binary, name on the pill), with the three types **Run**, **Template** and **LLM**.
- **Slots follow the channel:** they are the slots of the channel app's profile. Changing channel changes the slots, so each channel has only a few.
- **The LLM starts only with LLM slots.** Run (keys, `/compact`) and Template (`Use the "review" skill on: {{text}}`) are text substitutions, instant.
- The slot selection is remembered **per channel** and goes back to "no slot" after use, as today.

## 6. Voice commands: handle + grey

### 6.1 The gesture
- While you hold the handle, **one press of grey, at any moment, is enough**: the sentence becomes a command. There is no need to hold it until the end.
- Grey pressed during dictation does **not** trigger its normal action (Return) on release.
- The pill shows "Command" and the red LEDs use an animation different from KITT, so it is immediately clear that the sentence will not be typed.

The gesture already exists (`markEditSelection` in `DictationController`); its meaning changes. The old "edit the selection" becomes a special case of the command (§6.2, level 2).

### 6.2 What a command can do
The speech is not typed. It goes to the LLM, which answers with a JSON of actions from a **closed vocabulary**, then validated. The `{"actions":[…]}` format of the old Command mode is reused and extended:

| Level | Actions | Examples |
|---|---|---|
| 1. Text and keys *(exists)* | `text`, `key` in the focused field | "delete the last sentence", "new line", "select all" |
| 2. Selection | `replaceSelection` with the transformed text, when there is a selection | "translate it into English", "turn it into a list" |
| 3. Channels and slots | `switchChannel(name)`, `runSlot(name)`, `intent(name)` | "switch to the api project", "run the review", "new session", "interrupt" |
| 4. App menus *(phase 2)* | `menu(path)`, chosen from the menu items read through Accessibility | "export to PDF" in Word, "reply all" in Mail |

**Intents** are abstract actions that the profile maps to keys: `interrupt`, `approve`, `approveAlways`, `reject`, `newSession`, `cycleAgentMode`. An intent the profile does not define shows "not available here". This way a new harness is supported by mapping its keys to the intents, without touching the code.

**Level 4** makes commands generic for any app without configuration, because menus are a finite list that the app itself declares. It is not Computer Use: no clicks on screen coordinates.

### 6.3 Context passed to the LLM
The context stays short, to keep latency low:
- app and channel name;
- agent status;
- selected text, if any;
- names of the channel's slots and names of the channels;
- intents available in the profile;
- menu items (only from level 4, filtered and truncated).

The system prompt and the examples become **language-neutral**: today they are in Italian, while the sentence can arrive in any language Whisper recognises.

### 6.4 Agent waiting: an answer without a gesture
It is the only automatic rule. If the selected channel has an agent **waiting for an answer** (a permission or a question, signalled by the hook), the dictated sentence is treated as an **answer** even without grey:
- "sì", "no", "yes", "ok" are recognised with a **text match**, without the LLM and therefore without waiting;
- longer sentences ("yes, always for this session", "no, use pnpm") go to the LLM, which picks the option or writes the answer.

### 6.5 Answering permissions through hooks
For permissions, no keys are simulated in the interface: the answer goes **through the `PermissionRequest` hook**, which both Claude Code and Codex support. It is sturdier, because it depends neither on how the window looks nor on the app's shortcuts.

How it works:
1. The agent is about to ask for a permission and calls the hook. `fxmic-notify` tells the app, which blinks the channel's LED and shows on the pill what is being asked (tool and command, from the `tool_name` and `tool_input` fields).
2. The hook **waits** for the app's answer for a short, configurable time (for example 20 s).
3. If the user answers by voice:
   - "yes" → the hook returns `allow`;
   - "no" → `deny`, with the dictated reason if there is one ("no, use pnpm"), which reaches the agent as an explanation;
   - "yes always" → `allow` plus the permanent rule, if the agent supports it, otherwise just `allow`.
4. If the time runs out or the user answers with the mouse, the hook does not decide and the agent shows its normal permission dialog: in Codex with the provided "defer", in Claude Code by returning an empty answer.

Questions (`elicitation_dialog`, `agent_needs_input`) do not go through `PermissionRequest`: there the answer is typed into the agent's field and sent.

**Point to clarify in testing:** with the hook waiting, do Claude Code and Codex already show their permission dialog, or only once the hook ends? In the second case the wait must be kept shorter, so as not to hide the request from someone who is not using the voice.

The rule "no text field focused → command" was **rejected**: in agent apps the input field is almost always focused, and in other apps the signal is too uncertain.

### 6.6 Safety and errors
- The blocked-key list of `CommandParser.forbidden` stays: no ⌘Q, ⌘W, ⌘Tab and similar.
- If the answer is invalid, or the command is ambiguous, **nothing runs** and the pill says so.
- After running, the pill shows what was done, for example "✓ Ran: review", and everything goes into the history.
- Destructive menu items (Delete, Quit, Close) are excluded from level 4.

## 7. LLM: local and external
- The current client (`LLMClient`) already uses `/chat/completions` in the OpenAI format, but sends no API key and uses one endpoint for everything.
- An **optional API key** is added (stored in the Keychain), together with the option of choosing the endpoint **per use**: commands, LLM slots. Local stays the default.
- When a sentence leaves the Mac, the pill shows an **"external" indicator**.
- **Fallback:** if the LLM does not answer, the command is not run and a notice appears; an LLM slot types the raw text.

## 8. Data model changes (schema v3)
- `channels`: 4 items `{name, target: {bundleId, document?, cwd?, sessionId?}, slotIndex}`, stored globally and not per profile.
- `Profile.interaction` is replaced by:
  - `intents`: intent → action map (for example `interrupt: key escape`);
  - `commandHints`: hints for the LLM (already there).
- `Profile.slots` stays as it is.
- `InteractionMode` goes away. The old `enabledModes` and `defaultMode` settings are ignored. The "Enhanced" prompt becomes, if present, an LLM slot called "Enhance" in the profile.
- `llm`: `apiKeyRef` and an optional per-use `endpoints` are added.
- Gestures: new actions `nextChannel`, `previousChannel`, `bindChannel`, `interrupt`. `cycleMode` and `resetMode` stay for compatibility but are no longer assigned.

## 9. Compatibility
- The first launch with schema v3 creates `config.json.bak` and converts the file as described in §8.
- With no channels bound, the app behaves like today without modes: dictation goes to the app in front.

## 10. Checks
Details in `logs/TEST_NOTES.md`, section "One-Pager 004 §10 checks (2026-10-22)".

| # | Check | Result |
|---|---|---|
| 1 | Text field and document through Accessibility (Claude desktop, Codex, VS Code, Terminal, Ghostty, Word, Mail; `AXManualAccessibility` for Electron apps) | **Open.** The test must run from a process with the Accessibility permission (FXMic Bridge or an authorised terminal) |
| 2 | Claude Code hooks in the desktop app | **Partly.** The documentation says they fire in the desktop app too; the `cliSessionId` ↔ `session_id` map is verified. A field test in a new session is missing (hooks do not reload while a session is open) |
| 3 | Codex events | **Yes, on paper:** stable hooks in codex-cli 0.154, with `PermissionRequest` and `Stop`. To be tried in the desktop app |
| 4 | Opening a specific session | **Solved:** deep links in both apps (§4.3). Switching between two Claude sessions and opening a Codex thread still have to be checked by eye |
| 5 | Answering permissions | **Passed:** the answer goes through the hook (§6.5), not keys. How the permission dialog behaves while the hook waits is still to be understood |
| 6 | Command latency | **Passed:** qwen3.5:4b, 12 sentences in 4 languages, median 644 ms, maximum 770 ms. Channels, slots and intents right 9 times out of 10; text and keys need examples in the prompt for each level |

## 11. Alternatives considered
- **Modes on orange (One-Pager 001):** rejected for the reasons in §1.
- **"Prompt" mode (rewriting speech as a prompt) and "Ask" mode (a question answered on the pill):** rejected by the user.
- **Commands recognised by their first word** ("command…"): rejected, because they require remembering a keyword.
- **An LLM deciding for every sentence whether it is text or a command:** rejected because of latency.
- **LLM only when no text field is focused:** rejected (§6.4).
- **Grey tap to approve:** not sturdy enough; replaced by §6.4, §6.5 and the intents.
- **Answering permissions by simulating the interface's keys:** rejected in favour of the `PermissionRequest` hook (§6.5), which does not depend on how the apps look.
- **Selecting the session by clicking in the sidebar through Accessibility:** kept only as a last resort, because both apps have a deep link (§4.3).
- **Voice feedback, queue, capture, literal formatters:** deferred.

## 12. Risks
1. **Undocumented session index and deep links** (§4.3): a Claude or Codex update can change them. Mitigation: a tolerant reader and a fallback to the app alone; an automatic format check at startup, with a notice in Settings if it is no longer recognised.
2. **Hook waiting for the answer** (§6.5): if the wait hides the permission dialog, someone not using the voice waits without knowing why. Mitigation: a short, configurable wait, with the option of turning it off.
3. **Accessibility of Electron apps**: it may expose little or nothing without `AXManualAccessibility`.
4. **Reliability of commands with the 4B model** as the vocabulary grows: that is why we start with levels 1–3 and level 4 comes in phase 2.
5. **Hooks that differ between harnesses:** Claude Code and Codex are covered; other harnesses may have no status.
6. **Bringing a window to the front** at every dictation can be disruptive if you are working elsewhere. It is intended, but must be checked in use.

## 13. Plan
1. Close the open checks of §10: Accessibility, hooks in the Claude and Codex desktop apps, permission dialog with the hook waiting.
2. Schema v3, migration and unit tests.
3. Channels: binding, fingerprint, session index reader, deep links, bringing to the front, status LEDs.
4. Hooks: the `fxmic-notify` command, answering permissions (§6.5) and guided installation for Claude Code and Codex.
5. Grey and white with the new mapping; slots per channel.
6. Commands: gesture, levels 1–3, answering a waiting agent, multilingual prompt.
7. External LLM: API key and per-use endpoints.
8. Level 4 (app menus).
9. Update `GESTURES.md`, the TDD and the site, then verify on the device.

## 14. Implementation status (rev. 3, 2026-10-23)

### 14.1 Implemented
| Part | Commit | Notes |
|---|---|---|
| Channels on orange, binding, LEDs, schema v3 | `d9e04a8` | |
| Claude and Codex sessions with adapters (`SessionAdapter`) | `d9e04a8` | log + deep link, configurable in `sessionAdapters` |
| Voice command (grey while you talk), intents, grey long press = interrupt | `d9e04a8` | levels 1–3 of §6.2 |
| Settings: Channels chapter, paged profiles, voice command test | `7c9c813`, `b157bff` | |
| **The voice goes where you are** and **clear the channels** | `d439862` | changes §4, see 14.2 |
| Claude chats and projects as channels | `2656f04` | page address through Accessibility |
| Channels across Claude organizations (workspaces) | — | see 14.4 |

### 14.2 What changed compared with the design
- **No jump when you talk.** §4.1 had the selected channel's window brought to the front when you talk. In use it was awkward: working in an app that was not bound, the voice took you back to the channel. Now **the window in front of you decides**: if it is a channel the voice goes there, otherwise you are **free** (red LEDs off) and the voice goes where your cursor is. Only orange makes you jump. The profile always follows the app in front.
- **No empty position.** Orange cycles only through the bound channels (from free it starts at the first or the last). The long press adds the window to the first empty channel; with four channels it replaces the one you are on.
- **Clear the channels:** orange held **3 s** (`veryLongPress` gesture), from the menu with confirmation and undo, from Settings with confirmation.
- **Claude chats and projects:** they have no log lines, so a channel saves the address read from the web page (the adapter's `webPattern`/`webLink`) and returns to it with `claude://claude.ai/chat/…`. Without this, there was no way back to a chat from the Code view.
- **Grey long press = interrupt** in non-coding profiles too (before: retype the last raw text).

### 14.4 Channels across Claude organizations
Claude desktop's two bottom-left "profiles" are organizations of one account, and sessions and chats live in one of them. A deep link opens in the active organization only, and the only way to change it is the account menu (the sidebar's titled pop-up button), which reloads the window.
- A channel saves its `organization`: for a Claude Code session from the folder of its file (`claude-code-sessions/<account>/<organization>/…`), for a chat from the active organization, read from `main.log` (`Org changed from … to …`, or the startup line `Initialization succeeded … orgId=…`; the older `main1-3.log` are read too).
- Orange to a channel of another organization opens the account menu through Accessibility and presses the entry as soon as it is drawn (no fixed waits, no pill). It then reads only what `main.log` gets from that moment: `Org changed … to <target>` and, after it, `Loaded https://claude.ai` (the window has reloaded, `organizationReadyPattern`); the link is opened right then. Measured on 2026-10-24: Claude logs the change in the same second as the press and reloads within about one more second. The reload itself is Claude's and cannot be hidden.
- A **curtain** (`SwitchCurtain`) covers Claude's window from the tap until the target is on screen: a panel in Claude's background colour (light or dark, following Claude's theme setting) with the channel name, which fades out when the web view shows the chat's address or the log reports the session focused after the link was opened (2.5 s at most). It is not a picture of the window, so no Screen Recording permission is needed, and it never takes the focus or the clicks.
- When sessions of the current organization have terminals open, Claude asks first ("Switch to …? The terminals in your sessions will be closed"). The curtain is lifted at once and the dialog is left to the user: confirming continues the switch, cancelling ends it.
- The menu does not say which entry is which organization, so the app learns it: a press that ends in a known organization stores its label in `organizationLabels`, and with two entries the other one is the organization it came from. Until then it tries the candidates in order (`OrganizationPicker`), with a real click as a fallback if the press is ignored.
- Adapters get `organizationPattern` (group 1 = organization id) for other apps. **Not verified on the device yet**: the switch itself, and Codex workspaces.

### 14.3 Not done yet
- The `fxmic-notify` hook: agent status LEDs (§4.4), answering a waiting agent (§6.4) and permissions through the hook (§6.5). The test hooks of §10 are still installed in `.claude/settings.local.json` and `~/.codex/hooks.json`.
- External model with API key (§7) and level 4 of commands (app menus, §6.2): superseded by the [voice command agent TDD](tdd-v1-voice-command-agent.md), with one model for everything instead of per-use endpoints.
- Translations of the new UI strings (in English in every language today).
- Jack-only connection: tried with the Mac's headset jack, no signal (`logs/TEST_NOTES.md`); a USB audio interface with a line input still has to be tried.

## 15. Vocabulary for the README, the site and the video

The words used to present the product to the outside world, in English, the same in the README, site, video and app.

| Term | Meaning | Avoid |
|---|---|---|
| **channels** (orange) | up to 4 places where the voice goes: Claude Code and Codex sessions, Claude chats and projects, documents, apps | modes, interaction modes |
| **the voice goes where you are** | on a channel's window it goes to that channel; elsewhere you are **free** and it goes where your cursor is, with no jumps | "selected channel" as a fixed destination |
| **free** | no channel in front: red LEDs off | empty position |
| **skills & commands** (white) | up to 15 per app: a command that grey runs, a skill/template or an LLM rewrite applied to the next dictation | slots (only in technical details), styles |
| **send · interrupt** (grey) | tap = runs the command or Return; long press = interrupt | rewrite the last text |
| **voice command** (grey while you talk) | the sentence becomes actions: text, keys, selection, channels, skills, intents; in any language | enhanced, command mode, computer use |
| **hold orange for 3 s** | clears the channels | — |
| **local by design** | transcription and model on the Mac | — |

Key messages, in this order:
1. *Hold the handle, talk, release: the words land where your cursor is.*
2. *Four channels on the orange button: jump between Claude Code sessions, Claude chats, Codex threads and documents. Anywhere else the voice just goes where you are.*
3. *Grey while you talk turns a sentence into actions, in any language.*
4. *White picks a skill or a command; grey sends it.*
5. *Everything runs on your Mac.*
