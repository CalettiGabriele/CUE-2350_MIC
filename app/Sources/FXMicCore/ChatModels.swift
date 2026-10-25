import Foundation

/// Any JSON value: tool schemas and tool arguments (TDD voice command agent §3.2).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Parses JSON text; nil if it is not valid JSON.
    public init?(json: String) {
        guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        self = value
    }

    /// Compact JSON text.
    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// A tool the model can call, in the MCP shape (`name`, `description`, `inputSchema`).
public struct ToolSpec: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    /// JSON Schema of the input (an object).
    public var inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// A tool call made by the model. `arguments` is the JSON text the provider returned.
public struct ToolCall: Equatable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// One message of a chat, as sent on the OpenAI `/chat/completions` wire.
public struct ChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case system, user, assistant, tool }

    public var role: Role
    public var content: String?
    /// Assistant messages that called tools.
    public var toolCalls: [ToolCall]
    /// Tool messages: the call they answer.
    public var toolCallID: String?

    public init(role: Role, content: String?, toolCalls: [ToolCall] = [], toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func system(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: text) }
    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }
    public static func tool(callID: String, _ text: String) -> ChatMessage {
        ChatMessage(role: .tool, content: text, toolCallID: callID)
    }
}

public struct ChatResponse: Equatable, Sendable {
    /// The text answer, without reasoning blocks (empty when the model only called tools).
    public var text: String
    public var toolCalls: [ToolCall]
    public var finishReason: String?
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(text: String, toolCalls: [ToolCall] = [], finishReason: String? = nil,
                promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    /// The assistant message to put back in the conversation.
    public var message: ChatMessage {
        ChatMessage(role: .assistant, content: text.isEmpty ? nil : text, toolCalls: toolCalls)
    }
}

/// An error worth one more try (a server that answered 5xx, e.g. Ollama failing to parse a
/// malformed tool call).
public protocol RetryableError: Error {
    var isRetryable: Bool { get }
}

/// Where the model runs. The agent loop and the LLM skills only talk to this (ADR-004).
public protocol ChatProvider: Sendable {
    /// `temperature` nil = the provider's default.
    func send(_ messages: [ChatMessage], tools: [ToolSpec], temperature: Double?, maxTokens: Int?) async throws -> ChatResponse
}

extension ChatProvider {
    /// One system and one user message, text answer only (LLM skills, the one-call command).
    public func complete(system: String, user: String, temperature: Double? = nil, maxTokens: Int? = nil) async throws -> String {
        try await send([.system(system), .user(user)], tools: [], temperature: temperature, maxTokens: maxTokens).text
    }
}
