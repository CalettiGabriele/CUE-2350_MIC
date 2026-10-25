import Foundation

/// How much harm a tool call can do (TDD voice command agent §3.3). Risky calls are confirmed on
/// the mic before they run.
public enum Risk: String, Codable, CaseIterable, Comparable, Sendable {
    /// Only looks: never confirmed, also runs in a dry run.
    case read
    /// Changes something that can be undone (text, keys, focus).
    case safe
    /// Sends, deletes, closes or runs user code: asks first.
    case risky

    public static func < (a: Risk, b: Risk) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// What a tool tells the model after running. `content` is short and factual: it is what the
/// model reads to check its own work (G3).
public struct ToolResult: Equatable, Sendable {
    public var ok: Bool
    public var content: String

    public init(ok: Bool, _ content: String) {
        self.ok = ok
        self.content = content
    }

    public static func ok(_ content: String = "ok") -> ToolResult { ToolResult(ok: true, content) }
    public static func failed(_ content: String) -> ToolResult { ToolResult(ok: false, content) }
}

public struct ToolContext: Sendable {
    /// Settings › Voice command › Try a command: tools with effects are not run.
    public var dryRun: Bool

    public init(dryRun: Bool = false) { self.dryRun = dryRun }
}

/// One action the agent can take. Built-in tools, user tools and (later) MCP tools all conform.
public protocol AgentTool: Sendable {
    var spec: ToolSpec { get }
    var risk: Risk { get }
    /// Some calls are riskier than the tool (a click on «Delete»). Default: `risk`.
    func risk(for arguments: JSONValue) -> Risk
    /// A step towards the result, never the result itself (select_text): a successful call does
    /// not end the command by itself (implicit finish).
    var prepares: Bool { get }
    /// The same per call (press_keys cmd+a only selects). Default: `prepares`.
    func prepares(for arguments: JSONValue) -> Bool
    /// A few words for the island and the trace, e.g. `click «Share»`.
    func summary(for arguments: JSONValue) -> String
    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult
}

extension AgentTool {
    public func risk(for arguments: JSONValue) -> Risk { risk }
    public var prepares: Bool { false }
    public func prepares(for arguments: JSONValue) -> Bool { prepares }

    public func summary(for arguments: JSONValue) -> String {
        guard case .object(let fields) = arguments, !fields.isEmpty else { return spec.name }
        let shown = fields.sorted { $0.key < $1.key }.map { _, value -> String in
            let text = value.stringValue ?? value.jsonString
            return text.count > 40 ? "«\(text.prefix(39))…»" : "«\(text)»"
        }
        return spec.name + " " + shown.joined(separator: " ")
    }
}

/// Where tools come from: the built-in set, the user's tools, and later one per MCP server.
public protocol ToolSource: Sendable {
    var id: String { get }
    func tools() async -> [AgentTool]
}

/// The tools of one agent run, in a stable order (the prompt prefix stays cacheable).
public struct ToolRegistry: Sendable {
    public private(set) var tools: [AgentTool] = []
    private var overrides: [String: Risk]

    /// Valid on every provider: OpenAI caps names at 64 characters of this alphabet.
    public static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil
    }

    /// Later tools with a name already taken, an invalid name or a disabled name are left out.
    public init(_ tools: [AgentTool], disabled: Set<String> = [], riskOverrides: [String: Risk] = [:]) {
        overrides = riskOverrides
        var names = Set<String>()
        for tool in tools where Self.isValidName(tool.spec.name) && !disabled.contains(tool.spec.name)
            && names.insert(tool.spec.name).inserted {
            self.tools.append(tool)
        }
    }

    public static func build(_ sources: [ToolSource], disabled: Set<String> = [], riskOverrides: [String: Risk] = [:]) async -> ToolRegistry {
        var all: [AgentTool] = []
        for source in sources { all += await source.tools() }
        return ToolRegistry(all, disabled: disabled, riskOverrides: riskOverrides)
    }

    public var specs: [ToolSpec] { tools.map(\.spec) }

    public func tool(named name: String) -> AgentTool? { tools.first { $0.spec.name == name } }

    /// The user's override replaces the tool's own level, but a call that is risky by its
    /// arguments stays risky.
    public func risk(of tool: AgentTool, arguments: JSONValue) -> Risk {
        let dynamic = tool.risk(for: arguments)
        guard let base = overrides[tool.spec.name] else { return dynamic }
        return dynamic > tool.risk ? max(base, dynamic) : base
    }
}

/// Checks tool arguments against the subset of JSON Schema the tools use: `type`, `properties`,
/// `required`, `enum`, `items`, `additionalProperties: false`. Providers do not all enforce the
/// schema (Anthropic ignores `strict`), so the loop does.
public enum SchemaValidator {
    /// nil when valid, else a short reason for the model.
    public static func validate(_ value: JSONValue, against schema: JSONValue, path: String = "arguments") -> String? {
        if let type = schema["type"]?.stringValue, !matches(value, type) {
            return "\(path) must be \(type == "object" || type == "array" ? "an" : "a") \(type)"
        }
        if case .array(let options)? = schema["enum"], !options.contains(value) {
            let list = options.map { $0.stringValue ?? $0.jsonString }.joined(separator: ", ")
            return "\(path) must be one of: \(list)"
        }
        if case .object(let fields) = value {
            if case .array(let required)? = schema["required"] {
                for case .string(let name) in required where fields[name] == nil || fields[name] == .null {
                    return "missing \(path == "arguments" ? "" : path + ".")\(name)"
                }
            }
            let properties: [String: JSONValue]
            if case .object(let p)? = schema["properties"] { properties = p } else { properties = [:] }
            for (name, field) in fields.sorted(by: { $0.key < $1.key }) {
                if let sub = properties[name] {
                    if let problem = validate(field, against: sub, path: name) { return problem }
                } else if schema["additionalProperties"] == .bool(false) {
                    return "unknown argument \(name)"
                }
            }
        }
        if case .array(let items) = value, let itemSchema = schema["items"] {
            for (i, item) in items.enumerated() {
                if let problem = validate(item, against: itemSchema, path: "\(path)[\(i)]") { return problem }
            }
        }
        return nil
    }

    static func matches(_ value: JSONValue, _ type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null): return true
        case ("number", .number): return true
        case ("integer", .number(let n)): return n.rounded() == n
        default: return false
        }
    }
}

/// Builders for the schemas of the built-in tools.
public enum Schema {
    public static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties),
                 "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])
    }

    public static func string(_ description: String, oneOf values: [String]? = nil) -> JSONValue {
        var field: [String: JSONValue] = ["type": .string("string"), "description": .string(description)]
        if let values { field["enum"] = .array(values.map(JSONValue.string)) }
        return .object(field)
    }

    public static func strings(_ description: String) -> JSONValue {
        .object(["type": .string("array"), "description": .string(description), "items": .object(["type": .string("string")])])
    }
}
