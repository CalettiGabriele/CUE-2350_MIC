import Foundation
import Testing
@testable import FXMicCore

@Suite struct HistoryStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fxmic-history-\(UUID().uuidString).jsonl")
    }

    private func entry(_ text: String, daysAgo: Double = 0, now: Date) -> HistoryEntry {
        HistoryEntry(date: now.addingTimeInterval(-daysAgo * 86_400), app: "TextEdit", profile: "Generale",
                     mode: "Raw", raw: text, processed: nil)
    }

    @Test func appendPersistsWithOwnerOnlyPermissions() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let store = HistoryStore(fileURL: url, retentionDays: 7, enabled: true)
        store.append(entry("uno", now: now), now: now)
        store.append(entry("due", now: now), now: now)

        let reloaded = HistoryStore(fileURL: url, retentionDays: 7, enabled: true)
        reloaded.load(now: now)
        #expect(reloaded.entries.map(\.raw) == ["due", "uno"])
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func expiredEntriesAreDroppedOnLoad() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let store = HistoryStore(fileURL: url, retentionDays: 30, enabled: true)
        store.append(entry("vecchia", daysAgo: 10, now: now), now: now)
        store.append(entry("nuova", now: now), now: now)

        let reloaded = HistoryStore(fileURL: url, retentionDays: 7, enabled: true)
        reloaded.load(now: now)
        #expect(reloaded.entries.map(\.raw) == ["nuova"])
    }

    @Test func deleteAndClear() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let store = HistoryStore(fileURL: url, retentionDays: 7, enabled: true)
        let a = entry("a", now: now)
        store.append(a, now: now)
        store.append(entry("b", now: now), now: now)
        store.delete(id: a.id)
        let reloaded = HistoryStore(fileURL: url, retentionDays: 7, enabled: true)
        reloaded.load(now: now)
        #expect(reloaded.entries.map(\.raw) == ["b"])
        reloaded.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func disabledHistoryKeepsSessionOnly() {
        let url = tempURL()
        let now = Date()
        let store = HistoryStore(fileURL: url, retentionDays: 7, enabled: false)
        store.append(entry("solo in memoria", now: now), now: now)
        #expect(store.entries.count == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
