import Foundation
@preconcurrency import FXMicCore

/// Finds the session an agent app shows right now and the link that reopens it, using the app's
/// `SessionAdapter` (built-in for Claude and Codex desktop, extra ones in `config.json`).
/// Everything read here is undocumented app data, so each read tolerates missing or changed
/// content and returns nil; the channel then falls back to the app (One-Pager 004 §4.3).
enum SessionLocator {
    struct Session: Equatable {
        let id: String
        let title: String?
    }

    /// Adapters from `config.json`, kept up to date by the app delegate.
    nonisolated(unsafe) static var custom: [SessionAdapter] = []

    static func adapter(for bundleID: String) -> SessionAdapter? {
        SessionAdapter.adapter(for: bundleID, custom: custom)
    }

    /// Short name for the apps whose own name is misleading ("ChatGPT" for Codex).
    static func displayName(bundleID: String) -> String? { adapter(for: bundleID)?.name }

    static func url(bundleID: String, session: String) -> URL? { adapter(for: bundleID)?.url(for: session) }

    static func current(bundleID: String) -> Session? {
        guard let adapter = adapter(for: bundleID) else { return nil }
        // A log folder can hold several files (Codex writes one per process, and a git worker
        // writes to its own at every switch): the newest *event* decides, not the newest file.
        var best: (found: SessionAdapter.Found, when: Date)?
        for file in recentLogs(at: expand(adapter.logDirectory)) {
            guard let found = lastEvent(inFile: file.url, modified: file.modified, adapter: adapter) else { continue }
            let when = found.timestamp ?? file.modified
            if best == nil || when > best!.when { best = (found, when) }
        }
        guard case .focus(let id)? = best?.found.event else { return nil }
        return Session(id: id, title: title(bundleID: bundleID, session: id))
    }

    // MARK: Organizations

    /// Menu label of each organization, learned by switching; kept up to date by the app delegate.
    nonisolated(unsafe) static var organizationLabels: [String: String] = [:]

    nonisolated(unsafe) private static var organizationCache: [String: (size: UInt64, modified: Date, id: String?)] = [:]

    /// The organization the app has active right now, from its log (lowercased), nil when the app
    /// has none or the log says nothing. The log rotates, so the older files are read too.
    static func activeOrganization(bundleID: String) -> String? {
        guard let adapter = adapter(for: bundleID), adapter.organizationPattern != nil else { return nil }
        let main = expand(adapter.logDirectory)
        guard main.pathExtension == "log" else { return nil }
        let base = main.deletingPathExtension().path
        for file in [main] + (1...3).map({ URL(fileURLWithPath: "\(base)\($0).log") }) {
            if let id = lastOrganization(inFile: file, adapter: adapter) { return id }
        }
        return nil
    }

    private static func lastOrganization(inFile url: URL, adapter: SessionAdapter) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes?[.size] as? UInt64, let modified = attributes?[.modificationDate] as? Date else { return nil }
        if let hit = organizationCache[url.path], hit.size == size, hit.modified == modified { return hit.id }
        var found: String?
        for bytes: UInt64 in [400_000, 4_000_000, 16_000_000] {
            if let id = adapter.lastOrganization(in: tail(of: url, bytes: bytes)) {
                found = id
                break
            }
            if size <= bytes { break }
        }
        organizationCache[url.path] = (size, modified, found)
        return found
    }

    /// The app's log file and its current size, to read what it writes from now on.
    static func logMark(bundleID: String) -> (url: URL, offset: UInt64)? {
        guard let adapter = adapter(for: bundleID) else { return nil }
        let url = expand(adapter.logDirectory)
        guard url.pathExtension == "log",
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 else { return nil }
        return (url, size)
    }

    /// What the log got since `mark` (empty if it rotated or cannot be read).
    static func logText(since mark: (url: URL, offset: UInt64)) -> String {
        guard let handle = try? FileHandle(forReadingFrom: mark.url) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > mark.offset else { return "" }
        try? handle.seek(toOffset: mark.offset)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    /// Claude Code keeps each session under the organization it belongs to.
    static func organization(bundleID: String, session id: String) -> String? {
        guard bundleID == SessionAdapter.claudeDesktop.bundleID else { return nil }
        return claudeSessionFile(for: id)?.organization.lowercased()
    }

    // MARK: Log files

    private static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The log itself, or the few most recently written `.log` files of a folder.
    private static func recentLogs(at url: URL) -> [(url: URL, modified: Date)] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        func modified(_ file: URL) -> Date {
            (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        guard isDirectory.boolValue else { return [(url, modified(url))] }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let cutoff = Date().addingTimeInterval(-3 * 86_400)
        var files: [(url: URL, modified: Date)] = []
        for case let file as URL in walker where file.pathExtension == "log" {
            let date = modified(file)
            if date > cutoff { files.append((file, date)) }
        }
        return Array(files.sorted { $0.modified > $1.modified }.prefix(6))
    }

    private struct CacheEntry {
        let size: UInt64
        let modified: Date
        let found: SessionAdapter.Found?
    }

    nonisolated(unsafe) private static var cache: [String: CacheEntry] = [:]

    /// The newest focus/blur line of a log. Switches can be hours apart while the log keeps
    /// growing, so the search reads a larger tail until it finds one (at most 16 MB), and an
    /// unchanged file is not read again.
    private static func lastEvent(inFile url: URL, modified: Date, adapter: SessionAdapter) -> SessionAdapter.Found? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let key = url.path + "|" + adapter.focusPattern
        if let hit = cache[key], hit.size == size, hit.modified == modified { return hit.found }
        var found: SessionAdapter.Found?
        for bytes: UInt64 in [400_000, 4_000_000, 16_000_000] {
            if let event = adapter.lastEvent(in: tail(of: url, bytes: bytes)) {
                found = event
                break
            }
            if size <= bytes { break }
        }
        cache[key] = CacheEntry(size: size, modified: modified, found: found)
        return found
    }

    /// The last `bytes` of a file as text (a partial first line is harmless).
    private static func tail(of url: URL, bytes: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Titles

    /// The session's name, for the apps that store it where it can be read. Other apps show the
    /// window title instead (the channel name falls back to it).
    private static func title(bundleID: String, session: String) -> String? {
        switch bundleID {
        case SessionAdapter.claudeDesktop.bundleID: return claudeTitle(for: session)
        case SessionAdapter.codexDesktop.bundleID: return codexTitle(for: session)
        default: return nil
        }
    }

    private static func home(_ path: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
    }

    /// `claude-code-sessions/<account>/<organization>/<id>.json` holds the title.
    private static func claudeTitle(for id: String) -> String? {
        claudeSessionFile(for: id)?.json["title"] as? String
    }

    private static func claudeSessionFile(for id: String) -> (organization: String, json: [String: Any])? {
        let root = home("Library/Application Support/Claude/claude-code-sessions")
        let fm = FileManager.default
        for account in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let accountURL = root.appendingPathComponent(account)
            for organization in (try? fm.contentsOfDirectory(atPath: accountURL.path)) ?? [] {
                let file = accountURL.appendingPathComponent(organization).appendingPathComponent("\(id).json")
                guard let data = try? Data(contentsOf: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                return (organization, json)
            }
        }
        return nil
    }

    /// `~/.codex/session_index.jsonl`: one `{"id","thread_name"}` object per line.
    private static func codexTitle(for id: String) -> String? {
        let text = tail(of: home(".codex/session_index.jsonl"), bytes: 400_000)
        var title: String?
        for line in text.split(separator: "\n") where line.contains(id) {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["id"] as? String == id {
                title = json["thread_name"] as? String
            }
        }
        return title
    }
}
