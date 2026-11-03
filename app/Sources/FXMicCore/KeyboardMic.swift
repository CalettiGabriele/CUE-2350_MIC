/// Keyboard input translated into the same gestures as the FX-MIC.
public struct KeyboardMic {
    public struct Result {
        public let gestures: [Gesture]
        public let intercept: Bool
    }

    private var recognizer: GestureRecognizer
    private var commandDown = false
    private var optionDown = false
    /// Right ⌥ and right ⌘ held together while a take runs: the take is a voice command.
    private var commandMode = false
    /// The arrow held together with right Command, until its key-up (even after Command is released).
    private var heldArrow: (keyCode: UInt16, start: Double, shakeHoldFired: Bool)?

    /// True while a risky action waits for an answer: only then does ⌘↑ mean "yes".
    public var confirmationPending = false

    public init(settings: GestureSettings = GestureSettings()) {
        recognizer = GestureRecognizer(settings: settings)
    }

    /// Key codes of the arrows that act as buttons while right Command is held:
    /// left = orange, right = white, down = shake ("no"), up = "yes" (only during a confirmation).
    private static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    private static let rightCommand: UInt16 = 54, rightOption: UInt16 = 61

    /// Key codes identify physical keys, independently of the keyboard layout.
    /// Right Option is the handle; its events are consumed so that no other app reacts to them
    /// (a double tap of it, for instance, opens Claude). Right Command alone does nothing: it only
    /// combines with right Option (voice command) or with an arrow (orange, white, "no", "yes").
    /// Those arrow events are intercepted too (never with the left Command, never a plain arrow).
    public mutating func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool = false,
                                at time: Double) -> Result {
        let pass = Result(gestures: [], intercept: false)
        switch keyCode {
        case Self.rightCommand:
            guard !isRepeat, isDown != commandDown else { return pass }
            commandDown = isDown
            return Result(gestures: updateCommandMode(at: time), intercept: false)
        case Self.rightOption:
            guard !isRepeat else { return Result(gestures: [], intercept: true) }
            var gestures: [Gesture] = []
            if isDown != optionDown {
                optionDown = isDown
                if isDown {
                    gestures = recognizer.handle(.handle, active: true, at: time)
                    gestures += updateCommandMode(at: time)
                } else {
                    gestures = endCommandModeIfNeeded(at: time)
                    gestures += recognizer.handle(.handle, active: false, at: time)
                }
            }
            return Result(gestures: gestures, intercept: true)
        case Self.left, Self.right, Self.down, Self.up:
            return handleArrow(keyCode: keyCode, isDown: isDown, isRepeat: isRepeat, at: time)
        default:
            return pass
        }
    }

    /// Both modifiers down with a take running: the command mode starts (once per take).
    private mutating func updateCommandMode(at time: Double) -> [Gesture] {
        if commandDown, optionDown, recognizer.handleDown, !commandMode {
            commandMode = true
            return recognizer.handle(.grey, active: true, at: time)   // .chordGrey while the handle is down
        }
        if !commandDown, commandMode {
            // The command runs as soon as either key is let go.
            return endCommandModeIfNeeded(at: time)
        }
        return []
    }

    private mutating func endCommandModeIfNeeded(at time: Double) -> [Gesture] {
        guard commandMode else { return [] }
        commandMode = false
        var gestures = recognizer.handle(.handle, active: false, at: time)   // .pttUp: the command runs
        gestures += recognizer.handle(.grey, active: false, at: time)        // clears the chord
        return gestures
    }

    private mutating func handleArrow(keyCode: UInt16, isDown: Bool, isRepeat: Bool,
                                      at time: Double) -> Result {
        let pass = Result(gestures: [], intercept: false)
        let swallow = Result(gestures: [], intercept: true)
        if let held = heldArrow {
            guard keyCode == held.keyCode else {
                // Another arrow during the combination: swallowed while Command is down.
                return isDown && commandDown ? swallow : pass
            }
            if isDown { return swallow }   // auto-repeat of the held arrow
            heldArrow = nil
            switch keyCode {
            case Self.left: return Result(gestures: recognizer.handle(.orange, active: false, at: time), intercept: true)
            case Self.right: return Result(gestures: recognizer.handle(.white, active: false, at: time), intercept: true)
            case Self.up: return swallow
            default: return Result(gestures: held.shakeHoldFired ? [] : [.shake], intercept: true)
            }
        }
        guard isDown, !isRepeat, commandDown else { return pass }
        // ⌘↑ is only "yes" while a confirmation waits; otherwise it is an ordinary shortcut.
        if keyCode == Self.up, !confirmationPending { return pass }
        heldArrow = (keyCode, time, false)
        switch keyCode {
        case Self.left: return Result(gestures: recognizer.handle(.orange, active: true, at: time), intercept: true)
        case Self.right: return Result(gestures: recognizer.handle(.white, active: true, at: time), intercept: true)
        case Self.up: return Result(gestures: [.tap(.grey)], intercept: true)
        default: return swallow   // the shake is decided on release, or when held long enough
        }
    }

    public mutating func tick(at time: Double) -> [Gesture] {
        var gestures = recognizer.tick(at: time)
        if let held = heldArrow, held.keyCode == Self.down, !held.shakeHoldFired,
           time - held.start >= recognizer.settings.shakeHoldMs {
            heldArrow?.shakeHoldFired = true
            gestures.append(.shakeHold)
        }
        return gestures
    }
}
