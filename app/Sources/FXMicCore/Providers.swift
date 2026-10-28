import Foundation

/// Known OpenAI-compatible servers (TDD voice command agent §3.1). A preset fills in the URL and
/// says which request fields the server accepts; the user can still edit the URL.
public enum ProviderPreset: String, Codable, CaseIterable, Sendable {
    case ollama, lmstudio, openai, anthropic, openrouter, custom

    public var label: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom"
        }
    }

    public var defaultURL: String {
        switch self {
        case .ollama: return "http://localhost:11434/v1"
        case .lmstudio: return "http://localhost:1234/v1"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return "http://localhost:8080/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .ollama: return "qwen3.5:4b"
        case .openai: return "gpt-6.1-terra"
        case .anthropic: return "claude-haiku-5-5"
        default: return ""
        }
    }

    /// Recent models offered in the Settings menu, newest first. Only a shortcut: the model field
    /// takes any string, so models newer than this list still work.
    public var suggestedModels: [String] {
        switch self {
        case .openai:
            return ["gpt-6-astra", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-6-sol",
                    "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        case .anthropic:
            return ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5",
                    "claude-fable-5", "claude-opus-5", "claude-sonnet-5"]
        default:
            return []
        }
    }

    public var needsKey: Bool { [.openai, .anthropic, .openrouter].contains(self) }

    /// Anthropic's own API requires `max_tokens`: sent when the caller gives none.
    public var defaultMaxTokens: Int? { self == .anthropic ? 4096 : nil }

    /// Claude 4.7 and later reject a temperature below 1 on the compatibility layer: not sent.
    public var sendsTemperature: Bool { self != .anthropic }

    /// `reasoning_effort: "none"` turns thinking off on Ollama (0.7 s instead of 54 s). Other
    /// servers ignore it or reject it on models without reasoning, so it is not sent there.
    public var canDisableThinking: Bool { self == .ollama || self == .custom }
}

/// One saved server. The API key is not here: `apiKeyRef` names its Keychain item.
public struct LLMProvider: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var preset: ProviderPreset
    public var name: String
    public var baseURL: String
    public var apiKeyRef: String?
    /// e.g. `anthropic-workspace-id` for keys not scoped to a workspace.
    public var extraHeaders: [String: String] = [:]

    public init(id: String, preset: ProviderPreset, name: String? = nil, baseURL: String? = nil,
                apiKeyRef: String? = nil, extraHeaders: [String: String] = [:]) {
        self.id = id
        self.preset = preset
        self.name = name ?? preset.label
        self.baseURL = baseURL ?? preset.defaultURL
        self.apiKeyRef = apiKeyRef
        self.extraHeaders = extraHeaders
    }

    public static let ollama = LLMProvider(id: "ollama", preset: .ollama, name: "Ollama (this Mac)")

    /// A new provider from a preset, with an id not used by `existing`.
    public static func make(_ preset: ProviderPreset, existing: [LLMProvider]) -> LLMProvider {
        var id = preset.rawValue
        var n = 2
        while existing.contains(where: { $0.id == id }) { id = "\(preset.rawValue)-\(n)"; n += 1 }
        return LLMProvider(id: id, preset: preset, apiKeyRef: preset.needsKey ? "fxmic.llm.\(id)" : nil)
    }

    /// True when the server is on this Mac (TDD §4: warn otherwise).
    public var isLocal: Bool {
        guard let host = URL(string: baseURL)?.host else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
    }
}

extension LLMProvider {
    private enum CodingKeys: String, CodingKey { case id, preset, name, baseURL, apiKeyRef, extraHeaders }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let preset = (try? c.decodeIfPresent(ProviderPreset.self, forKey: .preset)) ?? .custom
        let id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? preset.rawValue
        self.init(id: id, preset: preset,
                  name: try? c.decodeIfPresent(String.self, forKey: .name),
                  baseURL: try? c.decodeIfPresent(String.self, forKey: .baseURL),
                  apiKeyRef: try? c.decodeIfPresent(String.self, forKey: .apiKeyRef),
                  extraHeaders: (try? c.decodeIfPresent([String: String].self, forKey: .extraHeaders)) ?? [:])
    }
}
