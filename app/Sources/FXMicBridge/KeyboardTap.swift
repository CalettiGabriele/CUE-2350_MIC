import AppKit
import ApplicationServices

/// An active event tap for the keyboard mic. Unlike the passive monitors it can consume an event,
/// which the right ⌘ + arrow combinations need so that they never reach the app in front, and
/// right ⌥ needs so that no other app reacts to it (a double tap of it opens Claude, for one).
/// It sits at the HID level, ahead of the other apps' taps, and falls back to the session level.
/// It relies on the Accessibility grant the app already holds; without it `init` fails and the
/// caller falls back to the monitors (right ⌥ and the voice command keep working, the arrows
/// do not, and other apps still see right ⌥).
@MainActor
final class KeyboardTap {
    /// A key event: key code, down or up, auto-repeat. Returns true to consume it.
    typealias Handler = (_ keyCode: UInt16, _ isDown: Bool, _ isRepeat: Bool) -> Bool

    private let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    /// Device-dependent modifier flags: they tell the left and right keys apart even when the
    /// other side is held.
    private static let modifierMasks: [UInt16: UInt64] = [
        54: 0x10, 55: 0x08,        // right / left Command
        56: 0x02, 60: 0x04,        // left / right Shift
        58: 0x20, 61: 0x40,        // left / right Option
        59: 0x01, 62: 0x2000,      // left / right Control
        63: CGEventFlags.maskSecondaryFn.rawValue,
    ]

    init?(handler: @escaping Handler) {
        self.handler = handler
        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyboardTap>.fromOpaque(info).takeUnretainedValue()
            let consume = MainActor.assumeIsolated { tap.consumes(type: type, event: event) }
            return consume ? nil : Unmanaged.passUnretained(event)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = [CGEventTapLocation.cghidEventTap, .cgSessionEventTap].lazy.compactMap({
            CGEvent.tapCreate(tap: $0, place: .headInsertEventTap, options: .defaultTap,
                              eventsOfInterest: mask, callback: callback, userInfo: userInfo)
        }).first else { return nil }
        self.port = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }

    private func consumes(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off when it is slow or after a re-sign: switch it back on.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .flagsChanged:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            guard let mask = Self.modifierMasks[keyCode] else {
                // Caps Lock reports its latched state: toggling it either way is key activity.
                return handler(keyCode, true, false)
            }
            return handler(keyCode, event.flags.rawValue & mask != 0, false)
        case .keyDown, .keyUp:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return handler(keyCode, type == .keyDown, isRepeat)
        default:
            return false
        }
    }
}
