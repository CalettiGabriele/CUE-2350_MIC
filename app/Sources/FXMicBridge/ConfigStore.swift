import FXMicCore
import Foundation
import os

/// Loads ~/Library/Application Support/FXMicBridge/config.json (TDD §3.3). On first run the
/// defaults are written there so the file can be edited by hand; a backup is kept on save.
enum ConfigStore {
    private static let log = Logger(subsystem: "com.fxmicbridge", category: "config")

    static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FXMicBridge", isDirectory: true)
    static var fileURL: URL { directory.appendingPathComponent("config.json") }
    static var modelsDirectory: URL { directory.appendingPathComponent("models", isDirectory: true) }

    /// Returns the config and an error message if the file exists but could not be parsed.
    static func load() -> (AppConfig, String?) {
        guard let data = try? Data(contentsOf: fileURL) else {
            let defaults = AppConfig()
            writeDefaults(defaults)
            return (defaults, nil)
        }
        do {
            return (try JSONDecoder().decode(AppConfig.self, from: data), nil)
        } catch {
            log.error("config.json invalid: \(String(describing: error), privacy: .public)")
            return (AppConfig(), L.t("config.json is invalid: using the defaults"))
        }
    }

    static var iconsDirectory: URL { directory.appendingPathComponent("icons", isDirectory: true) }

    private static func writeDefaults(_ config: AppConfig) {
        if save(config, backup: false) {
            log.notice("wrote default config to \(fileURL.path, privacy: .public)")
        }
    }

    /// Writes the config, keeping the previous file as config.json.bak (TDD §8).
    @discardableResult
    static func save(_ config: AppConfig, backup: Bool = true) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if backup, FileManager.default.fileExists(atPath: fileURL.path) {
                let bak = directory.appendingPathComponent("config.json.bak")
                try? FileManager.default.removeItem(at: bak)
                try FileManager.default.copyItem(at: fileURL, to: bak)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
            return true
        } catch {
            log.error("cannot write config: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Copies a user-chosen icon into the support folder so it survives moving the original.
    static func importIcon(from source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        let target = iconsDirectory.appendingPathComponent("menubar." + source.pathExtension.lowercased())
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}
