import AppKit
import ApplicationServices
import os
@preconcurrency import FXMicCore

/// Binds windows to channels and brings them back to the front (One-Pager 004 §4.2).
/// Windows are told apart with Accessibility: `AXDocument` for documents, the title otherwise.
enum ChannelNavigator {
    private static let log = Logger(subsystem: "com.fxmicbridge", category: "channels")

    /// Describes the frontmost window of `app`, to be saved as a channel.
    static func capture(_ app: NSRunningApplication) -> Channel? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // This runs on the main thread: an app that hangs must not freeze ours.
        AXUIElementSetMessagingTimeout(element, 0.25)
        var document: String?
        var title: String?
        if let window = attribute(element, kAXFocusedWindowAttribute) {
            let window = window as! AXUIElement
            document = (attribute(window, "AXDocument") as? String).flatMap { $0.isEmpty ? nil : $0 }
            title = (attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        // Claude and Codex keep several sessions in one window: bind the one on screen.
        let session = SessionLocator.current(bundleID: bundleID)
        var detail = session?.title ?? document.flatMap { URL(string: $0)?.lastPathComponent } ?? title ?? ""
        if detail.count > 28 { detail = String(detail.prefix(27)) + "…" }
        let appName = SessionLocator.displayName(bundleID: bundleID) ?? app.localizedName ?? bundleID
        return Channel(name: detail.isEmpty || detail == appName ? appName : "\(appName) · \(detail)",
                       bundleID: bundleID, document: document, title: session == nil ? title : nil, session: session?.id)
    }

    /// True when talking would land in the channel's session already: no need to navigate again.
    static func isShowing(_ channel: Channel) -> Bool {
        guard let session = channel.session,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == channel.bundleID else { return false }
        return SessionLocator.current(bundleID: channel.bundleID)?.id == session
    }

    /// Brings the channel's app and window to the front. Launches the app if it is not running.
    static func bringToFront(_ channel: Channel) {
        // The deep link switches to the session; activating afterwards puts the window on top.
        if let session = channel.session {
            let link = SessionLocator.url(bundleID: channel.bundleID, session: session)
            log.notice("open \(channel.bundleID, privacy: .public) session=\(session, privacy: .public) link=\(link?.absoluteString ?? "none", privacy: .public)")
            if let link { NSWorkspace.shared.open(link) }
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: channel.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            guard let app else { return }
            // The window can only be raised once the app is active.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { raiseWindow(of: app, matching: channel) }
        }
    }

    private static func raiseWindow(of app: NSRunningApplication, matching channel: Channel) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { return }
        let match = windows.first { window in
            guard let document = channel.document else { return false }
            return (attribute(window, "AXDocument") as? String) == document
        } ?? windows.first { window in
            guard channel.document == nil, let title = channel.title else { return false }
            return (attribute(window, kAXTitleAttribute) as? String) == title
        }
        guard let match else { return }
        AXUIElementPerformAction(match, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
