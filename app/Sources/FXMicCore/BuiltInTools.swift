import Foundation

/// What the built-in tools do on the Mac. The app implements it with keystrokes, Accessibility
/// and its channel engine; the evaluation implements it on a fake screen. Names passed here are
/// already resolved against the screen's lists.
public protocol MacActions: Sendable {
    func typeText(_ text: String) async -> ToolResult
    func pressKeys(_ keys: [String]) async -> ToolResult
    func replaceSelection(_ text: String) async -> ToolResult
    func switchChannel(_ name: String) async -> ToolResult
    func runSkill(_ name: String) async -> ToolResult
    func runIntent(_ name: String) async -> ToolResult
    /// The whole text of the focused field and the selection, for the model to read.
    func readFocusedText() async -> ToolResult
    /// Selects the `occurrence`-th match of `text` in the focused field (1 = first, -1 = last).
    /// On success the result's content starts with the exact text selected.
    func selectText(_ text: String, occurrence: Int) async -> ToolResult
    /// The selected text right now (after keys such as cmd+a or shift+arrows), nil if none.
    func currentSelection() async -> String?
}

/// What the tools of one run know about the screen while they change it: the selection after
/// select_text, cmd+a or a replacement. Starts from the snapshot.
public final class ScreenState: @unchecked Sendable {
    private let lock = NSLock()
    private var _selection: String?
    public let textFormat: String

    public init(_ screen: ScreenContext) {
        _selection = (screen.selection ?? "").isEmpty ? nil : screen.selection
        textFormat = screen.textFormat
    }

    public var selection: String? {
        get { lock.withLock { _selection } }
        set { lock.withLock { _selection = (newValue ?? "").isEmpty ? nil : newValue } }
    }
}

/// The built-in tools of TDD voice command agent §3.3: the parity set (phase 3: what the one-call
/// command could do) and reading, selecting and formatting text (phase 4). Each tool checks its
/// arguments first, so a wrong call fails with a reason the model can act on.
public enum BuiltInTools {
    public static func standard(_ mac: MacActions, screen: ScreenContext) -> [AgentTool] {
        let state = ScreenState(screen)
        return [
            TypeTextTool(mac: mac, state: state),
            PressKeysTool(mac: mac, state: state),
            ReplaceSelectionTool(mac: mac, state: state),
            NamedTool(kind: .channel, names: screen.channels, mac: mac),
            NamedTool(kind: .skill, names: screen.skills, mac: mac),
            NamedTool(kind: .intent, names: screen.intents, mac: mac),
            ReadFocusedTextTool(mac: mac),
            SelectTextTool(mac: mac, state: state),
            FormatSelectionTool(mac: mac, state: state),
        ]
    }

    /// Why a shortcut cannot be pressed, or nil if it can.
    public static func keyProblem(_ key: String) -> String? {
        let modifiers = ["cmd", "command", "shift", "opt", "option", "alt", "ctrl", "control"]
        if modifiers.contains(key.lowercased().trimmingCharacters(in: .whitespaces)) {
            return "\(key) is a modifier: join it to a key, e.g. \(key)+left"
        }
        guard let combo = KeyCombo(key) else { return "unknown shortcut \(key)" }
        if combo.isBlocked { return "\(key) is blocked for safety" }
        return nil
    }
}

struct TypeTextTool: AgentTool {
    let mac: MacActions
    let state: ScreenState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "type_text",
        description: "Types text at the cursor: what the COMMAND dictates after write or type, or a list marker.",
        inputSchema: Schema.object(["text": Schema.string("The text to type, exactly as it should appear.")], required: ["text"]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else { return .failed("text is empty") }
        let result = await mac.typeText(text)
        if result.ok { state.selection = nil }
        return result
    }
}

struct PressKeysTool: AgentTool {
    let mac: MacActions
    let state: ScreenState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "press_keys",
        description: "Presses shortcuts in order. Each one is optional modifiers (cmd, shift, opt, ctrl) joined with + "
            + "to one key: a letter, a digit, return, tab, space, delete, forwarddelete, escape, left, right, up, down, "
            + "home, end. delete erases before the cursor, opt+delete the previous word, cmd+shift+left selects to the "
            + "line start.",
        inputSchema: Schema.object(["keys": Schema.strings("Shortcuts such as shift+return, cmd+a, delete.")], required: ["keys"]))

    func summary(for arguments: JSONValue) -> String {
        guard case .array(let keys)? = arguments["keys"] else { return spec.name }
        return keys.compactMap(\.stringValue).joined(separator: " ")
    }

    /// Return sends where the field is a chat or a terminal (markdown, plain): that asks first. In
    /// rich text (Mail, Notes) it is a new line.
    func risk(for arguments: JSONValue) -> Risk {
        guard state.textFormat != "rich", case .array(let items)? = arguments["keys"] else { return risk }
        let sends = items.compactMap(\.stringValue).contains { key in
            guard let combo = KeyCombo(key) else { return false }
            return (combo.key == "return" || combo.key == "enter") && combo.modifiers.subtracting([.command]).isEmpty
        }
        return sends ? .risky : risk
    }

    /// Keys that only select (cmd+a, shift+arrows…) prepare the next step: they do not end the command.
    func prepares(for arguments: JSONValue) -> Bool {
        guard case .array(let items)? = arguments["keys"], !items.isEmpty else { return false }
        return items.compactMap(\.stringValue).allSatisfy { key in
            guard let combo = KeyCombo(key) else { return false }
            if combo.key == "a", combo.modifiers == [.command] { return true }
            let moves = ["left", "right", "up", "down", "home", "end", "pageup", "pagedown"]
            return combo.modifiers.contains(.shift) && moves.contains(combo.key)
        }
    }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard case .array(let items)? = arguments["keys"] else { return .failed("keys is missing") }
        let keys = items.compactMap(\.stringValue)
        guard !keys.isEmpty, keys.count <= 20 else { return .failed("give between 1 and 20 shortcuts") }
        for key in keys {
            if let problem = BuiltInTools.keyProblem(key) { return .failed(problem + "; nothing was pressed") }
        }
        let result = await mac.pressKeys(keys)
        // Keys can select (cmd+a, shift+arrows) or drop the selection: ask what it is now.
        if result.ok {
            state.selection = await mac.currentSelection()
            if let selection = state.selection {
                return .ok(result.content + "; selected: \"\(selection.prefix(120))\"")
            }
        }
        return result
    }
}

struct ReplaceSelectionTool: AgentTool {
    let mac: MacActions
    let state: ScreenState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "replace_selection",
        description: "Replaces the selection in CONTEXT with your new version of it (translated, shorter, fixed, "
            + "as a list). Only the selection, never the rest of the field.",
        inputSchema: Schema.object(["text": Schema.string("The new version of the selected text.")], required: ["text"]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard state.selection != nil else { return .failed("nothing is selected") }
        guard let text = arguments["text"]?.stringValue else { return .failed("text is missing") }
        let result = await mac.replaceSelection(text)
        if result.ok { state.selection = nil }
        return result
    }
}

/// switch_channel, run_skill and run_intent: a name from a list in CONTEXT.
struct NamedTool: AgentTool {
    enum Kind { case channel, skill, intent }
    let kind: Kind
    let names: [String]
    let mac: MacActions
    let risk = Risk.safe

    var spec: ToolSpec {
        switch kind {
        case .channel:
            return ToolSpec(name: "switch_channel",
                            description: "Goes to one of the channels in CONTEXT (go to, switch to, open). Part of the name is enough.",
                            inputSchema: Schema.object(["name": Schema.string("The channel's name, or part of it.")], required: ["name"]))
        case .skill:
            return ToolSpec(name: "run_skill",
                            description: "Runs one of the skills in CONTEXT when the COMMAND names it (run, do, launch).",
                            inputSchema: Schema.object(["name": Schema.string("The skill's name.")], required: ["name"]))
        case .intent:
            return ToolSpec(name: "run_intent",
                            description: "Does one of the intents in CONTEXT, only when the COMMAND means exactly that: "
                                + "interrupt = stop what the agent or app is doing; newSession = a new session or chat. "
                                + "Never use an intent in place of an action you do not have.",
                            inputSchema: Schema.object(["name": Schema.string("The intent's name.")], required: ["name"]))
        }
    }

    func summary(for arguments: JSONValue) -> String { arguments["name"]?.stringValue ?? spec.name }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        let query = arguments["name"]?.stringValue ?? ""
        let what: String
        switch kind {
        case .channel: what = "channel"
        case .skill: what = "skill"
        case .intent: what = "intent"
        }
        guard !names.isEmpty else { return .failed("there are no \(what)s here") }
        // Intents are identifiers: exact match only, so "stop" does not pick a random one.
        let index = kind == .intent
            ? names.firstIndex { $0.caseInsensitiveCompare(query) == .orderedSame }
            : NameMatcher.index(of: query, in: names)
        guard let index else {
            return .failed("no \(what) called \(query); the \(what)s are: " + names.joined(separator: ", "))
        }
        switch kind {
        case .channel: return await mac.switchChannel(names[index])
        case .skill: return await mac.runSkill(names[index])
        case .intent: return await mac.runIntent(names[index])
        }
    }
}

struct ReadFocusedTextTool: AgentTool {
    let mac: MacActions
    let risk = Risk.read
    let spec = ToolSpec(
        name: "read_focused_text",
        description: "Reads the whole text of the focused field and what is selected in it.",
        inputSchema: Schema.object([:]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult { await mac.readFocusedText() }
}

struct SelectTextTool: AgentTool {
    let mac: MacActions
    let state: ScreenState
    let risk = Risk.safe
    let prepares = true
    let spec = ToolSpec(
        name: "select_text",
        description: "Selects a piece of text in the focused field, e.g. a word to format or replace. "
            + "occurrence: 1 = where it first appears (default), 2 = the second time, -1 = the last time.",
        inputSchema: Schema.object([
            "text": Schema.string("The text to select, as written in the field."),
            "occurrence": .object(["type": .string("integer"), "description": .string("1, 2, … or -1 for the last.")]),
        ], required: ["text"]))

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else { return .failed("text is empty") }
        var occurrence = 1
        if case .number(let n)? = arguments["occurrence"], n != 0 { occurrence = Int(n) }
        // Selecting what is already selected would jump to its first occurrence: nothing to do.
        if occurrence == 1, let current = state.selection,
           current.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return .ok("already selected")
        }
        let result = await mac.selectText(text, occurrence: occurrence)
        if result.ok { state.selection = await mac.currentSelection() ?? text }
        return result
    }
}

/// Bold, italic, lists… the way the field supports them: shortcuts in rich text, Markdown marks in
/// Markdown fields (the Claude input), nothing in plain text (terminals).
struct FormatSelectionTool: AgentTool {
    static let styles = ["bold", "italic", "underline", "strikethrough", "code", "heading", "bullet_list", "numbered_list"]

    let mac: MacActions
    let state: ScreenState
    let risk = Risk.safe
    let spec = ToolSpec(
        name: "format_selection",
        description: "Formats the selected text. Works in the text format of CONTEXT: rich text (shortcuts) or markdown "
            + "(marks such as **bold**). To format a word that is not selected, select_text it first.",
        inputSchema: Schema.object(["style": Schema.string("The style.", oneOf: FormatSelectionTool.styles)],
                                   required: ["style"]))

    func summary(for arguments: JSONValue) -> String { arguments["style"]?.stringValue ?? spec.name }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        guard let style = arguments["style"]?.stringValue else { return .failed("style is missing") }
        guard let selection = state.selection else { return .failed("nothing is selected: select_text first") }
        switch state.textFormat {
        case "markdown":
            guard let marked = Self.markdown(selection, style: style) else {
                return .failed("markdown has no \(style)")
            }
            let result = await mac.replaceSelection(marked)
            if result.ok { state.selection = nil }
            return result.ok ? .ok("formatted as \(style): \(marked.prefix(120))") : result
        case "rich":
            guard let keys = Self.richKeys[style] else {
                return .failed("\(style) has no shortcut in this app; available: bold, italic, underline")
            }
            let result = await mac.pressKeys(keys)
            return result.ok ? .ok("formatted as \(style)") : result
        default:
            return .failed("this field is plain text: it has no formatting")
        }
    }

    static let richKeys: [String: [String]] = ["bold": ["cmd+b"], "italic": ["cmd+i"], "underline": ["cmd+u"]]

    static func markdown(_ text: String, style: String) -> String? {
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        switch style {
        case "bold": return "**\(text)**"
        case "italic": return "*\(text)*"
        case "strikethrough": return "~~\(text)~~"
        case "code": return text.contains("\n") ? "```\n\(text)\n```" : "`\(text)`"
        case "heading": return "# " + text
        case "bullet_list": return lines.map { "- " + $0 }.joined(separator: "\n")
        case "numbered_list": return lines.enumerated().map { "\($0.offset + 1). " + $0.element }.joined(separator: "\n")
        default: return nil
        }
    }
}
