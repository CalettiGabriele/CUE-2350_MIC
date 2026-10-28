import Foundation
import os

/// `ChatProvider` for any OpenAI-compatible `/chat/completions` server: Ollama, LM Studio,
/// OpenAI, Anthropic's compatibility layer, OpenRouter (ADR-004). Non-streaming only.
public struct OpenAICompatibleClient: ChatProvider {
    public var provider: LLMProvider
    public var model: String
    public var apiKey: String?
    public var timeoutMs: Double
    /// Asks for no thinking phase, where the preset supports it.
    public var disableThinking: Bool

    private static let log = Logger(subsystem: "com.fxmicbridge", category: "llm")

    public init(provider: LLMProvider, model: String, apiKey: String?, timeoutMs: Double, disableThinking: Bool) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.timeoutMs = timeoutMs
        self.disableThinking = disableThinking
    }

    public enum Failure: LocalizedError, Equatable {
        case badURL
        case http(Int, String?)
        case empty
        case missingKey

        public var errorDescription: String? {
            switch self {
            case .badURL: return L.t("Invalid LLM endpoint URL")
            case .http(let code, let message): return L.f("LLM: HTTP error %d", code) + (message.map { " – " + $0 } ?? "")
            case .empty: return L.t("LLM: empty response")
            case .missingKey: return L.t("No API key saved for this provider")
            }
        }
    }

    // MARK: - Request

    /// The JSON body, kept separate so it can be tested without a server.
    public func body(_ messages: [ChatMessage], tools: [ToolSpec], temperature: Double?, maxTokens: Int?) -> [String: Any] {
        var body: [String: Any] = ["model": model, "stream": false, "messages": messages.map(Self.wire)]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                ["type": "function", "function": [
                    "name": tool.name, "description": tool.description, "parameters": Self.any(tool.inputSchema),
                ]]
            }
            // Forced tool use is rejected by some models (Claude 5.5): always let the model choose.
            body["tool_choice"] = "auto"
        }
        if let temperature, provider.preset.sendsTemperature { body["temperature"] = temperature }
        if let maxTokens = maxTokens ?? provider.preset.defaultMaxTokens {
            body[provider.preset.maxTokensField] = max(maxTokens, provider.preset.minOutputTokens)
        }
        if disableThinking, provider.preset.canDisableThinking {
            // Ollama's own `think: false` is ignored on the OpenAI-compatible endpoint.
            body["reasoning_effort"] = "none"
        }
        return body
    }

    static func wire(_ message: ChatMessage) -> [String: Any] {
        var m: [String: Any] = ["role": message.role.rawValue]
        m["content"] = message.content ?? NSNull()
        if !message.toolCalls.isEmpty {
            m["tool_calls"] = message.toolCalls.map {
                ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]]
            }
        }
        if let id = message.toolCallID { m["tool_call_id"] = id }
        return m
    }

    static func any(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(any)
        case .object(let o): return o.mapValues(any)
        }
    }

    private func request(path: String, timeout: Double) throws -> URLRequest {
        guard let base = URL(string: provider.baseURL), base.scheme != nil else { throw Failure.badURL }
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else if provider.preset.needsKey {
            throw Failure.missingKey
        }
        for (name, value) in provider.extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    // MARK: - ChatProvider

    public func send(_ messages: [ChatMessage], tools: [ToolSpec], temperature: Double?, maxTokens: Int?) async throws -> ChatResponse {
        var request = try request(path: "chat/completions", timeout: timeoutMs / 1000)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body(messages, tools: tools, temperature: temperature,
                                                                          maxTokens: maxTokens))
        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status, Self.errorMessage(data)) }
        let parsed = try Self.parse(data)
        let ms = Date().timeIntervalSince(start) * 1000
        Self.log.notice("llm \(model, privacy: .public) on \(provider.id, privacy: .public) answered in \(ms, format: .fixed(precision: 0), privacy: .public) ms, \(parsed.toolCalls.count, privacy: .public) tool calls")
        guard !parsed.text.isEmpty || !parsed.toolCalls.isEmpty else { throw Failure.empty }
        return parsed
    }

    /// Reads a `/chat/completions` answer. Arguments given as an object instead of JSON text
    /// (some servers do) are turned back into text.
    public static func parse(_ data: Data) throws -> ChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first else { throw Failure.empty }
        let message = choice["message"] as? [String: Any] ?? [:]
        var text = message["content"] as? String ?? ""
        if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).enumerated().compactMap { index, call -> ToolCall? in
            guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
            var arguments = function["arguments"] as? String ?? "{}"
            if let object = function["arguments"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: object) {
                arguments = String(decoding: data, as: UTF8.self)
            }
            return ToolCall(id: call["id"] as? String ?? "call_\(index)", name: name, arguments: arguments)
        }
        let usage = json["usage"] as? [String: Any]
        return ChatResponse(text: PromptComposer.clean(text), toolCalls: calls,
                            finishReason: choice["finish_reason"] as? String,
                            promptTokens: usage?["prompt_tokens"] as? Int, completionTokens: usage?["completion_tokens"] as? Int)
    }

    static func errorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let message = (json["error"] as? [String: Any])?["message"] as? String ?? json["error"] as? String
        return message.map { String($0.prefix(200)) }
    }

    // MARK: - Helpers

    /// Model ids from `/models`, or nil if the server cannot be reached.
    public func availableModels() async -> [String]? {
        guard var request = try? request(path: "models", timeout: 3) else { return nil }
        request.httpMethod = "GET"
        if provider.preset == .anthropic, let apiKey {
            // Anthropic's model list is a native endpoint: it wants its own headers.
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return nil }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    /// The agent's prompt with every tool is about 3,500 tokens and grows with each step:
    /// Ollama's default 4,096-token context re-reads it every time and, past the limit, cuts its
    /// start. The context of the loaded model, from Ollama's own `/api/ps`; nil elsewhere.
    public func ollamaContextLength() async -> Int? {
        guard provider.preset == .ollama, var base = URL(string: provider.baseURL) else { return nil }
        if base.lastPathComponent == "v1" { base.deleteLastPathComponent() }
        guard let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("api/ps")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        let loaded = models.first { ($0["name"] as? String) == model || ($0["model"] as? String) == model }
        return loaded?["context_length"] as? Int
    }

    public static let agentContextLength = 8192

    /// Loads the model into memory ahead of the first dictation (Ollama keeps it ~5 min).
    public func warmUp() {
        guard provider.isLocal else { return }
        Task.detached { [self] in
            _ = try? await complete(system: "Reply only: ok", user: "ok", maxTokens: 1)
        }
    }

    /// Asks the model to call one tool: proves that the server, the key, the model and tool
    /// calling all work (Settings › Model › Test). Returns the time it took.
    public func testToolCall() async throws -> Double {
        let echo = ToolSpec(name: "echo", description: "Repeats a word back.", inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["word": .object(["type": .string("string")])]),
            "required": .array([.string("word")]),
        ]))
        let start = Date()
        let response = try await send([.system("Call the tool echo with the word ok. Do not answer with text."),
                                       .user("ok")], tools: [echo], temperature: 0, maxTokens: 200)
        guard response.toolCalls.contains(where: { $0.name == "echo" }) else { throw ToolTestFailure.noToolCall(response.text) }
        return Date().timeIntervalSince(start) * 1000
    }

    public enum ToolTestFailure: LocalizedError {
        case noToolCall(String)
        public var errorDescription: String? {
            switch self {
            case .noToolCall(let text):
                return L.t("The model answered without calling the tool") + (text.isEmpty ? "" : ": " + String(text.prefix(120)))
            }
        }
    }
}

extension OpenAICompatibleClient.Failure: RetryableError {
    public var isRetryable: Bool {
        if case .http(let code, _) = self { return (500...599).contains(code) }
        return false
    }
}
