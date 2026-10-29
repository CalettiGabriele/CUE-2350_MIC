# Smoke checks

Use this checklist after a change to handle ownership, recording or transport behavior. It is a manual procedure, not evidence that any case has passed. The [gesture reference](GESTURES.md) describes current behavior; [the jack channel](JACK-CHANNEL.md) explains acoustic codes and timing. [JackTransport.swift](../app/Sources/FXMicBridge/JackTransport.swift) decodes capture positions, and [GestureRouter.swift](../app/Sources/FXMicCore/GestureRouter.swift) authorizes the recording effects before those positions reach the recorder.

## Prepare a local build

1. On the Mac, from the repository's `app` directory, optionally run `./scripts/create-signing-identity.sh` once to create the local `CUE-2350 MIC Dev` signing identity. Keep its private key local; do not share credentials or keychain prompts.
2. Build and publish with `./scripts/bundle.sh` (release by default), or `./scripts/bundle.sh debug`. It uses the local development identity if available, otherwise ad-hoc signing. `SIGN_IDENTITY='-' ./scripts/bundle.sh` explicitly selects ad-hoc signing; an explicitly selected identity must succeed or the build fails.
3. If signing needs an interactive keychain session separate from the build, run `./scripts/bundle.sh --prepare` and note the printed prepared app path. In the interactive session run `./scripts/bundle.sh --finalize "<prepared-app-path>"`; this signs and publishes without rebuilding. Use the same `BUNDLE_OUTPUT_DIR`, if set, in both commands. Failed or interrupted finalization discards the staged app and leaves the previously published app intact; prepare a fresh bundle before retrying.
4. Open the published `dist/CUE-2350 MIC.app` (or the app under `BUNDLE_OUTPUT_DIR` if overridden). Grant **Microphone** and **Accessibility** to that actual app bundle in System Settings › Privacy & Security. Verify the selected audio input and speech model are ready. A stable local signing identity helps Accessibility grants survive rebuilds; ad-hoc signatures change with the binary, so grants may need to be removed and granted again after rebuilding. Confirm macOS shows the intended app, not another copy. Do not assume a prior grant applies.
5. If using an automation tool to drive the keyboard or inspect another app, grant that runner its own Accessibility permission as needed; the app's grant does not grant permission to the runner. Automation is not a substitute for a physical-keyboard check. Secure Keyboard Entry or secure text fields may prevent global key events from reaching the app; disable it for this test and avoid password fields.
6. Open a throwaway Notes note or TextEdit document, focus its editable body and use only harmless test phrases. Do not use a terminal, chat, real data or credentials as the output target.

## Keyboard only — human proof

Disconnect the FX-MIC or disable its transports. Record the macOS version, app build/signing identity and input device with the results.

- [ ] Physically hold **right Option**, speak a distinct phrase and release. Recording starts on hold, ends on release and the phrase appears in the throwaway document.
- [ ] Repeat, holding left Option too; releasing right Option still ends the take. Releasing left Option must not end a right-Option-owned take.
- [ ] Quickly double-click right Option. The configured handle double-click action runs (by default Shift-Return inserts a newline), without leaving a recording active.
- [ ] Repeat a normal hold/release after the double-click to check that recording still works.

## Hardware ownership and recovery

These cases require the physical FX-MIC. For USB use a data cable; for jack install [FXMic firmware](INSTALL-FIRMWARE.md) and connect its jack to a suitable USB audio input. Original firmware and the USB RAM agent do not emit the jack gesture codes. Configure the relevant connection and audio input. Run USB and jack cases separately and record firmware, connection and input details.

- [ ] Start a take with right Option, then press and release the physical handle while keeping right Option held. The physical events neither take ownership nor end the recording; release right Option and confirm one completed take.
- [ ] Start with the physical handle, then press and release right Option while keeping the physical handle held. Keyboard events neither take ownership nor end the recording; release the physical handle and confirm one completed take.
- [ ] During a USB-owned take, disconnect USB. The take is cancelled rather than committed; a subsequent right Option take still works. Reconnect USB and confirm a new physical take works.
- [ ] During a jack-owned take, stop the jack listener by changing the connection away from jack, or change the audio input to restart the listener. The take is cancelled rather than committed; a subsequent right Option take still works. Restore the jack connection/listener and confirm a new physical take works.
- [ ] Hold the jack handle for more than 12 seconds, speaking throughout, then release. No heartbeat is sent while held; heartbeat silence alone must not cancel the take. Confirm the recording lasts through the hold and completes on release.

## Audio boundary regression

Use distinct spoken markers before, during and after the accepted take; inspect the resulting transcription. Repeat with both ownership directions for USB and jack. A brief pre-roll is intentional: allow the configured capture timing described in [the jack channel](JACK-CHANNEL.md), and separate the markers by several seconds. An ignored source's press/release must not cut, extend or replace the owner's capture. In particular, keep speaking after the ignored handle is released but before releasing the owning handle; those words must still appear. Cancellation on transport loss must not insert a partial result. Repeat ambiguous speech-recognition results.

## Record results separately

- **Automated tests:** record command, date and pass/fail or not run; `cd app && ./scripts/test.sh` covers automated tests, not physical-keyboard or hardware proof.
- **Bundle publication:** `python3 app/scripts/test-bundle.py` exercises real ad-hoc signing in a temporary output directory, checks that failed or interrupted finalization preserves the previous bundle, and verifies successful replacement. It does not require keychain credentials or modify the installed app.
- **Human physical keyboard:** record each case as pass, fail or not run, with observations.
- **Physical USB and jack hardware:** record each case separately as pass, fail or unavailable/not run, including transport details and observations. Real hardware validation is pending until actually performed; do not infer it from automated tests or keyboard-only results.
