/// Keyboard input translated into the same gestures as the FX-MIC.
public struct KeyboardMic {
    public struct Result {
        public let gestures: [Gesture]
        public let intercept: Bool
    }

    private var recognizer: GestureRecognizer
    private var commandPressedAt: Double?
    private var commandUsed = false

    public init(settings: GestureSettings = GestureSettings()) {
        recognizer = GestureRecognizer(settings: settings)
    }

    /// Key codes identify physical keys, independently of the keyboard layout.
    /// Right Command is provisional until release: a later shortcut key must still cancel it.
    /// For a chord, release Command before releasing the right-Option handle.
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
        if isDown, commandPressedAt != nil { commandUsed = true }
        guard keyCode == 61, !isRepeat else {
            return Result(gestures: [], intercept: false)
        }
        // A chord must commit while its take is still recording, never after pttUp.
        if !isDown, commandPressedAt != nil, recognizer.handleDown { commandUsed = true }
        return Result(gestures: recognizer.handle(.handle, active: isDown, at: time),
                      intercept: false)
    }

    public mutating func tick(at time: Double) -> [Gesture] {
        recognizer.tick(at: time)
    }
}
