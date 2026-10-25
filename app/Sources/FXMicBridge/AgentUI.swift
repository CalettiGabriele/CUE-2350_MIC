import AppKit
import FXMicCore
import Foundation
import os

/// The interface tools on the real Mac (TDD voice command agent §3.3, phase 5): the front app's
/// controls, menus and windows through Accessibility, apps and links through NSWorkspace. The ids
/// handed to the model point into tables that live for one command.
final class LiveUI: MacUI, @unchecked Sendable {
    private let log = Logger(subsystem: "com.fxmicbridge", category: "agent-ui")
    // Only touched inside MainActor.run.
    private var elements: [String: AXUIElement] = [:]
    private var menus: [String: AXUIElement] = [:]
    private var windowTable: [String: AXUIElement] = [:]
    private var titles: [String: String] = [:]

    private static let roles: [String: String] = [
        "AXButton": "button", "AXLink": "link", "AXCheckBox": "checkbox", "AXRadioButton": "option",
        "AXPopUpButton": "popup", "AXMenuButton": "menu", "AXTextField": "field", "AXTextArea": "field",
        "AXComboBox": "field", "AXDisclosureTriangle": "disclosure", "AXTab": "tab", "AXSlider": "slider",
    ]

    // MARK: - Accessibility helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }

    @MainActor private static func frontApp() -> (AXUIElement, NSRunningApplication)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron and Chromium apps build their Accessibility tree only when asked to.
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return (element, app)
    }

    private static func name(of element: AXUIElement) -> String {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute] {
            if let text: String = attribute(element, key), !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // A button whose label is a child text (common in web views).
        for child in children(element).prefix(3) {
            if let text: String = attribute(child, kAXValueAttribute), !text.isEmpty { return text }
            if let text: String = attribute(child, kAXTitleAttribute), !text.isEmpty { return text }
        }
        return ""
    }

    // MARK: - Controls

    func uiElements() async -> [UIElementInfo]? {
        await MainActor.run {
            guard let (app, _) = Self.frontApp(),
                  let window: AXUIElement = Self.attribute(app, kAXFocusedWindowAttribute) else { return nil }
            elements = [:]
            titles = [:]
            var found: [UIElementInfo] = []
            var queue: [(AXUIElement, Int)] = [(window, 0)]
            var visited = 0
            while !queue.isEmpty, visited < 2500, found.count < 300 {
                let (element, depth) = queue.removeFirst()
                visited += 1
                let role: String = Self.attribute(element, kAXRoleAttribute) ?? ""
                if let kind = Self.roles[role], (Self.attribute(element, kAXEnabledAttribute) as Bool?) != false {
                    let title = String(Self.name(of: element).prefix(80))
                    if !title.isEmpty {
                        let id = "e\(found.count + 1)"
                        elements[id] = element
                        titles[id] = title
                        found.append(UIElementInfo(id: id, role: kind, title: title))
                    }
                }
                if depth < 30 { queue += Self.children(element).map { ($0, depth + 1) } }
            }
            log.notice("read_ui: \(found.count, privacy: .public) controls, \(visited, privacy: .public) nodes")
            return found
        }
    }

    func press(_ id: String) async -> ToolResult {
        let outcome: ToolResult = await MainActor.run {
            guard let element = elements[id] else { return .failed("unknown element") }
            let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
            return error == .success ? .ok("pressed «\(titles[id] ?? id)»") : .failed("the control did not respond (\(error.rawValue))")
        }
        return await withFrontWindow(outcome)
    }

    func setValue(_ id: String, text: String) async -> ToolResult {
        await MainActor.run {
            guard let element = elements[id] else { return .failed("unknown element") }
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
            return error == .success ? .ok("text set in «\(titles[id] ?? id)»") : .failed("this field cannot be set (\(error.rawValue))")
        }
    }

    /// After an action, say which window is in front: the model sees whether something opened.
    private func withFrontWindow(_ result: ToolResult) async -> ToolResult {
        guard result.ok else { return result }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let title = await MainActor.run { () -> String? in
            guard let (app, running) = Self.frontApp(),
                  let window: AXUIElement = Self.attribute(app, kAXFocusedWindowAttribute) else { return nil }
            let name: String = Self.attribute(window, kAXTitleAttribute) ?? ""
            return "\(running.localizedName ?? "?") · «\(name)»"
        }
        return .ok(result.content + (title.map { "; front window now: \($0)" } ?? ""))
    }

    // MARK: - Menus

    func menuItems() async -> [String]? {
        await MainActor.run {
            guard let (app, _) = Self.frontApp(), let bar: AXUIElement = Self.attribute(app, kAXMenuBarAttribute) else { return nil }
            menus = [:]
            var paths: [String] = []
            func walk(_ menu: AXUIElement, prefix: String, depth: Int) {
                for item in Self.children(menu) {
                    let title: String = Self.attribute(item, kAXTitleAttribute) ?? ""
                    guard !title.isEmpty, (Self.attribute(item, kAXEnabledAttribute) as Bool?) != false else { continue }
                    let path = prefix + " › " + title
                    if let submenu = Self.children(item).first, depth < 2 {
                        walk(submenu, prefix: path, depth: depth + 1)
                    } else {
                        menus[path] = item
                        paths.append(path)
                    }
                }
            }
            // The first item is the Apple menu: system commands, not the app's.
            for top in Self.children(bar).dropFirst() {
                let title: String = Self.attribute(top, kAXTitleAttribute) ?? ""
                guard !title.isEmpty, let menu = Self.children(top).first else { continue }
                walk(menu, prefix: title, depth: 0)
            }
            return paths
        }
    }

    func chooseMenuItem(_ path: String) async -> ToolResult {
        let outcome: ToolResult = await MainActor.run {
            guard let item = menus[path] else { return .failed("unknown menu item") }
            let error = AXUIElementPerformAction(item, kAXPressAction as CFString)
            return error == .success ? .ok("chose \(path)") : .failed("the menu item did not respond (\(error.rawValue))")
        }
        return await withFrontWindow(outcome)
    }

    // MARK: - Windows and apps

    func windows() async -> [WindowInfo] {
        await MainActor.run {
            guard let (app, _) = Self.frontApp() else { return [] }
            var list: [AXUIElement] = Self.attribute(app, kAXWindowsAttribute) ?? []
            if let front: AXUIElement = Self.attribute(app, kAXFocusedWindowAttribute),
               let index = list.firstIndex(where: { CFEqual($0, front) }) {
                list.insert(list.remove(at: index), at: 0)
            }
            windowTable = [:]
            return list.enumerated().map { index, window in
                let id = "w\(index + 1)"
                windowTable[id] = window
                let title: String = Self.attribute(window, kAXTitleAttribute) ?? ""
                return WindowInfo(id: id, title: title.isEmpty ? "(untitled)" : title)
            }
        }
    }

    func focusWindow(_ id: String) async -> ToolResult {
        await MainActor.run {
            guard let window = windowTable[id] else { return .failed("unknown window") }
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            NSWorkspace.shared.frontmostApplication?.activate()
            let title: String = Self.attribute(window, kAXTitleAttribute) ?? id
            return .ok("«\(title)» is in front")
        }
    }

    func closeWindow(_ id: String) async -> ToolResult {
        await MainActor.run {
            guard let window = windowTable[id] else { return .failed("unknown window") }
            guard let button: AXUIElement = Self.attribute(window, kAXCloseButtonAttribute),
                  AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                return .failed("this window has no close button")
            }
            return .ok("closed")
        }
    }

    func openApp(_ name: String) async -> ToolResult {
        guard let url = await MainActor.run(body: { Self.findApp(name) }) else {
            return .failed("no app called \(name) in Applications")
        }
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .ok("\(app.localizedName ?? name) is open")
        } catch {
            return .failed("could not open \(name): \(error.localizedDescription)")
        }
    }

    /// An app by its file name, bundle name or localized name ("Note" is Notes in Italian).
    @MainActor static func findApp(_ name: String) -> URL? {
        let wanted = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: ".app", with: "").trimmingCharacters(in: .whitespaces)
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        var candidates: [URL] = []
        for folder in folders {
            let urls = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
            candidates += urls.filter { $0.pathExtension == "app" }
        }
        func key(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacingOccurrences(of: ".app", with: "")
        }
        let names: (URL) -> [String] = { url in
            var all = [url.deletingPathExtension().lastPathComponent, fm.displayName(atPath: url.path)]
            if let info = Bundle(url: url)?.localizedInfoDictionary ?? Bundle(url: url)?.infoDictionary {
                all += [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String].compactMap { $0 }
            }
            return all.map(key)
        }
        return candidates.first { names($0).contains(wanted) }
            ?? candidates.first { names($0).contains { $0.hasPrefix(wanted) } }
    }

    func openURL(_ url: URL) async -> ToolResult {
        await MainActor.run { NSWorkspace.shared.open(url) } ? .ok("opened \(url.absoluteString)") : .failed("could not open it")
    }
}
