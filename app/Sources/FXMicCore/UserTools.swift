import Foundation

/// A tool the user adds in Settings › Voice command › My tools (TDD voice command agent §3.4).
public struct UserTool: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Keys and text, in order, as the Run slots do.
        case macro
        /// A shortcut of the Shortcuts app, run with `shortcuts run`.
        case shortcut
    }

    public var id = UUID()
    public var kind: Kind
    /// What the user calls it; the model sees `user_` + this name in snake case.
    public var name: String
    /// When to use it, for the model: written by the user, in English like every prompt.
    public var description: String
    /// macro: `key` and `text` actions; `{{text}}` in a text step takes the parameter.
    public var steps: [Action] = []
    /// shortcut: its name in the Shortcuts app.
    public var shortcut: String = ""
    /// What the model passes in, e.g. "Reminder text"; nil = the tool takes nothing.
    public var parameter: String?
    /// shortcut: send the shortcut's text output back to the model.
    public var returnsOutput = false
    public var risk: Risk

    public init(kind: Kind, name: String, description: String, steps: [Action] = [], shortcut: String = "",
                parameter: String? = nil, returnsOutput: Bool = false, risk: Risk? = nil) {
        self.kind = kind
        self.name = name
        self.description = description
        self.steps = steps
        self.shortcut = shortcut
        self.parameter = parameter
        self.returnsOutput = returnsOutput
        // A shortcut can do anything: it asks first unless the user says otherwise.
        self.risk = risk ?? (kind == .shortcut ? .risky : .safe)
    }

    /// `user_` + the name in lowercase snake case, cut to the 64 characters every provider accepts.
    public var toolName: String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var snake = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII { snake.unicodeScalars.append(scalar) }
            else if !snake.hasSuffix("_") { snake += "_" }
        }
        snake = snake.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = snake.hasPrefix("user_") ? snake : "user_" + snake
        return String((base == "user_" ? "user_tool" : base).prefix(64))
    }

    /// Why the tool cannot be used yet, for Settings; nil when it is complete.
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give it a name." }
        if description.trimmingCharacters(in: .whitespaces).isEmpty { return "Say when to use it: the model reads this." }
        switch kind {
        case .macro:
            if steps.isEmpty { return "Add at least one step." }
            for case .key(let keys) in steps where keys.isEmpty || keys.contains(where: { KeyCombo($0) == nil }) {
                return "A step has a shortcut that is not valid."
            }
        case .shortcut:
            if shortcut.trimmingCharacters(in: .whitespaces).isEmpty { return "Pick a shortcut." }
        }
        return nil
    }
}

extension UserTool {
    private enum CodingKeys: String, CodingKey { case id, kind, name, description, steps, shortcut, parameter, returnsOutput, risk }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .macro
        self.init(kind: kind, name: (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "",
                  description: (try? c.decodeIfPresent(String.self, forKey: .description)) ?? "",
                  steps: (try? c.decodeIfPresent([Action].self, forKey: .steps)) ?? [],
                  shortcut: (try? c.decodeIfPresent(String.self, forKey: .shortcut)) ?? "",
                  parameter: (try? c.decodeIfPresent(String.self, forKey: .parameter)) ?? nil,
                  returnsOutput: (try? c.decodeIfPresent(Bool.self, forKey: .returnsOutput)) ?? false,
                  risk: (try? c.decodeIfPresent(Risk.self, forKey: .risk)) ?? nil)
        if let id = try? c.decodeIfPresent(UUID.self, forKey: .id) { self.id = id }
    }
}

/// Runs user tools on the Mac: keystrokes for macros, the Shortcuts app for shortcuts.
public protocol UserToolRunner: Sendable {
    /// `steps` already have `{{text}}` filled in.
    func runMacro(_ steps: [Action]) async -> ToolResult
    func runShortcut(_ name: String, input: String?, returnsOutput: Bool) async -> ToolResult
}

extension BuiltInTools {
    /// The user's tools as agent tools. Incomplete ones are left out.
    public static func user(_ tools: [UserTool], runner: UserToolRunner) -> [AgentTool] {
        tools.filter { $0.problem == nil }.map { UserAgentTool(tool: $0, runner: runner) }
    }
}

struct UserAgentTool: AgentTool {
    let tool: UserTool
    let runner: UserToolRunner

    var risk: Risk { tool.risk }

    var spec: ToolSpec {
        var properties: [String: JSONValue] = [:]
        var required: [String] = []
        if let parameter = tool.parameter, !parameter.isEmpty {
            properties["text"] = Schema.string(parameter)
            required = ["text"]
        }
        return ToolSpec(name: tool.toolName, description: tool.description, inputSchema: Schema.object(properties, required: required))
    }

    func summary(for arguments: JSONValue) -> String {
        tool.name + (arguments["text"]?.stringValue.map { " «\($0.prefix(40))»" } ?? "")
    }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        let text = arguments["text"]?.stringValue
        switch tool.kind {
        case .macro:
            let steps = tool.steps.map { step -> Action in
                guard case .text(let value) = step else { return step }
                return .text(value.replacingOccurrences(of: "{{text}}", with: text ?? ""))
            }
            return await runner.runMacro(steps)
        case .shortcut:
            return await runner.runShortcut(tool.shortcut, input: text, returnsOutput: tool.returnsOutput)
        }
    }
}

// MARK: - Catalog for Settings

/// The built-in tools by group, for Settings › Voice command › Tools: names, descriptions and
/// risk levels come from the tools themselves.
public enum ToolCatalog {
    public struct Entry: Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var description: String
        public var risk: Risk
        /// Off unless the user turns it on (`agent.enabledTools`).
        public var optIn: Bool
    }

    public static let groups: [(title: String, tools: [String])] = [
        ("Text and keys", ["type_text", "press_keys", "replace_selection"]),
        ("Read, select, format", ["read_focused_text", "select_text", "format_selection"]),
        ("Channels, skills, intents", ["switch_channel", "run_skill", "run_intent"]),
        ("Controls of the window", ["read_ui", "click", "set_value"]),
        ("Menus", ["list_menu_items", "choose_menu_item"]),
        ("Windows and apps", ["list_windows", "focus_window", "close_window", "open_app"]),
        ("Web", ["open_url"]),
    ]

    public static var entries: [Entry] {
        let noop = NoopMac()
        let tools = BuiltInTools.standard(noop, screen: ScreenContext(app: "")) + BuiltInTools.interface(noop, allowOpenURL: true)
        return tools.map { Entry(name: $0.spec.name, description: $0.spec.description, risk: $0.risk,
                                 optIn: $0.spec.name == "open_url") }
    }
}

/// Does nothing: lets the catalog read the tools' names and texts.
public struct NoopMac: MacActions, MacUI {
    public init() {}
    private static let no = ToolResult.failed("not available")
    public func typeText(_ text: String) async -> ToolResult { Self.no }
    public func pressKeys(_ keys: [String]) async -> ToolResult { Self.no }
    public func replaceSelection(_ text: String) async -> ToolResult { Self.no }
    public func switchChannel(_ name: String) async -> ToolResult { Self.no }
    public func runSkill(_ name: String) async -> ToolResult { Self.no }
    public func runIntent(_ name: String) async -> ToolResult { Self.no }
    public func readFocusedText() async -> ToolResult { Self.no }
    public func selectText(_ text: String, occurrence: Int) async -> ToolResult { Self.no }
    public func currentSelection() async -> String? { nil }
    public func uiElements() async -> [UIElementInfo]? { nil }
    public func press(_ id: String) async -> ToolResult { Self.no }
    public func setValue(_ id: String, text: String) async -> ToolResult { Self.no }
    public func menuItems() async -> [String]? { nil }
    public func chooseMenuItem(_ path: String) async -> ToolResult { Self.no }
    public func windows() async -> [WindowInfo] { [] }
    public func focusWindow(_ id: String) async -> ToolResult { Self.no }
    public func closeWindow(_ id: String) async -> ToolResult { Self.no }
    public func openApp(_ name: String) async -> ToolResult { Self.no }
    public func openURL(_ url: URL) async -> ToolResult { Self.no }
}
