import AppKit
import ApplicationServices

/// One-Pager 004 §10.1: what the frontmost app exposes through Accessibility (focused element,
/// editable text, window title and document). Developer tool, reached with ⌥ in the menu; results
/// are appended to ax-diagnostics.log next to config.json.
enum AXDiagnostics {
    static var logURL: URL { ConfigStore.directory.appendingPathComponent("ax-diagnostics.log") }

    /// Probes the frontmost app and returns a one-line summary for the HUD.
    @discardableResult
    static func probeFrontmost() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "No frontmost app" }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium/Electron apps build their tree only when asked.
        let manual = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var lines = ["== \(Date()) \(app.bundleIdentifier ?? "?") (\(app.localizedName ?? "?")) manualAX=\(manual.rawValue)"]

        var editable = false
        if let focusedWindow = attribute(element, kAXFocusedWindowAttribute) {
            let window = focusedWindow as! AXUIElement
            lines.append("window title=\(string(window, kAXTitleAttribute)) document=\(string(window, "AXDocument"))")
        } else {
            lines.append("window: none")
        }
        if let focused = attribute(element, kAXFocusedUIElementAttribute) {
            let field = focused as! AXUIElement
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable)
            let hasRange = attribute(field, kAXSelectedTextRangeAttribute) != nil
            editable = settable.boolValue || hasRange
            let value = string(field, kAXValueAttribute)
            lines.append("focused role=\(string(field, kAXRoleAttribute)) subrole=\(string(field, kAXSubroleAttribute)) "
                + "valueSettable=\(settable.boolValue) selectedRange=\(hasRange) "
                + "selectedText=\(string(field, kAXSelectedTextAttribute).prefix(40)) valueLength=\(value.count)")
        } else {
            lines.append("focused: none")
        }
        append(lines.joined(separator: "\n") + "\n")
        return "\(app.localizedName ?? "?"): " + (editable ? "editable text" : "no editable text")
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        (attribute(element, name) as? String) ?? "-"
    }

    private static func append(_ text: String) {
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
