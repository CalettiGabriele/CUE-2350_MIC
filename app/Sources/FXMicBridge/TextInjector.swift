import AppKit
import Carbon.HIToolbox
import FXMicCore
import os

/// Writes text where the cursor is and posts shortcuts (TDD §3.8).
@MainActor
enum TextInjector {
    enum Outcome: Equatable {
        case done
        case secureInput
        case notTrusted
        case failed
    }

    private static let log = Logger(subsystem: "com.fxmicbridge", category: "inject")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Accessibility permission is needed to post synthetic key events and use AX.
    @discardableResult
    nonisolated static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static func precheck() -> Outcome? {
        if IsSecureEventInputEnabled() { return .secureInput }
        guard isTrusted(prompt: false) else { return .notTrusted }
        return nil
    }

    // MARK: - Text

    static func insert(_ text: String, strategy: InjectionStrategy, restoreAfterMs: Double) -> Outcome {
        if let blocked = precheck() { return blocked }
        switch strategy {
        case .paste:
            paste(text, restoreAfter: restoreAfterMs / 1000)
        case .ax:
            if !setSelectedTextViaAX(text) {
                log.notice("AX insert not supported here, falling back to paste")
                paste(text, restoreAfter: restoreAfterMs / 1000)
            }
        case .type:
            type(text)
        }
        return .done
    }

    /// Saves the clipboard, pastes with ⌘V and restores the clipboard afterwards.
    private static func paste(_ text: String, restoreAfter: TimeInterval) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: transientType)   // clipboard managers ignore it
        let ourChange = pasteboard.changeCount
        post(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
            guard pasteboard.changeCount == ourChange else { return }   // user copied meanwhile
            restore(saved, to: pasteboard)
        }
        log.info("pasted \(text.count, privacy: .public) chars")
    }

    private static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(text.utf16)
        var index = 0
        while index < utf16.count {
            let chunk = Array(utf16[index..<min(index + 20, utf16.count)])
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                chunk.withUnsafeBufferPointer {
                    event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress)
                }
                event?.post(tap: .cghidEventTap)
            }
            index += 20
        }
        log.info("typed \(text.count, privacy: .public) chars")
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private static func setSelectedTextViaAX(_ text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    /// Reads the selected text of the focused app: AX first, then ⌘C with the clipboard restored.
    static func readSelection() async -> String? {
        guard precheck() == nil else { return nil }
        if let element = focusedElement() {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                return text
            }
        }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        post(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let text = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
        restore(saved, to: pasteboard)
        return (text?.isEmpty ?? true) ? nil : text
    }

    // MARK: - Shortcuts

    /// Posts each combo in order, e.g. ["cmd+a", "delete"]. Unknown combos are skipped.
    static func send(_ combos: [String]) -> Outcome {
        if let blocked = precheck() { return blocked }
        var sent = 0
        for string in combos {
            guard let combo = KeyCombo(string), let code = namedKeyCodes[combo.key] else {
                log.error("unknown key combo \(string, privacy: .public)")
                continue
            }
            var flags: CGEventFlags = []
            if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
            if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
            if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
            if combo.modifiers.contains(.control) { flags.insert(.maskControl) }
            post(CGKeyCode(code), flags: flags)
            sent += 1
        }
        log.notice("keys \(combos.joined(separator: " "), privacy: .public)")
        return sent > 0 ? .done : .failed
    }

    private static let namedKeyCodes: [String: Int] = [
        "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "escape": kVK_Escape, "esc": kVK_Escape, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
        "9": kVK_ANSI_9,
    ]

    // MARK: - Helpers

    private static func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
