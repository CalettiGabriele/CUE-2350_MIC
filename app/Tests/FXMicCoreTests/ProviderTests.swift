import Foundation
import Testing
@testable import FXMicCore

@Suite struct ProviderConfigTests {
    @Test func defaultsAreOllamaOnThisMac() {
        let llm = AppConfig().llm
        #expect(llm.providers == [.ollama])
        #expect(llm.active.baseURL == "http://localhost:11434/v1")
        #expect(llm.isLocal)
        #expect(AppConfig().schemaVersion == 4)
    }

    @Test func schema3OllamaURLBecomesTheOllamaProvider() throws {
        let json = #"{"schemaVersion": 3, "llm": {"baseURL": "http://localhost:11434/v1/", "model": "qwen3:4b"}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.llm.providers == [.ollama])
        #expect(config.llm.model == "qwen3:4b")
        #expect(config.schemaVersion == 4)
    }

    @Test func schema3OtherURLBecomesCustom() throws {
        let json = #"{"llm": {"baseURL": "http://192.168.1.5:1234/v1", "model": "m"}}"#
        let llm = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).llm
        #expect(llm.active.preset == .custom)
        #expect(llm.active.baseURL == "http://192.168.1.5:1234/v1")
        #expect(!llm.isLocal)
    }

    @Test func roundTripKeepsProvidersAndDropsTheOldURL() throws {
        var config = AppConfig()
        config.llm.providers.append(LLMProvider.make(.anthropic, existing: config.llm.providers))
        config.llm.activeProvider = "anthropic"
        config.llm.active.extraHeaders = ["anthropic-workspace-id": "ws"]
        let data = try JSONEncoder().encode(config)
        let llmJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((llmJSON?["llm"] as? [String: Any])?["baseURL"] == nil)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(back == config)
        #expect(back.llm.active.apiKeyRef == "fxmic.llm.anthropic")
        #expect(!back.llm.isLocal)
    }

    @Test func unknownActiveFallsBackToTheFirstAndDuplicatesAreDropped() throws {
        let json = #"{"llm": {"providers": [{"id": "a", "preset": "openai"}, {"id": "a", "preset": "ollama"}], "activeProvider": "zzz"}}"#
        let llm = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).llm
        #expect(llm.providers.count == 1)
        #expect(llm.active.id == "a")
        #expect(llm.active.baseURL == "https://api.openai.com/v1")
    }

    @Test func newProvidersGetFreeIds() {
        let first = LLMProvider.make(.openai, existing: [.ollama])
        let second = LLMProvider.make(.openai, existing: [.ollama, first])
        #expect(first.id == "openai")
        #expect(second.id == "openai-2")
        #expect(second.apiKeyRef == "fxmic.llm.openai-2")
        #expect(LLMProvider.make(.lmstudio, existing: []).apiKeyRef == nil)
    }
}

@Suite struct OpenAICompatibleClientTests {
    let echo = ToolSpec(name: "echo", description: "Repeats.", inputSchema: .object(["type": .string("object")]))

    func client(_ preset: ProviderPreset) -> OpenAICompatibleClient {
        OpenAICompatibleClient(provider: LLMProvider(id: "p", preset: preset), model: "m", apiKey: "k",
                               timeoutMs: 1000, disableThinking: true)
    }

    @Test func ollamaGetsReasoningOffAndTemperature() {
        let body = client(.ollama).body([.user("hi")], tools: [echo], temperature: 0, maxTokens: nil)
        #expect(body["reasoning_effort"] as? String == "none")
        #expect(body["temperature"] as? Double == 0)
        #expect(body["tool_choice"] as? String == "auto")
        let tools = body["tools"] as? [[String: Any]]
        #expect((tools?.first?["function"] as? [String: Any])?["name"] as? String == "echo")
    }

    @Test func anthropicGetsNeitherTemperatureNorReasoning() {
        let body = client(.anthropic).body([.user("hi")], tools: [], temperature: 0.2, maxTokens: 10)
        #expect(body["temperature"] == nil)
        #expect(body["reasoning_effort"] == nil)
        #expect(body["tools"] == nil)
        #expect(body["tool_choice"] == nil)
        #expect(body["max_tokens"] as? Int == 10)
        #expect(client(.anthropic).body([.user("hi")], tools: [], temperature: nil, maxTokens: nil)["max_tokens"] as? Int == 4096)
        #expect(client(.ollama).body([.user("hi")], tools: [], temperature: nil, maxTokens: nil)["max_tokens"] == nil)
    }

    @Test func toolMessagesGoOnTheWire() {
        let call = ToolCall(id: "c1", name: "echo", arguments: #"{"word":"ok"}"#)
        let assistant = OpenAICompatibleClient.wire(ChatMessage(role: .assistant, content: nil, toolCalls: [call]))
        #expect(assistant["content"] is NSNull)
        #expect((assistant["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "c1")
        let result = OpenAICompatibleClient.wire(.tool(callID: "c1", "ok"))
        #expect(result["role"] as? String == "tool")
        #expect(result["tool_call_id"] as? String == "c1")
    }

    @Test func parsesToolCallsTextAndUsage() throws {
        let json = #"""
        {"choices": [{"finish_reason": "tool_calls", "message": {"role": "assistant", "content": "<think>x</think>",
          "tool_calls": [{"id": "a", "type": "function", "function": {"name": "echo", "arguments": "{\"word\":\"ok\"}"}},
                         {"type": "function", "function": {"name": "finish", "arguments": {"summary": "done"}}}]}}],
         "usage": {"prompt_tokens": 12, "completion_tokens": 3}}
        """#
        let response = try OpenAICompatibleClient.parse(Data(json.utf8))
        #expect(response.text == "")
        #expect(response.toolCalls.map(\.name) == ["echo", "finish"])
        #expect(response.toolCalls[1].id == "call_1")
        #expect(JSONValue(json: response.toolCalls[1].arguments)?["summary"]?.stringValue == "done")
        #expect(response.promptTokens == 12)
        #expect(response.finishReason == "tool_calls")
    }

    @Test func errorMessagesAreRead() {
        let data = Data(#"{"error": {"message": "model not found"}}"#.utf8)
        #expect(OpenAICompatibleClient.errorMessage(data) == "model not found")
    }

    @Test func providersThatNeedAKeyFailWithoutOne() async {
        var c = client(.openai)
        c.apiKey = nil
        await #expect(throws: OpenAICompatibleClient.Failure.missingKey) {
            _ = try await c.send([.user("hi")], tools: [], temperature: nil, maxTokens: nil)
        }
    }

    @Test func jsonValueRoundTrips() throws {
        let value = JSONValue(json: #"{"a": [1, true, null, "x"], "b": {"c": 2.5}}"#)
        #expect(value?["a"] == .array([.number(1), .bool(true), .null, .string("x")]))
        #expect(JSONValue(json: value!.jsonString) == value)
        #expect(JSONValue(json: "not json") == nil)
    }
}
