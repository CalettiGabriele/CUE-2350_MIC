# ADR-005: One slot counter for the whole mic, as the firmware has it

**Date:** 2026-10-30
**Status:** Accepted, implemented in `ProfileEngine` (commit `8abada6`)

## Context
The white LEDs show the slot number in binary, 0 (none) to 15. With the jack the Mac cannot talk to the mic (ADR-002), so the **firmware pages its own white LEDs**: a tap moves the number by one, modulo 16, whatever the profile in front has. The app learned about each tap as a gesture and moved **its own** selection, which until now was kept **per profile** and wrapped to "none" after the profile's last slot.

The two counters agreed only while the profile had 15 slots. With four slots, a fifth tap lit the third white LED on the mic while the app went back to "none": the island showed no slot, the slot's template was not applied, and after a dictation that used a slot the app cleared its selection while the mic kept the LEDs on. The island, which mirrors the LEDs, could not be right: either it showed what the app thought, or what the mic showed.

The firmware cannot be told how many slots a profile has (no Mac-to-mic path over the jack), and the profile changes with the app in front of you, so the count would be stale anyway.

## Decision
`ProfileEngine` keeps **one slot counter, 0 to 15, for the whole mic**, with the firmware's own rules:
- next / previous move it modulo 16; "no slot" sets it to 0;
- the selected slot is `slots[counter − 1]` of the profile in front, if that profile has one there; a number beyond the profile's slots **lights the LEDs and selects nothing**;
- a slot used by a dictation or a run (`consumeSlot`) **stops applying but keeps its number**, as the mic keeps its LEDs, until the next slot gesture;
- the selection is **no longer remembered per profile**: the number is the mic's, the slot behind it is the profile's.

The island and the LEDs both read the same logical mask, so they agree by construction (One-Pager 006).

## Consequences

**Positive**
- The island, the LEDs the Mac drives over USB and the mic's own LEDs over the jack show the same number at all times.
- No "invisible" slot state: what you see lit is what was selected.
- Simpler engine: one integer instead of a dictionary per profile.

**Negative**
- Changing app no longer remembers a slot per profile. Slot 2 in a terminal is slot 2 in Mail; what it does depends on the profile.
- After a slot is used the number stays lit with nothing applied until the next gesture; the island shows "No slot" in that case, which can look odd next to a lit LED.
- Tapping past the last defined slot lands on numbers with no slot instead of going straight to "none". With few slots that takes a few taps (or a double tap back, or a long press for none).
- Behaviour changes with USB too, where the app drives the LEDs: the number is kept after use, as on the jack.

## Alternatives considered
- **Keep per-profile selection and make the firmware wrap at the profile's count:** needs the count on the mic, which only a USB session can send, and it changes with the front app.
- **Keep the old engine and show the mic's number on the island by itself:** two sources of truth for one LED row; the template or skill applied would still disagree with the LEDs.
- **Reset the firmware counter on use:** impossible over the jack.
