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
    private var heldArrow: UInt16?

    public init(settings: GestureSettings = GestureSettings()) {
        recognizer = GestureRecognizer(settings: settings)
    }

    /// Key codes of the arrows that act as buttons while right Command is held:
    /// left = orange, right = white. Only these combinations are intercepted.
    private static let left: UInt16 = 123, right: UInt16 = 124

    /// Key codes identify physical keys, independently of the keyboard layout.
    /// Right Command is provisional until release: a later shortcut key must still cancel it.
    /// For a chord, release Command before releasing the right-Option handle.
    /// Right Command held with ← or → is orange or white; those events are intercepted
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
        if keyCode == Self.left || keyCode == Self.right {
            return handleArrow(keyCode: keyCode, isDown: isDown, isRepeat: isRepeat, at: time)
        }
        if isDown, commandPressedAt != nil { commandUsed = true }
        guard keyCode == 61, !isRepeat else {
            return Result(gestures: [], intercept: false)
        }
        // A chord must commit while its take is still recording, never after pttUp.
        if !isDown, commandPressedAt != nil, recognizer.handleDown { commandUsed = true }
        return Result(gestures: recognizer.handle(.handle, active: isDown, at: time),
                      intercept: false)
    }

    private mutating func handleArrow(keyCode: UInt16, isDown: Bool, isRepeat: Bool,
                                      at time: Double) -> Result {
        let pass = Result(gestures: [], intercept: false)
        let swallow = Result(gestures: [], intercept: true)
        if let held = heldArrow {
            guard keyCode == held else {
                // Another arrow during the combination: swallowed while Command is down.
                return isDown && commandPressedAt != nil ? swallow : pass
            }
            if isDown { return swallow }   // auto-repeat of the held arrow
            heldArrow = nil
            let button: DeviceControl = keyCode == Self.left ? .orange : .white
            return Result(gestures: recognizer.handle(button, active: false, at: time), intercept: true)
        }
        guard isDown, !isRepeat, commandPressedAt != nil else { return pass }
        commandUsed = true   // right Command with an arrow is never a grey tap
        heldArrow = keyCode
        let button: DeviceControl = keyCode == Self.left ? .orange : .white
        return Result(gestures: recognizer.handle(button, active: true, at: time), intercept: true)
    }

    public mutating func tick(at time: Double) -> [Gesture] {
        recognizer.tick(at: time)
    }
}
