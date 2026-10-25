import FXMicCore
import Foundation

/// What one engine did with one command.
public struct EngineResult: Sendable {
    /// nil when the model could not be reached: the run counts as failed.
    public var actions: [EvalAction]?
    /// Why nothing ran, e.g. "blocked: cmd+q", "invalid response", or the transport error.
    public var note: String?
    public var latencyMs: Double
    public var raw: String

    public init(actions: [EvalAction]?, note: String? = nil, latencyMs: Double, raw: String) {
        self.actions = actions
        self.note = note
        self.latencyMs = latencyMs
        self.raw = raw
    }
}

public protocol EvalEngine: Sendable {
    var name: String { get }
    func run(_ testCase: EvalCase, screen: Screen) async -> EngineResult
}

/// An OpenAI-compatible `/chat/completions` endpoint, sent the same body as the app's `LLMClient`.
public struct ChatEndpoint: Sendable {
    public var baseURL: String
    public var model: String
    public var apiKey: String?
    public var timeoutMs: Double
    public var disableThinking: Bool

    public init(baseURL: String, model: String, apiKey: String? = nil, timeoutMs: Double, disableThinking: Bool) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeoutMs = timeoutMs
        self.disableThinking = disableThinking
    }

    public struct Failure: LocalizedError {
        public var errorDescription: String?
    }

    /// The answer's text, cleaned like the app does.
    public func complete(system: String, user: String, temperature: Double) async throws -> String {
        guard let url = URL(string: baseURL)?.appendingPathComponent("chat/completions") else {
            throw Failure(errorDescription: "invalid URL \(baseURL)")
        }
        var request = URLRequest(url: url, timeoutInterval: timeoutMs / 1000)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = [
            "model": model, "temperature": temperature, "stream": false,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        if disableThinking { body["reasoning_effort"] = "none" }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure(errorDescription: "HTTP \(status)") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = ((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        return PromptComposer.clean(content ?? "")
    }
}

/// Today's voice command: one call with `PromptComposer.commandMessages`, validated by
/// `CommandParser` (DictationController.runCommand). The baseline of phase 0.
public struct LegacyEngine: EvalEngine {
    public let endpoint: ChatEndpoint
    public var name: String { "legacy" }

    public init(endpoint: ChatEndpoint) { self.endpoint = endpoint }

    public func run(_ testCase: EvalCase, screen: Screen) async -> EngineResult {
        let messages = PromptComposer.commandMessages(context: Self.context(screen), transcript: testCase.command)
        let start = Date()
        let response: String
        do {
            response = try await endpoint.complete(system: messages.system, user: messages.user, temperature: 0)
        } catch {
            return EngineResult(actions: nil, note: error.localizedDescription,
                                latencyMs: Date().timeIntervalSince(start) * 1000, raw: "")
        }
        let latency = Date().timeIntervalSince(start) * 1000
        switch CommandParser.parse(response) {
        case .success(let steps):
            return EngineResult(actions: steps.map(Self.action), latencyMs: latency, raw: response)
        case .failure(.forbidden(let key)):
            // The app runs nothing and says so: the outcome is "no action".
            return EngineResult(actions: [], note: "blocked: \(key)", latencyMs: latency, raw: response)
        case .failure:
            return EngineResult(actions: [], note: "invalid response", latencyMs: latency, raw: response)
        }
    }

    /// The context the app builds in `runCommand`, from the screen and the default profiles.
    public static func context(_ screen: Screen) -> PromptComposer.CommandContext {
        let profile = Profile.defaults.first { $0.id == screen.profile } ?? Profile.defaults[Profile.defaults.count - 1]
        let intents = profile.intents.filter { $0.value != .none }.keys.sorted() + (screen.extraIntents ?? [])
        return PromptComposer.CommandContext(
            appName: screen.app, language: screen.language ?? "auto", channels: screen.channels ?? [],
            slots: profile.slots.map(\.name), intents: intents, selection: screen.selection,
            hints: profile.interaction.commandHints)
    }

    /// The same step in the agent's vocabulary.
    public static func action(_ step: CommandStep) -> EvalAction {
        switch step {
        case .text(let text): return EvalAction(tool: "type_text", args: ["text": text])
        case .keys(let keys): return EvalAction(tool: "press_keys", keys: keys)
        case .replaceSelection(let text): return EvalAction(tool: "replace_selection", args: ["text": text])
        case .switchChannel(let name): return EvalAction(tool: "switch_channel", args: ["name": name])
        case .runSlot(let name): return EvalAction(tool: "run_skill", args: ["name": name])
        case .intent(let name): return EvalAction(tool: "run_intent", args: ["name": name])
        }
    }
}
