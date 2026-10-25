import FXMicCore
import Foundation
import os

/// Runs the user's tools (TDD voice command agent §3.4): macros as keystrokes and typed text,
/// shortcuts through the `shortcuts` command line tool, in a child process with a time limit.
final class LiveUserRunner: UserToolRunner, @unchecked Sendable {
    private let log = Logger(subsystem: "com.fxmicbridge", category: "user-tools")
    static let shortcutLimit: TimeInterval = 20
    static let maxOutput = 2000

    func runMacro(_ steps: [Action]) async -> ToolResult {
        for step in steps {
            let outcome: TextInjector.Outcome = await MainActor.run {
                switch step {
                case .key(let keys): return TextInjector.send(keys)
                case .text(let text):
                    // A trailing \n also presses Return, as in the Run slots.
                    let body = text.hasSuffix("\n") ? String(text.dropLast()) : text
                    var outcome = body.isEmpty ? .done : TextInjector.insert(body, strategy: .type, restoreAfterMs: 0)
                    if outcome == .done, text.hasSuffix("\n") { outcome = TextInjector.send(["return"]) }
                    return outcome
                default: return .failed
                }
            }
            guard outcome == .done else { return .failed("a step did not run (\(outcome))") }
            // Let the app take each step before the next one.
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return .ok("done")
    }

    func runShortcut(_ name: String, input: String?, returnsOutput: Bool) async -> ToolResult {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fxmic-shortcut-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var arguments = ["run", name]
        if let input {
            let file = folder.appendingPathComponent("input.txt")
            try? input.write(to: file, atomically: true, encoding: .utf8)
            arguments += ["--input-path", file.path]
        }
        let output = folder.appendingPathComponent("output.txt")
        if returnsOutput { arguments += ["--output-path", output.path, "--output-type", "public.plain-text"] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failed("could not start Shortcuts: \(error.localizedDescription)")
        }
        let finished = await withTaskCancellationHandler {
            await Self.wait(for: process, limit: Self.shortcutLimit)
        } onCancel: {
            process.terminate()
        }
        guard finished else {
            process.terminate()
            return .failed("the shortcut \(name) did not finish within \(Int(Self.shortcutLimit)) s")
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            log.error("shortcut \(name, privacy: .public) failed: \(message, privacy: .public)")
            return .failed("the shortcut \(name) failed" + (message.isEmpty ? "" : ": " + String(message.prefix(200))))
        }
        if returnsOutput, let text = try? String(contentsOf: output, encoding: .utf8), !text.isEmpty {
            return .ok(String(text.prefix(Self.maxOutput)))
        }
        return .ok("ran the shortcut \(name)")
    }

    private static func wait(for process: Process, limit: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning {
            if Date() > deadline || Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }

    /// The user's shortcuts, for the picker in Settings.
    static func shortcutNames() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.split(separator: "\n").map(String.init).sorted() ?? []
        }.value
    }
}
