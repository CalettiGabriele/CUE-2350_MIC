# One-Pager 005 — Pause the music while the handle is held

> Date: 2026-10-27 · Status: **Implemented** (Spotify and Apple Music, option A); tried by the user on Spotify (pause and resume work, a handle click does not stop the music); latency not measured, Apple Music not tried
> References: One-Pager 002 (jack transport), `app/Sources/FXMicBridge/DictationController.swift`, `app/Sources/FXMicBridge/JackTransport.swift`, `app/scripts/bundle.sh`

## 1. Problem
With music playing (Spotify, Apple Music), the voice take also records the music, and the user has to pause and resume by hand. Wanted: holding the handle pauses the player, releasing it resumes only what the app paused. It must be an option in Settings, off by default, because with headphones or a low volume the music does not disturb the take.

## 2. Verdict
**Feasible, with a reliable path for Spotify and Apple Music and no reliable generic path.** The same code works over USB-C and over the jack, because it hangs on the `pttDown`/`pttUp` the app already gets from both transports.

## 3. Options
| Option | State known | Works for | Cost / problem |
|---|---|---|---|
| **A. AppleScript per app** (Spotify, Music) | Yes: `player state` is `playing`/`paused`/`stopped`; `pause` and `play` are explicit commands (checked in `Spotify.sdef`) | Spotify, Apple Music | One Automation consent per app. Needs `NSAppleEventsUsageDescription`. Sending an event to an app that is not running **launches it**: check `NSWorkspace.runningApplications` first |
| B. Media key (play/pause) | No: it is a toggle | Whatever is the "now playing" app, browsers included | With nothing playing it **starts** something. Reading the state needs MediaRemote, which has been closed to third-party apps since macOS 15.4 (this Mac runs 26.5) |
| C. Lower the system volume (CoreAudio) | Yes | Everything | It does not pause, it ducks; it also affects notifications and calls |
| D. Per-app volume (`sound volume` in Spotify) | Yes | Spotify only | Ducking, not pausing |

Recommendation: **A as the feature**; D as a later "lower instead of pause" setting; B and C left out. A generic path would need "is this process playing" from CoreAudio process objects (`kAudioProcessPropertyIsRunningOutput`, macOS 14.2+) plus the media key, and still hits the wrong app when two are open: not worth it for a first version.

## 4. Behaviour
1. `pttDown` → for each enabled player that is running and `playing`: pause it and remember that **we** paused it.
2. `pttUp`, take cancelled, error, too-short take, shake, or app quit → resume only the players we paused, and only if they are still `paused` (if the user started something else or resumed by hand, do nothing).
3. A handle click (double click = new line) must not pause and resume the music: the pause is sent after ~150 ms of holding. The first ~150 ms of the take may contain music; the take can drop it, or the delay can be a setting.
4. Never touch a player that was paused before the handle.
5. If the app dies while the music is paused it stays paused; acceptable.

## 5. Where it goes in the code
- New `MediaController` (app target): a `MediaPlayer` protocol (`isRunning`, `state`, `pause`, `play`) with an AppleScript backend per app; the state machine (who we paused) is pure and lives in `FXMicCore`, tested with a fake player.
- Hooks: `DictationController` start and every end of a take (it already has a single place for "take over").
- Run the scripts off the main thread, compile each `NSAppleScript` once, warm it up when the transport starts so the first press does not pay for the scripting bridge.
- Config: `audio.pauseMedia { enabled: false, apps: ["spotify", "music"], holdMs: 150 }`.
- Settings › Audio: toggle "Pause the music while I talk", one checkbox per player, and a status line ("Allowed" / "Not allowed: grant it in System Settings › Privacy › Automation"). New strings go in `translations.py` (9 columns).
- `bundle.sh`: add `NSAppleEventsUsageDescription`. The stable signing identity keeps the Automation grant across rebuilds.

## 6. Risks and what to verify first
- **Latency of `pause`**: not measured. Spike: time `player state` and `pause` from `NSAppleScript` with Spotify playing (cold and warm). Pass if warm is under ~50 ms.
- Spotify's pause may fade: if it is not instant, the take still carries the tail.
- Spotify desktop only; the web player and browsers are out of scope.
- Automation consent is per app and can be refused: the setting must show it, not fail silently.
- Resume while the user is still speaking to the agent (answer in a voice reply): out of scope.

## 7. Estimate
About one day: `MediaController` + tests, hooks, Settings and translations, plist key, spike on the real Spotify. The generic path (B/C) is not planned.

## 8. Implementation notes (2026-10-27)
- `FXMicCore/MediaPauser.swift` is the pure state machine (tested with fake players in `MediaPauserTests`); `FXMicBridge/MediaController.swift` holds the AppleScript players and the delayed pause on a serial queue.
- `DictationController.onHold(true/false)` marks the start of a take and every way it ends (release, cancel, start failure); the app also resumes on quit.
- Config `audio.pauseMedia { enabled, apps, holdMs }`; Settings › Audio › Music, one row per player with the Automation status and an "Allow" button; `NSAppleEventsUsageDescription` added by `bundle.sh`.
- **Tried by the user on Spotify (2026-10-28):** the Automation prompt, pause and resume, and a handle click leaves the music alone.
- **Still to verify:** Apple Music, the latency of `pause` and whether Spotify fades.
