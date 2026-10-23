import Foundation

public enum MicButton: Int, Sendable, CaseIterable {
    case grey = 0, white = 1, orange = 2
}

public enum Gesture: Equatable, Sendable {
    case pttDown
    case pttUp
    case tap(MicButton)
    case doubleTap(MicButton)
    case longPress(MicButton)
    /// A button held for `veryLongPressMs`, after the long press has already fired.
    case veryLongPress(MicButton)
    /// Grey pressed while the handle is held (TDD §3.2: edit-selection chord).
    case chordGrey
    case shake
    /// Two quick handle clicks (each shorter than `handleClickMaxMs`).
    case handleDoubleClick
    /// Strong shake sustained for `shakeHoldMs` (e.g. "clear all").
    case shakeHold
}

public struct GestureSettings: Sendable {
    public var tapMaxMs: Double = 450
    public var doubleTapMs: Double = 300
    public var longPressMs: Double = 600
    public var veryLongPressMs: Double = 3000
    public var shakeThreshold: Double = 0.5
    public var shakeConsecutive: Int = 2
    /// Minimum gap between two shake gestures.
    public var shakeCooldownMs: Double = 1000
    /// A handle press shorter than this counts as a click (also too short to dictate).
    public var handleClickMaxMs: Double = 280
    /// Max gap between the first click's release and the second click's press.
    public var handleDoubleClickGapMs: Double = 400
    public var shakeHoldThreshold: Double = 0.5
    public var shakeHoldMs: Double = 2000
    /// Dips below the threshold shorter than this do not break a sustained shake.
    public var shakeHoldToleranceMs: Double = 400
    public init() {}
}

/// Turns raw device switch events and polls into gestures (TDD §3.2).
/// Pure and clock-injected: feed events with `handle(_:at:)` and call `tick(at:)` periodically
/// so long-presses fire while held and single taps resolve after the double-tap window.
public struct GestureRecognizer {
    public var settings: GestureSettings
    public private(set) var handleDown = false

    private var pressedAt: [MicButton: Double] = [:]
    private var longFired: Set<MicButton> = []
    private var veryLongFired: Set<MicButton> = []
    private var chordFired = false
    private var pendingTap: [MicButton: Double] = [:]   // release time of an unresolved single tap
    private var shakeCount = 0
    private var lastShake = -Double.infinity
    private var handlePressedAt: Double?
    private var lastHandleClick: Double?   // release time of a short handle click
    private var shakeHoldStart: Double?
    private var shakeHoldLastAbove = -Double.infinity
    private var shakeHoldFired = false

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    /// `time` is in milliseconds on any monotonic clock.
    public mutating func handle(_ control: DeviceControl, active: Bool, at time: Double) -> [Gesture] {
        var out = tick(at: time)
        if control == .handle {
            guard active != handleDown else { return out }
            handleDown = active
            if active {
                handlePressedAt = time
                out.append(.pttDown)
                return out
            }
            // pttUp first: the dictation discards the too-short take before the click action.
            out.append(.pttUp)
            let pressed = handlePressedAt ?? time
            handlePressedAt = nil
            if time - pressed <= settings.handleClickMaxMs {
                if let first = lastHandleClick, pressed - first <= settings.handleDoubleClickGapMs {
                    lastHandleClick = nil
                    out.append(.handleDoubleClick)
                } else {
                    lastHandleClick = time
                }
            } else {
                lastHandleClick = nil
            }
            return out
        }
        guard let button = MicButton(rawValue: control.rawValue) else { return out }
        if active {
            pressedAt[button] = time
            longFired.remove(button)
            veryLongFired.remove(button)
            if button == .grey, handleDown {
                chordFired = true
                out.append(.chordGrey)
            }
            return out
        }
        // release
        guard let start = pressedAt.removeValue(forKey: button) else { return out }
        if button == .grey, chordFired {
            chordFired = false
            return out
        }
        veryLongFired.remove(button)
        if longFired.remove(button) != nil { return out }
        guard time - start <= settings.tapMaxMs else { return out }
        // Selecting mode/style while talking is ignored, like the factory firmware.
        if handleDown, button != .grey { return out }
        if let first = pendingTap.removeValue(forKey: button), time - first <= settings.doubleTapMs {
            out.append(.doubleTap(button))
        } else {
            pendingTap[button] = time
        }
        return out
    }

    public mutating func poll(shaker: Double, at time: Double) -> [Gesture] {
        var out = tick(at: time)
        if shaker > settings.shakeHoldThreshold {
            if shakeHoldStart == nil { shakeHoldStart = time }
            shakeHoldLastAbove = time
            if !shakeHoldFired, let start = shakeHoldStart, time - start >= settings.shakeHoldMs {
                shakeHoldFired = true
                out.append(.shakeHold)
            }
        } else if time - shakeHoldLastAbove > settings.shakeHoldToleranceMs {
            shakeHoldStart = nil
            shakeHoldFired = false
        }
        if shaker > settings.shakeThreshold {
            shakeCount += 1
            if shakeCount >= settings.shakeConsecutive, time - lastShake >= settings.shakeCooldownMs {
                lastShake = time
                shakeCount = 0
                out.append(.shake)
            }
        } else {
            shakeCount = 0
        }
        return out
    }

    public mutating func tick(at time: Double) -> [Gesture] {
        var out: [Gesture] = []
        for (button, start) in pressedAt {
            if button == .grey, chordFired { continue }
            if !longFired.contains(button), time - start >= settings.longPressMs {
                longFired.insert(button)
                out.append(.longPress(button))
            }
            // Never while talking: holding a button with the handle down is not this gesture.
            if longFired.contains(button), !veryLongFired.contains(button), !handleDown,
               time - start >= settings.veryLongPressMs {
                veryLongFired.insert(button)
                out.append(.veryLongPress(button))
            }
        }
        for (button, released) in pendingTap where time - released > settings.doubleTapMs {
            pendingTap.removeValue(forKey: button)
            out.append(.tap(button))
        }
        return out
    }
}
