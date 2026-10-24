import AppKit
import ApplicationServices

/// Covers an app's window while orange switches it to another organization, so the account menu,
/// the reload and the page Claude lands on stay out of sight: one fade instead of four page
/// changes. A plain panel in the app's background colour, not a picture of the window (that would
/// need the Screen Recording permission). It never takes the focus or the clicks.
@MainActor
final class SwitchCurtain {
    private var panel: NSPanel?
    private var label: NSTextField?

    /// Claude's page background, light and dark; its theme setting decides, "system" follows macOS.
    private static func background(for bundleID: String) -> NSColor {
        let light = NSColor(srgbRed: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255, alpha: 1)
        let dark = NSColor(srgbRed: 0x26 / 255, green: 0x26 / 255, blue: 0x24 / 255, alpha: 1)
        switch claudeTheme() {
        case "light": return light
        case "dark": return dark
        default: return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func claudeTheme() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["userThemeMode"] as? String
    }

    /// The frame of the app's main window in Cocoa coordinates, nil if it cannot be read.
    static func windowFrame(of app: NSRunningApplication) -> NSRect? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
            var value: AnyObject?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        guard let window = (attribute(element, kAXMainWindowAttribute) ?? attribute(element, kAXFocusedWindowAttribute)),
              let position = attribute(window as! AXUIElement, kAXPositionAttribute),
              let size = attribute(window as! AXUIElement, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        // Accessibility measures from the top of the main screen, Cocoa from its bottom.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: point.x, y: top - point.y - extent.height, width: extent.width, height: extent.height)
    }

    var isShown: Bool { panel?.isVisible == true }

    /// Covers the app's window at once (no fade in: the menu must not be seen).
    func show(over app: NSRunningApplication, title: String) {
        guard let frame = Self.windowFrame(of: app), let bundleID = app.bundleIdentifier else { return }
        let panel = self.panel ?? makePanel()
        let background = Self.background(for: bundleID)
        panel.contentView?.layer?.backgroundColor = background.cgColor
        label?.stringValue = title
        label?.textColor = background.brightnessComponent < 0.5
            ? NSColor(white: 1, alpha: 0.45) : NSColor(white: 0, alpha: 0.4)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Fades the curtain out (or removes it at once).
    func hide(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let content = NSView()
        content.wantsLayer = true
        // macOS window corners; the panel sits exactly on the window.
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: 13, weight: .medium)
        text.alignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(text)
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            text.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48),
        ])
        panel.contentView = content
        self.panel = panel
        self.label = text
        return panel
    }
}
