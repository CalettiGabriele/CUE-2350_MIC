import AppKit
import FXMicCore
import Foundation

/// Reads what the agent needs to know before its first call (TDD voice command agent §2, step 3):
/// the front window's title and the focused field's text around the cursor, through Accessibility.
@MainActor
enum ScreenSnapshot {
    /// Characters kept on each side of the cursor.
    nonisolated static let around = 1000

    static func windowTitle(pid: pid_t?) -> String? {
        guard let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String, !text.isEmpty else { return nil }
        return text
    }

    /// The focused text element, unless it is a password field.
    static func focusedField() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
        if (role as? String) == (kAXSecureTextFieldSubrole as String) { return nil }
        return element
    }

    /// The field's whole text and the selected range (UTF-16), nil when the app exposes no text.
    static func field() -> (element: AXUIElement, text: String, selection: CFRange)? {
        guard let element = focusedField() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        var selection = CFRange(location: text.utf16.count, length: 0)
        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
           let range, CFGetTypeID(range) == AXValueGetTypeID() {
            AXValueGetValue(range as! AXValue, .cfRange, &selection)
        }
        return (element, text, selection)
    }

    /// The focused field's text, cut to `around` characters on each side of the cursor. nil when the
    /// app exposes no text (some Electron views) or the field is a password.
    static func fieldText(around: Int = around) -> String? {
        guard let field = field(), !field.text.isEmpty else { return nil }
        let utf16 = Array(field.text.utf16)
        let location = min(max(0, field.selection.location), utf16.count)
        let lower = max(0, location - around)
        let upper = min(utf16.count, location + around)
        return String(decoding: utf16[lower..<upper], as: UTF16.self)
    }

    /// The selected text, through Accessibility only (no ⌘C: it runs between agent steps).
    static func selectedText() -> String? {
        guard let element = focusedField() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// Selects the `occurrence`-th match (1 = first, -1 = last), ignoring case and accents.
    static func select(_ needle: String, occurrence: Int) -> Result<String, AgentMacError> {
        guard let field = field() else { return .failure(.noText) }
        let haystack = field.text as NSString
        var ranges: [NSRange] = []
        var search = NSRange(location: 0, length: haystack.length)
        while search.length > 0 {
            let found = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let next = found.location + max(1, found.length)
            search = NSRange(location: next, length: haystack.length - next)
        }
        guard !ranges.isEmpty else { return .failure(.notFound(String(field.text.prefix(300)))) }
        let index = occurrence < 0 ? ranges.count + occurrence : occurrence - 1
        guard ranges.indices.contains(index) else { return .failure(.occurrence(ranges.count)) }
        var cf = CFRange(location: ranges[index].location, length: ranges[index].length)
        guard let value = AXValueCreate(.cfRange, &cf),
              AXUIElementSetAttributeValue(field.element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            return .failure(.cannotSelect)
        }
        return .success(haystack.substring(with: ranges[index]))
    }
}

enum AgentMacError: Error {
    case noText, notFound(String), occurrence(Int), cannotSelect

    var message: String {
        switch self {
        case .noText: return "this app does not expose the field's text"
        case .notFound(let start): return "text not found; the field starts with: \"\(start)\""
        case .occurrence(let count): return "it appears only \(count) time(s)"
        case .cannotSelect: return "this app does not let me select text"
        }
    }
}

/// The built-in tools' actions on the real Mac: keystrokes and paste through `TextInjector`,
/// channels, skills and intents through the app (the same paths as the one-call command).
final class LiveMac: MacActions, @unchecked Sendable {
    /// Runs the steps that need the app; nil = not available (Settings test).
    private let handler: (@MainActor (CommandStep) -> TextInjector.Outcome)?
    private let strategy: InjectionStrategy
    private let restoreClipboardMs: Double
    /// Set when something was written or pressed, for grey double tap (undo).
    private(set) var changedSomething = false

    init(handler: (@MainActor (CommandStep) -> TextInjector.Outcome)?, strategy: InjectionStrategy, restoreClipboardMs: Double) {
        self.handler = handler
        self.strategy = strategy
        self.restoreClipboardMs = restoreClipboardMs
    }

    private func result(_ outcome: TextInjector.Outcome, _ done: String) -> ToolResult {
        switch outcome {
        case .done:
            changedSomething = true
            return .ok(done)
        case .secureInput: return .failed("the field is protected (a password field): nothing was sent")
        case .notTrusted: return .failed("the app has no Accessibility permission: nothing was sent")
        case .failed: return .failed("the action did not work")
        }
    }

    func typeText(_ text: String) async -> ToolResult {
        // Typed, not pasted: several pastes in a row would race on the clipboard.
        let outcome = await MainActor.run { TextInjector.insert(text, strategy: .type, restoreAfterMs: 0) }
        return result(outcome, "typed")
    }

    func pressKeys(_ keys: [String]) async -> ToolResult {
        let outcome = await MainActor.run { TextInjector.send(keys) }
        return result(outcome, "pressed " + keys.joined(separator: " "))
    }

    func replaceSelection(_ text: String) async -> ToolResult {
        let outcome = await MainActor.run {
            text.isEmpty ? TextInjector.send(["delete"])
                : TextInjector.insert(text, strategy: strategy, restoreAfterMs: restoreClipboardMs)
        }
        // Let the paste land before the next key press.
        try? await Task.sleep(nanoseconds: 120_000_000)
        return result(outcome, "selection replaced")
    }

    private func app(_ step: CommandStep, done: String, settle: UInt64) async -> ToolResult {
        guard let handler else { return .failed("not available here") }
        let outcome = await MainActor.run { handler(step) }
        // A channel or a skill brings another window forward: give it time before typing there.
        if outcome == .done { try? await Task.sleep(nanoseconds: settle) }
        return outcome == .done ? .ok(done) : .failed("could not do it")
    }

    func switchChannel(_ name: String) async -> ToolResult {
        await app(.switchChannel(name), done: "now on channel \(name)", settle: 600_000_000)
    }

    func runSkill(_ name: String) async -> ToolResult {
        await app(.runSlot(name), done: "ran \(name)", settle: 200_000_000)
    }

    func runIntent(_ name: String) async -> ToolResult {
        await app(.intent(name), done: "done: \(name)", settle: 200_000_000)
    }

    func readFocusedText() async -> ToolResult {
        await MainActor.run {
            guard let field = ScreenSnapshot.field() else { return .failed(AgentMacError.noText.message) }
            let text = field.text.count > 4000 ? String(field.text.prefix(4000)) + "…" : field.text
            let selected = ScreenSnapshot.selectedText().map { "\nselected: \"\($0.prefix(500))\"" } ?? "\nselected: (none)"
            return .ok("field text:\n\(text)" + selected)
        }
    }

    func selectText(_ text: String, occurrence: Int) async -> ToolResult {
        await MainActor.run {
            switch ScreenSnapshot.select(text, occurrence: occurrence) {
            case .success(let selected): return .ok("selected \"\(selected)\"")
            case .failure(let error): return .failed(error.message)
            }
        }
    }

    func currentSelection() async -> String? {
        // Let the app apply the keys before asking.
        try? await Task.sleep(nanoseconds: 60_000_000)
        return await MainActor.run { ScreenSnapshot.selectedText() }
    }
}
