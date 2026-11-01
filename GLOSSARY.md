# CUE-2350 MIC

A macOS menu bar app that turns the EP-2350 FX-MIC (or the keyboard) into a voice remote for the Mac and for coding agents.

## Language

### Input

**FX-MIC**:
The EP-2350 FX-MIC hardware: a handle, three buttons, eight LEDs and an accelerometer.
_Avoid_: CUE, device (when the hardware is meant)

**Keyboard mic**:
The set of keys on the Mac keyboard that acts as a virtual FX-MIC, producing the same gestures as the handle, the buttons and the shake.
_Avoid_: hotkeys, fallback, keyboard shortcuts

**Connection**:
How the FX-MIC talks to the app: USB-C or the 3.5 mm jack. The keyboard mic is not a connection.

**Handle**:
The FX-MIC's push-to-talk lever: held, it records dictation.

**Button**:
One of the FX-MIC's three buttons, named by colour: grey, white, orange.

**Gesture**:
A recognised input from the handle, a button or the shake: tap, double tap, long press, very long press, chord, handle double click, shake, shake hold.

**Chord**:
Grey pressed while the handle is held; it turns the dictation into a voice command.

### Where the voice goes

**Channel**:
A saved destination (an agent session, a chat, a document, a window or an app) that orange jumps between; up to four.
_Avoid_: bookmark, target

**Free**:
The state of being on no channel: the voice goes where the cursor is.

### What the voice does

**Dictation**:
Speech transcribed locally and written where the voice goes.

**Voice command**:
A dictation that is turned into actions by the local agent instead of being written.
_Avoid_: edit selection

**Confirmation**:
The yes/no the app asks for before a risky action of a voice command; no answer means no.

**Profile**:
The set of slots, intents and button actions that applies to the app in front.

**Slot**:
One entry of a profile's list on white: a command, a skill/template or an LLM rewrite.

**Intent**:
A named action (such as `interrupt`) that each profile maps to its own keys.

### On screen

**Island**:
The black status shape at the top of the screen that mirrors the LEDs and shows recording, destination and cards.
_Avoid_: pill, HUD
