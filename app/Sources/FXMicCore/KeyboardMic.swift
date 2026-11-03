/// Keyboard input translated into the same gestures as the FX-MIC.
public struct KeyboardMic {
    public struct Result {
        public let gestures: [Gesture]
        public let intercept: Bool
    }

    private var recognizer: GestureRecognizer
    private var commandPressedAt: Double?
    private var commandUsed = false
    /// The arrow held together with right Command, until its key-up (even after Command is released).
    private var heldArrow: (keyCode: UInt16, start: Double, shakeHoldFired: Bool)?

    public init(settings: GestureSettings = GestureSettings()) {
        recognizer = GestureRecognizer(settings: settings)
    }

    /// Key codes of the arrows that act as buttons while right Command is held:
    /// left = orange, right = white, down = shake. Only these combinations are intercepted.
    private static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125

    /// Key codes identify physical keys, independently of the keyboard layout.
    /// Right Command is provisional until release: a later shortcut key must still cancel it.
    /// For a chord, release Command before releasing the right-Option handle.
    /// Right Command held with an arrow is orange, white or the shake; those events are intercepted
    /// (never with the left Command, never a plain arrow).
    public mutating func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool = false,
                                at time: Double) -> Result {
        if keyCode == 54 {
            guard !isRepeat else { return Result(gestures: [], intercept: false) }
            if isDown {
                if commandPressedAt == nil {
                    commandPressedAt = time
                    commandUsed = false
                }
                return Result(gestures: [], intercept: false)
            }
            guard let start = commandPressedAt else {
                return Result(gestures: [], intercept: false)
            }
            commandPressedAt = nil
            guard !commandUsed else { return Result(gestures: [], intercept: false) }
            var gestures = recognizer.handle(.grey, active: true, at: start)
            gestures += recognizer.handle(.grey, active: false, at: time)
            return Result(gestures: gestures, intercept: false)
        }
        if keyCode == Self.left || keyCode == Self.right || keyCode == Self.down {
            return handleArrow(keyCode: keyCode, isDown: isDown, isRepeat: isRepeat, at: time)
        }
        if isDown, commandPressedAt != nil { commandUsed = true }
        guard keyCode == 61 else { return Result(gestures: [], intercept: false) }
        // Right Option is the handle: its events are consumed so that no other app reacts to
        // them (a double tap of it opens Claude, for one).
        guard !isRepeat else { return Result(gestures: [], intercept: true) }
        // A chord must commit while its take is still recording, never after pttUp.
        if !isDown, commandPressedAt != nil, recognizer.handleDown { commandUsed = true }
        return Result(gestures: recognizer.handle(.handle, active: isDown, at: time),
                      intercept: true)
    }

    private mutating func handleArrow(keyCode: UInt16, isDown: Bool, isRepeat: Bool,
                                      at time: Double) -> Result {
        let pass = Result(gestures: [], intercept: false)
        let swallow = Result(gestures: [], intercept: true)
        if let held = heldArrow {
            guard keyCode == held.keyCode else {
                // Another arrow during the combination: swallowed while Command is down.
                return isDown && commandPressedAt != nil ? swallow : pass
            }
            if isDown { return swallow }   // auto-repeat of the held arrow
            heldArrow = nil
            switch keyCode {
            case Self.left: return Result(gestures: recognizer.handle(.orange, active: false, at: time), intercept: true)
            case Self.right: return Result(gestures: recognizer.handle(.white, active: false, at: time), intercept: true)
            default: return Result(gestures: held.shakeHoldFired ? [] : [.shake], intercept: true)
            }
        }
        guard isDown, !isRepeat, commandPressedAt != nil else { return pass }
        commandUsed = true   // right Command with an arrow is never a grey tap
        heldArrow = (keyCode, time, false)
        switch keyCode {
        case Self.left: return Result(gestures: recognizer.handle(.orange, active: true, at: time), intercept: true)
        case Self.right: return Result(gestures: recognizer.handle(.white, active: true, at: time), intercept: true)
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
