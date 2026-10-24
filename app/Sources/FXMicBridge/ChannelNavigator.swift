import AppKit
import ApplicationServices
import os
@preconcurrency import FXMicCore

/// Binds windows to channels and brings them back to the front (One-Pager 004 §4.2).
/// Windows are told apart with Accessibility: `AXDocument` for documents, the title otherwise.
@MainActor
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
        // The organization decides where a Claude session or chat lives (see `bringToFront`).
        var organization: String?
        if let session {
            organization = SessionLocator.organization(bundleID: bundleID, session: session.id)
        } else if link != nil {
            organization = SessionLocator.activeOrganization(bundleID: bundleID)
        }
        var detail = session?.title ?? document.flatMap { URL(string: $0)?.lastPathComponent } ?? title ?? ""
        if let link, detail.isEmpty || detail == appName {
            detail = (link.contains("/project/") ? L.t("project") : L.t("chat")) + " " + String(link.suffix(8))
        }
        if detail.count > 28 { detail = String(detail.prefix(27)) + "…" }
        var name = detail.isEmpty || detail == appName ? appName : "\(appName) · \(detail)"
        if let organization, let label = SessionLocator.organizationLabels[organization] {
            name += " · " + (label.count > 18 ? String(label.prefix(17)) + "…" : label)
        }
        return Channel(name: name, bundleID: bundleID, document: document,
                       title: session == nil && link == nil ? title : nil,
                       session: session?.id, link: link, organization: organization)
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

    nonisolated(unsafe) private static var generation = 0

    /// Brings the channel's app and window to the front. Launches the app if it is not running.
    /// A channel of another organization first switches the app to it through its account menu,
    /// as fast as the app allows: no fixed waits, the link opens as soon as the window has
    /// reloaded. `learn` is told which menu label led to which organization; `status` is only
    /// used when the switch fails.
    static func bringToFront(_ channel: Channel, learn: @escaping (_ organization: String, _ label: String) -> Void = { _, _ in },
                             status: @escaping (String) -> Void = { _ in }) {
        generation += 1
        let mine = generation
        guard let target = channel.organization,
              SessionLocator.adapter(for: channel.bundleID)?.organizationPattern != nil,
              let current = SessionLocator.activeOrganization(bundleID: channel.bundleID), current != target,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: channel.bundleID).first else {
            open(channel)
            return
        }
        log.notice("organization \(current, privacy: .public) → \(target, privacy: .public) for \(channel.name, privacy: .public)")
        app.activate()
        // The curtain hides the menu, the reload and the page Claude lands on.
        curtain.show(over: app, title: channel.name)
        switchOrganization(app, to: target, from: current, learn: learn, confirming: {
            // Claude asks before closing terminals: that is for the user to see and answer.
            curtain.hide(animated: false)
        }) { done in
            // A newer tap on orange wins: it handles its own channel and its curtain.
            guard mine == generation else { return }
            if !done {
                curtain.hide(animated: false)
                status(L.t("Could not switch Claude organization"))
            }
            let mark = SessionLocator.logMark(bundleID: channel.bundleID)
            open(channel)
            guard done, curtain.isShown else { return }
            liftCurtain(when: channel, isShownIn: app, since: mark, generation: mine, until: Date().addingTimeInterval(2.5))
        }
    }

    private static let curtain = SwitchCurtain()

    /// Lifts the curtain once the channel's page is on screen: the chat's address in the web view,
    /// or the session reported as focused in the app's log. At most until `deadline`.
    private static func liftCurtain(when channel: Channel, isShownIn app: NSRunningApplication,
                                    since mark: (url: URL, offset: UInt64)?, generation mine: Int, until deadline: Date) {
        guard mine == generation else { return }
        var shown = Date() >= deadline
        if !shown, let link = channel.link, let path = link.range(of: "claude.ai").map({ String(link[$0.upperBound...]) }) {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.2)
            shown = webURL(in: element)?.contains(path) == true
        } else if !shown, let session = channel.session, let mark, let adapter = SessionLocator.adapter(for: channel.bundleID) {
            // Only a focus line written after the link was opened counts.
            shown = adapter.lastEvent(in: SessionLocator.logText(since: mark))?.event == .focus(session)
        }
        guard shown else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                liftCurtain(when: channel, isShownIn: app, since: mark, generation: mine, until: deadline)
            }
            return
        }
        // A moment for the page to paint before it shows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard mine == generation else { return }
            curtain.hide()
        }
    }

    /// Opens the channel's link (the deep link switches to the session or chat) and puts the window on top.
    private static func open(_ channel: Channel) {
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

    // MARK: Switching organization

    /// Opens the account menu, presses the entry for `target` as soon as it is drawn and watches the
    /// app's log until it names `target` and the window has reloaded. Entries do not say which
    /// organization they are, so a press that ends somewhere known is learned, and with two
    /// entries the other one is the organization we came from. If the app asks for confirmation
    /// (its sessions have terminals open), the dialog is left to the user and the wait goes on.
    /// Calls `done` on the main thread.
    private static func switchOrganization(_ app: NSRunningApplication, to target: String, from start: String,
                                           learn: @escaping (String, String) -> Void,
                                           confirming onConfirmation: @escaping () -> Void,
                                           done: @escaping (Bool) -> Void) {
        let bundleID = app.bundleIdentifier ?? ""
        guard let adapter = SessionLocator.adapter(for: bundleID), let mark = SessionLocator.logMark(bundleID: bundleID) else {
            return done(false)
        }
        var current = start
        var tried = Set<String>()
        let began = Date()
        var lastDialogCheck = Date.distantPast
        var confirmGrace = Date.distantPast

        func next() {
            guard tried.count < 4, AccountMenu.open(in: app) else { return done(false) }
            pick(until: Date().addingTimeInterval(0.8))
        }

        /// Polls until the menu is drawn, then presses the best entry.
        func pick(until deadline: Date) {
            let entries = AccountMenu.items(in: app)
            guard !entries.isEmpty else {
                guard Date() < deadline else { return done(false) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { pick(until: deadline) }
                return
            }
            let titles = entries.map(\.title)
            let order = OrganizationPicker.candidates(menu: titles, target: target, current: current,
                                                      learned: SessionLocator.organizationLabels)
            guard let label = order.first(where: { !tried.contains($0) }),
                  let entry = entries.first(where: { $0.title == label }) else {
                AccountMenu.close()
                return done(false)
            }
            tried.insert(label)
            log.notice("press account menu entry \(label, privacy: .public) after \(Int(Date().timeIntervalSince(began) * 1000), privacy: .public) ms")
            _ = AccountMenu.press(entry, useClick: false)
            watch(label: label, entry: entry, others: titles.filter { $0 != label }, clicked: false,
                  deadline: Date().addingTimeInterval(1.2), confirming: false)
        }

        /// Reads what the log got since the start until it names `target` and the window is loaded.
        func watch(label: String, entry: (element: AXUIElement, title: String), others: [String],
                   clicked: Bool, deadline: Date, confirming: Bool) {
            let progress = adapter.switchProgress(in: SessionLocator.logText(since: mark))
            if let now = progress.organization, now != current {
                learn(now, label)
                if now == target {
                    if others.count == 1, SessionLocator.organizationLabels[current] == nil { learn(current, others[0]) }
                    current = now
                    guard progress.ready || Date() >= deadline.addingTimeInterval(3) else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                            watch(label: label, entry: entry, others: others, clicked: clicked, deadline: deadline, confirming: confirming)
                        }
                        return
                    }
                    log.notice("organization switched and loaded after \(Int(Date().timeIntervalSince(began) * 1000), privacy: .public) ms")
                    return done(true)
                }
                current = now
                return next()   // a third organization: keep going from there
            }
            // The app's own confirmation: wait for the user's answer. The tree is large, so it is
            // looked at a few times a second; once it is gone, the switch has 2 s to show in the log
            // (otherwise it was cancelled).
            if confirming || Date().timeIntervalSince(lastDialogCheck) > 0.15 {
                lastDialogCheck = Date()
                if AccountMenu.confirmationShown(in: app) {
                    if !confirming { onConfirmation() }
                    confirmGrace = Date().addingTimeInterval(2)
                    guard Date() < began.addingTimeInterval(60) else { return done(false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        watch(label: label, entry: entry, others: others, clicked: clicked, deadline: deadline, confirming: true)
                    }
                    return
                }
                if confirming {
                    guard Date() < confirmGrace else { return done(false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        watch(label: label, entry: entry, others: others, clicked: clicked, deadline: deadline, confirming: true)
                    }
                    return
                }
            }
            guard Date() >= deadline else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    watch(label: label, entry: entry, others: others, clicked: clicked, deadline: deadline, confirming: false)
                }
                return
            }
            if !clicked, !AccountMenu.items(in: app).isEmpty {
                log.notice("account menu ignored the press; clicking \(label, privacy: .public)")
                _ = AccountMenu.press(entry, useClick: true)
                return watch(label: label, entry: entry, others: others, clicked: true,
                             deadline: Date().addingTimeInterval(1.2), confirming: false)
            }
            AccountMenu.close()
            // Pressing the active organization changes nothing: it is learned, then the next entry.
            if others.count == 1, SessionLocator.organizationLabels[current] == nil { learn(current, label) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { next() }
        }

        next()
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
