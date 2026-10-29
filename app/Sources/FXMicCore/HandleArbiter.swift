public enum GestureSource: Sendable {
    case usb, jack, keyboard
}

/// A handle release can only end the hold started by the same source.
public struct HandleArbiter {
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

    public mutating func accept(_ gesture: Gesture, from source: GestureSource) -> Bool {
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
