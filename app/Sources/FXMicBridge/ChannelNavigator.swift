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
        let appName = SessionLocator.displayName(bundleID: bundleID) ?? app.localizedName ?? bundleID
        // Claude and Codex keep several sessions in one window: bind the one on screen.
        let session = SessionLocator.current(bundleID: bundleID)
        // Outside a session (a Claude chat) the page is told by the URL of the web view.
        var link: String?
        if session == nil, let adapter = SessionLocator.adapter(for: bundleID), adapter.webPattern != nil,
           let url = webURL(in: element) {
            link = adapter.webLink(forURL: url)
        }
        var detail = session?.title ?? document.flatMap { URL(string: $0)?.lastPathComponent } ?? title ?? ""
        if let link, detail.isEmpty || detail == appName {
            detail = (link.contains("/project/") ? L.t("project") : L.t("chat")) + " " + String(link.suffix(8))
        }
        if detail.count > 28 { detail = String(detail.prefix(27)) + "…" }
        return Channel(name: detail.isEmpty || detail == appName ? appName : "\(appName) · \(detail)",
                       bundleID: bundleID, document: document, title: session == nil && link == nil ? title : nil,
                       session: session?.id, link: link)
    }

    /// The URL of the web view that has the focus: the focused element's ancestors up to the web
    /// area, or else a short search under the focused window. Chromium and Electron apps only.
    static func webURL(in app: AXUIElement) -> String? {
        func urlString(_ element: AXUIElement) -> String? {
            let value = attribute(element, "AXURL")
            return (value as? URL)?.absoluteString ?? (value as? String)
        }
        func isWebArea(_ element: AXUIElement) -> Bool { (attribute(element, kAXRoleAttribute) as? String) == "AXWebArea" }
        if let focused = attribute(app, kAXFocusedUIElementAttribute) {
            var current: AnyObject? = focused
            for _ in 0..<60 {
                guard let element = current else { break }
                let ax = element as! AXUIElement
                if isWebArea(ax), let url = urlString(ax) { return url }
                current = attribute(ax, kAXParentAttribute)
            }
        }
        guard let window = attribute(app, kAXFocusedWindowAttribute) else { return nil }
        var queue: [(AXUIElement, Int)] = [(window as! AXUIElement, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 300 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if isWebArea(element), let url = urlString(element) { return url }
            guard depth < 7, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return nil
    }

    /// For the log when a bind finds no link: what the web view says.
    static func debugWebURL(of app: NSRunningApplication) -> String {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        return webURL(in: element) ?? "none"
    }

    /// Brings the channel's app and window to the front. Launches the app if it is not running.
    static func bringToFront(_ channel: Channel) {
        // The deep link switches to the session or chat; activating afterwards puts the window on top.
        if let link = channel.link, let adapter = SessionLocator.adapter(for: channel.bundleID),
           adapter.accepts(webLink: link), let url = URL(string: link) {
            log.notice("open \(channel.bundleID, privacy: .public) link=\(link, privacy: .public)")
            NSWorkspace.shared.open(url)
        } else if let session = channel.session {
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
