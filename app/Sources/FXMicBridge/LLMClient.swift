import FXMicCore
import Foundation
import os

/// Minimal client for an OpenAI-compatible `/chat/completions` endpoint (Ollama, LM Studio,
/// llama.cpp server). TDD §3.4.
struct LLMClient {
    let settings: AppConfig.LLM
    private let log = Logger(subsystem: "com.fxmicbridge", category: "llm")

    enum Failure: LocalizedError {
        case badURL, http(Int), empty
        var errorDescription: String? {
            switch self {
            case .badURL: return L.t("Invalid LLM endpoint URL")
            case .http(let code): return L.f("LLM: HTTP error %d", code)
            case .empty: return L.t("LLM: empty response")
            }
        }
    }

    /// `temperature` overrides the configured one (e.g. 0 for deterministic commands).
    func complete(system: String, user: String, maxTokens: Int? = nil, temperature: Double? = nil) async throws -> String {
        guard let url = URL(string: settings.baseURL)?.appendingPathComponent("chat/completions") else {
            throw Failure.badURL
        }
        var request = URLRequest(url: url, timeoutInterval: settings.timeoutMs / 1000)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": settings.model,
            "temperature": temperature ?? settings.temperature,
            "stream": false,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        if let maxTokens { body["max_tokens"] = maxTokens }
        if settings.disableThinking {
            // Measured with Ollama 0.34.4 + qwen3.5:4b: 0.7 s instead of 54 s. Ollama's own
            // `think: false` is ignored on the OpenAI-compatible endpoint, so it is not sent.
            body["reasoning_effort"] = "none"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = ((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        let text = PromptComposer.clean(content ?? "")
        log.notice("llm \(settings.model, privacy: .public) answered in \(Date().timeIntervalSince(start) * 1000, format: .fixed(precision: 0), privacy: .public) ms")
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    /// Loads the model into memory ahead of the first dictation (Ollama keeps it ~5 min).
    func warmUp() {
        Task.detached { [self] in
            _ = try? await complete(system: "Reply only: ok", user: "ok", maxTokens: 1)
        }
    }

    /// Lists model ids from `/models`, or nil if the server is not reachable.
    func availableModels() async -> [String]? {
        guard let url = URL(string: settings.baseURL)?.appendingPathComponent("models") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 2)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return nil }
        return list.compactMap { $0["id"] as? String }
    }
}
