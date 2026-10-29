public enum GestureSource: Sendable {
    case usb, jack, keyboard
}

/// Authorizes input before any recording or capture-boundary side effect.
public struct GestureRouter {
    public enum Effect: Equatable, Sendable {
        case startRecording(fromSample: Int?)
        case stopRecording(atSample: Int?)
        case perform(Gesture)
        case confirm(Bool)
    }

    private var owner: GestureSource?
    private var releasedBy: GestureSource?
    private var ownsClickPair = false

    public init() {}

    /// Returns true when the disconnected source owned a take that must be cancelled.
    public mutating func disconnect(_ source: GestureSource) -> Bool {
        if releasedBy == source { releasedBy = nil }
        guard owner == source else { return false }
        owner = nil
        ownsClickPair = false
        return true
    }

    public mutating func route(_ gesture: Gesture, from source: GestureSource,
                               captureSample: Int? = nil, awaitingConfirmation: Bool = false) -> Effect? {
        if awaitingConfirmation {
            // A pending confirmation blocks recording effects, not release bookkeeping.
            if gesture == .pttUp { _ = accept(gesture, from: source) }
            switch gesture {
            case .tap(.grey): return .confirm(true)
            case .shake, .longPress(.grey): return .confirm(false)
            default: return nil
            }
        }
        guard accept(gesture, from: source) else { return nil }
        switch gesture {
        case .pttDown: return .startRecording(fromSample: source == .jack ? captureSample : nil)
        case .pttUp: return .stopRecording(atSample: source == .jack ? captureSample : nil)
        default: return .perform(gesture)
        }
    }

    private mutating func accept(_ gesture: Gesture, from source: GestureSource) -> Bool {
        switch gesture {
        case .pttDown:
            guard owner == nil else { return false }
            ownsClickPair = releasedBy == source
            releasedBy = nil
            owner = source
            return true
        case .pttUp:
            releasedBy = owner == source ? source : nil
            guard owner == source else { return false }
            owner = nil
            return true
        case .handleDoubleClick:
            return releasedBy == source && ownsClickPair
        default:
            return true
        }
    }
}
