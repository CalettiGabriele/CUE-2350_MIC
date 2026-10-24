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

    /// Writes the window tree of a running app (role, subrole, title, description, value, frame) to
    /// the log. Developer tool for working out how to drive an app's own menus, such as Claude's
    /// organization picker; started with `--ax-dump <bundle id>` at launch.
    @discardableResult
    static func dumpTree(bundleID: String, maxNodes: Int = 4000) -> Int {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            append("== \(Date()) \(bundleID): not running\n")
            return 0
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var lines = ["== \(Date()) tree of \(bundleID)"]
        var count = 0
        func visit(_ element: AXUIElement, _ depth: Int) {
            guard count < maxNodes, depth < 60 else { return }
            count += 1
            var parts = [string(element, kAXRoleAttribute)]
            for (label, name) in [("sub", kAXSubroleAttribute), ("title", kAXTitleAttribute),
                                  ("desc", kAXDescriptionAttribute), ("help", kAXHelpAttribute),
                                  ("id", "AXIdentifier"), ("dom", "AXDOMIdentifier")] {
                let value = string(element, name)
                if value != "-" && !value.isEmpty { parts.append("\(label)=\(value.prefix(80))") }
            }
            if parts[0] == "AXWebArea", let url = attribute(element, "AXURL") {
                parts.append("url=\((url as? URL)?.absoluteString ?? String(describing: url))")
            }
            if let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty {
                parts.append("value=\(value.prefix(60).replacingOccurrences(of: "\n", with: " "))")
            }
            if let frame = frame(element) { parts.append("@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))") }
            if parts[0] == "AXMenuItem" {
                var names: CFArray?
                AXUIElementCopyAttributeNames(element, &names)
                for name in (names as? [String]) ?? [] where ![kAXChildrenAttribute, kAXParentAttribute, kAXWindowAttribute, kAXTopLevelUIElementAttribute].contains(name) {
                    if let value = attribute(element, name), !(value is AXUIElement), !(value is [AXUIElement]) {
                        parts.append("\(name)=\(String(describing: value).prefix(40))")
                    }
                }
            }
            lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { visit(child, depth + 1) }
        }
        visit(root, 0)
        append(lines.joined(separator: "\n") + "\n")
        return count
    }

    /// Finds the first element whose title or description starts with `label` and presses it.
    static func press(bundleID: String, label: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        var found: AXUIElement?
        func visit(_ element: AXUIElement, _ depth: Int) {
            guard found == nil, depth < 60 else { return }
            if string(element, kAXTitleAttribute).hasPrefix(label) || string(element, kAXDescriptionAttribute).hasPrefix(label) {
                found = element
                return
            }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { visit(child, depth + 1) }
        }
        visit(AXUIElementCreateApplication(app.processIdentifier), 0)
        guard let element = found else {
            append("== \(Date()) press \(label): not found\n")
            return false
        }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        append("== \(Date()) press \(label): \(result.rawValue)\n")
        return result == .success
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
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
