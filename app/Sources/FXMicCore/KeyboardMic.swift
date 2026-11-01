/// Keyboard input translated into the same gestures as the FX-MIC.
public struct KeyboardMic {
    public struct Result {
        public let gestures: [Gesture]
        public let intercept: Bool
    }

    private var recognizer: GestureRecognizer

    public init(settings: GestureSettings = GestureSettings()) {
        recognizer = GestureRecognizer(settings: settings)
    }

    /// Key codes identify physical keys, independently of the keyboard layout.
    public mutating func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool = false,
                                at time: Double) -> Result {
        guard keyCode == 61, !isRepeat else {
            return Result(gestures: [], intercept: false)
        }
        return Result(gestures: recognizer.handle(.handle, active: isDown, at: time),
                      intercept: false)
    }

    public mutating func tick(at time: Double) -> [Gesture] {
        recognizer.tick(at: time)
    }
}
