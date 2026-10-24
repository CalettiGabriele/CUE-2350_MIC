import AppKit
import ApplicationServices

/// The account menu at the bottom of Claude desktop's sidebar, where the organization is chosen.
/// Found without any text: the sidebar's pop-up button that has a title (the account name) and sits
/// lowest; its menu lists the organizations in the first application group, before the separator.
/// All of it is Accessibility on a web view, so every read tolerates a changed layout and fails
/// with nil/false (the caller then opens the link in whatever organization is active).
@MainActor
enum AccountMenu {
    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        (attribute(element, name) as? String) ?? ""
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    private static func walk(_ element: AXUIElement, depth: Int = 0, budget: UnsafeMutablePointer<Int>,
                             _ visit: (AXUIElement, Int) -> Bool) {
        guard depth < 40, budget.pointee > 0 else { return }
        budget.pointee -= 1
        guard visit(element, depth) else { return }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            walk(child, depth: depth + 1, budget: budget, visit)
        }
    }

    private static func appElement(_ app: NSRunningApplication) -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return element
    }

    private static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        (attribute(appElement(app), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// The pop-up button that opens the account menu.
    static func button(in app: NSRunningApplication) -> AXUIElement? {
        var best: (element: AXUIElement, y: CGFloat)?
        var budget = 6000
        for window in windows(of: app) {
            walk(window, budget: &budget) { element, _ in
                if string(element, kAXRoleAttribute) == "AXPopUpButton", !string(element, kAXTitleAttribute).isEmpty,
                   let rect = frame(element), rect.minX - (frame(window)?.minX ?? 0) < 320,
                   best == nil || rect.minY > best!.y {
                    best = (element, rect.minY)
                }
                return true
            }
        }
        return best?.element
    }

    /// The organization entries of the open menu: elements and titles, in menu order.
    static func items(in app: NSRunningApplication) -> [(element: AXUIElement, title: String)] {
        var result: [(AXUIElement, String)] = []
        var budget = 6000
        for window in windows(of: app) {
            walk(window, budget: &budget) { element, _ in
                guard result.isEmpty, string(element, kAXRoleAttribute) == "AXGroup",
                      string(element, kAXSubroleAttribute) == "AXApplicationGroup" else { return true }
                var found: [(AXUIElement, String)] = []
                var inner = 40
                walk(element, budget: &inner) { child, _ in
                    if string(child, kAXRoleAttribute) == "AXMenuItem", !string(child, kAXTitleAttribute).isEmpty {
                        found.append((child, string(child, kAXTitleAttribute)))
                    }
                    return true
                }
                if !found.isEmpty { result = found }
                return false
            }
        }
        return result
    }

    /// Claude's own confirmation ("Switch to …? The terminals in your sessions will be closed"), shown
    /// when sessions of the current organization have terminals open. It is the user's call.
    static func confirmationShown(in app: NSRunningApplication) -> Bool {
        var shown = false
        var budget = 6000
        for window in windows(of: app) where !shown {
            walk(window, budget: &budget) { element, _ in
                if string(element, kAXSubroleAttribute) == "AXApplicationAlertDialog" { shown = true }
                return !shown
            }
        }
        return shown
    }

    static func open(in app: NSRunningApplication) -> Bool {
        guard let button = button(in: app) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Presses the entry: through Accessibility first, then with a real click if the web view
    /// ignores the action.
    static func press(_ entry: (element: AXUIElement, title: String), useClick: Bool) -> Bool {
        if !useClick { return AXUIElementPerformAction(entry.element, kAXPressAction as CFString) == .success }
        guard let rect = frame(entry.element) else { return false }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        return true
    }

    static func close() { _ = TextInjector.send(["escape"]) }
}
