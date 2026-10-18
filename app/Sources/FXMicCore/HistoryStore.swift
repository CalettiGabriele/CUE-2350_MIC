import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var app: String
    public var profile: String
    public var mode: String
    public var raw: String
    public var processed: String?

    public var text: String { processed ?? raw }

    public init(id: UUID = UUID(), date: Date = Date(), app: String, profile: String, mode: String,
                raw: String, processed: String?) {
        self.id = id
        self.date = date
        self.app = app
        self.profile = profile
        self.mode = mode
        self.raw = raw
        self.processed = processed
    }
}

/// Dictation history in a local JSONL file, owner-only permissions (0600), with retention
/// (TDD §4). Newest entries first in memory.
public final class HistoryStore {
    public let fileURL: URL
    public private(set) var entries: [HistoryEntry] = []
    public var retentionDays: Int
    public var enabled: Bool

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(fileURL: URL, retentionDays: Int, enabled: Bool) {
        self.fileURL = fileURL
        self.retentionDays = retentionDays
        self.enabled = enabled
    }

    /// Reads the file, drops expired or unreadable lines and rewrites it if anything was dropped.
    public func load(now: Date = Date()) {
        guard enabled, let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        let lines = data.split(separator: UInt8(ascii: "\n"))
        let decoded = lines.compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0)) }
        // The file is append-only, oldest first: reverse it instead of sorting (equal dates keep order).
        entries = decoded.reversed().filter { !isExpired($0, now: now) }
        if entries.count != lines.count { rewrite() }
    }

    public func append(_ entry: HistoryEntry, now: Date = Date()) {
        guard enabled else {
            // Session-only: keep in memory so the menu still shows recent text.
            entries.insert(entry, at: 0)
            entries = Array(entries.prefix(20))
            return
        }
        entries.insert(entry, at: 0)
        entries.removeAll { isExpired($0, now: now) }
        guard retentionDays > 0, var line = try? encoder.encode(entry) else { return }
        line.append(UInt8(ascii: "\n"))
        if FileManager.default.fileExists(atPath: fileURL.path), let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            write(line)
        }
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        rewrite()
    }

    public func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func isExpired(_ entry: HistoryEntry, now: Date) -> Bool {
        guard enabled, retentionDays > 0 else { return false }
        return now.timeIntervalSince(entry.date) > Double(retentionDays) * 86_400
    }

    private func rewrite() {
        guard enabled, retentionDays > 0 else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        var data = Data()
        for entry in entries.reversed() {   // oldest first on disk
            if let line = try? encoder.encode(entry) {
                data.append(line)
                data.append(UInt8(ascii: "\n"))
            }
        }
        write(data)
    }

    private func write(_ data: Data) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: data,
                                       attributes: [.posixPermissions: 0o600])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
