import FXMicCore
import Foundation

/// An action an engine decided to run, in the agent's tool vocabulary (TDD §3.3).
public struct EvalAction: Codable, Sendable, Equatable {
    public var tool: String
    public var keys: [String]
    public var args: [String: String]

    public init(tool: String, keys: [String] = [], args: [String: String] = [:]) {
        self.tool = tool
        self.keys = keys
        self.args = args
    }

    /// Short form for reports: `press_keys(cmd+a delete)`, `type_text("- ")`.
    public var summary: String {
        if tool == "press_keys" { return "press_keys(\(keys.joined(separator: " ")))" }
        let shown = args.sorted { $0.key < $1.key }.map { key, value in
            let cut = value.count > 60 ? String(value.prefix(57)) + "…" : value
            return args.count == 1 ? "\"\(cut)\"" : "\(key): \"\(cut)\""
        }
        return "\(tool)(\(shown.joined(separator: ", ")))"
    }
}

public enum Scorer {
    /// Tools that only look or end the loop: they are not part of the outcome.
    public static let readOnlyTools: Set<String> = [
        "read_focused_text", "read_ui", "list_windows", "list_menu_items", "finish",
    ]

    /// Drops read-only tools and merges consecutive key presses, so equivalent answers compare equal.
    public static func outcome(_ actions: [EvalAction]) -> [EvalAction] {
        var result: [EvalAction] = []
        for action in actions where !readOnlyTools.contains(action.tool) {
            var action = action
            action.keys = action.keys.map(canonicalKey)
            if action.tool == "press_keys", let last = result.last, last.tool == "press_keys" {
                result[result.count - 1].keys += action.keys
            } else {
                result.append(action)
            }
        }
        return result
    }

    public static func passes(_ actions: [EvalAction], _ testCase: EvalCase, screen: Screen) -> Bool {
        let got = outcome(actions)
        return testCase.expect.contains { alternative in
            alternative.count == got.count && zip(alternative, got).allSatisfy { matches($0, $1, screen: screen) }
        }
    }

    static func matches(_ m: StepMatcher, _ a: EvalAction, screen: Screen) -> Bool {
        guard m.tool == a.tool else { return false }
        if let keys = m.keys, keys.map(canonicalKey) != a.keys { return false }
        let text = a.args["text"] ?? ""
        if let expected = m.text, loose(expected) != loose(text) { return false }
        if let groups = m.textIncludes {
            let haystack = loose(text)
            guard groups.allSatisfy({ $0.values.contains { haystack.contains(loose($0)) } }) else { return false }
        }
        if let excluded = m.textExcludes, excluded.contains(where: { loose(text).contains(loose($0)) }) { return false }
        if m.shorterThanSelection == true, text.count >= (screen.selection ?? "").count { return false }
        if let name = m.name, !sameName(name, a.args["name"] ?? "", tool: a.tool, screen: screen) { return false }
        for (key, expected) in m.args ?? [:] {
            let value = loose(a.args[key] ?? "")
            guard expected.values.contains(where: { loose($0) == value }) else { return false }
        }
        return true
    }

    /// Channels and skills are found the way the app finds them, so "Codex" means "Codex · fxmic-bridge".
    static func sameName(_ expected: String, _ got: String, tool: String, screen: Screen) -> Bool {
        let names: [String]
        switch tool {
        case "switch_channel": names = screen.channels ?? []
        case "run_skill": names = Profile.defaults.first { $0.id == screen.profile }?.slots.map(\.name) ?? []
        default: return loose(expected) == loose(got)
        }
        guard let want = NameMatcher.index(of: expected, in: names) else { return false }
        return NameMatcher.index(of: got, in: names) == want
    }

    /// Case, accents, spacing, menu separators and final punctuation do not matter.
    public static func loose(_ text: String) -> String {
        var t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        t = t.replacingOccurrences(of: "›", with: ">").replacingOccurrences(of: "…", with: "...")
        t = t.replacingOccurrences(of: "’", with: "'")
        t = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        t = t.replacingOccurrences(of: " > ", with: ">").replacingOccurrences(of: "> ", with: ">")
            .replacingOccurrences(of: " >", with: ">")
        while let last = t.last, ".!?;:".contains(last) { t.removeLast() }
        return t
    }

    /// "cmd+shift+x" with modifiers in a fixed order and key aliases resolved.
    public static func canonicalKey(_ key: String) -> String {
        KeyCombo(key)?.canonical ?? key.lowercased()
    }
}
