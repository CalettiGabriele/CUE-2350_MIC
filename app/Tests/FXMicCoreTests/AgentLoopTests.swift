import Foundation
import Testing
@testable import FXMicCore

// MARK: - Fakes

/// Answers with the scripted responses in order and records what it was sent.
final class ScriptedProvider: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<ChatResponse, Error>]
    private(set) var received: [[ChatMessage]] = []
    /// Called on every request, e.g. to move the fake clock.
    var onSend: (@Sendable () -> Void)?

    init(_ responses: [ChatResponse]) { self.responses = responses.map { .success($0) } }
    init(results: [Result<ChatResponse, Error>]) { responses = results }

    func send(_ messages: [ChatMessage], tools: [ToolSpec], temperature: Double?, maxTokens: Int?) async throws -> ChatResponse {
        onSend?()
        let next: Result<ChatResponse, Error> = lock.withLock {
            received.append(messages)
            return responses.isEmpty ? .success(ChatResponse(text: "", toolCalls: [read()])) : responses.removeFirst()
        }
        return try next.get()
    }

    var calls: Int { lock.withLock { received.count } }
    var lastMessages: [ChatMessage] { lock.withLock { received.last ?? [] } }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms = 0.0
    func now() -> Double { lock.withLock { ms } }
    func advance(_ by: Double) { lock.withLock { ms += by } }
}

final class TestTool: AgentTool, @unchecked Sendable {
    let spec: ToolSpec
    let risk: Risk
    private let lock = NSLock()
    private var results: [ToolResult]
    private(set) var arguments: [JSONValue] = []

    init(_ name: String, risk: Risk = .safe, results: [ToolResult] = [.ok()], schema: JSONValue? = nil) {
        spec = ToolSpec(name: name, description: name,
                        inputSchema: schema ?? Schema.object(["text": Schema.string("text")]))
        self.risk = risk
        self.results = results
    }

    func risk(for arguments: JSONValue) -> Risk {
        arguments["text"]?.stringValue == "Delete" ? .risky : risk
    }

    func run(_ arguments: JSONValue, context: ToolContext) async -> ToolResult {
        lock.withLock {
            self.arguments.append(arguments)
            return results.count > 1 ? results.removeFirst() : results[0]
        }
    }

    var runs: Int { lock.withLock { arguments.count } }
}

private var callCounter = 0
func call(_ name: String, _ arguments: String = "{}") -> ToolCall {
    callCounter += 1
    return ToolCall(id: "c\(callCounter)", name: name, arguments: arguments)
}
func read() -> ToolCall { call("look") }
func finish(_ summary: String = "Done", status: String = "done") -> ToolCall {
    call("finish", #"{"summary": "\#(summary)", "status": "\#(status)"}"#)
}
func answer(_ calls: ToolCall...) -> ChatResponse { ChatResponse(text: "", toolCalls: calls) }

// MARK: - Loop

@Suite struct AgentLoopTests {
    let screen = ScreenContext(app: "Mail", selection: "we need it by Friday")

    func loop(_ provider: ChatProvider, _ tools: [AgentTool], limits: AgentLimits = AgentLimits(),
              dryRun: Bool = false, confirm: Bool = true, clock: FakeClock? = nil,
              events: (@Sendable (AgentEvent) -> Void)? = nil) -> AgentLoop {
        var loop = AgentLoop(provider: provider, registry: ToolRegistry(tools), limits: limits,
                             context: ToolContext(dryRun: dryRun), confirm: { _ in confirm },
                             progress: events ?? { _ in })
        if let clock { loop.clock = { clock.now() } }
        return loop
    }

    @Test func actionAndFinishInOneAnswerTakeOneCall() async {
        let type = TestTool("type_text")
        let provider = ScriptedProvider([answer(call("type_text", #"{"text": "ciao"}"#), finish("Typed"))])
        let run = await loop(provider, [type]).run(screen, command: "scrivi ciao")
        #expect(run.outcome == .done("Typed"))
        #expect(run.modelCalls == 1)
        #expect(type.arguments == [.object(["text": .string("ciao")])])
        #expect(run.path == "type_text → finish")
    }

    @Test func actionsThatWorkEndTheCommandWithoutFinish() async {
        let keys = TestTool("press_keys")
        let provider = ScriptedProvider([answer(call("press_keys", #"{"text": "shift+return"}"#))])
        let run = await loop(provider, [keys]).run(screen, command: "vai a capo")
        #expect(run.outcome == .done("press_keys «shift+return»"))
        #expect(run.modelCalls == 1)
    }

    @Test func continueShowsTheResultsAndReadOnlyCallsGoOn() async {
        let look = TestTool("look", risk: .read, results: [.ok("field: hello")])
        let type = TestTool("type_text")
        let provider = ScriptedProvider([
            answer(call("look")),                                          // read only: go on
            answer(call("type_text", #"{"text": "hi"}"#), call("continue")), // asked to see the result
            answer(finish("Checked")),
        ])
        let run = await loop(provider, [look, type]).run(screen, command: "x")
        #expect(run.outcome == .done("Checked"))
        #expect(run.modelCalls == 3)
    }

    @Test func aServerErrorIsTriedOnceMore() async {
        let provider = ScriptedProvider(results: [
            .failure(OpenAICompatibleClient.Failure.http(500, "XML syntax error")),
            .success(answer(finish("Done"))),
        ])
        let run = await loop(provider, []).run(screen, command: "x")
        #expect(run.outcome == .done("Done"))
        let twice = ScriptedProvider(results: [.failure(OpenAICompatibleClient.Failure.http(500, nil)),
                                               .failure(OpenAICompatibleClient.Failure.http(502, nil))])
        #expect(await loop(twice, []).run(screen, command: "x").outcome == .failed("LLM: HTTP error 502"))
        let notFound = ScriptedProvider(results: [.failure(OpenAICompatibleClient.Failure.http(404, nil))])
        _ = await loop(notFound, []).run(screen, command: "x")
        #expect(notFound.calls == 1)
    }

    @Test func aFailedActionNextToFinishLetsTheModelFixIt() async {
        let select = TestTool("select_text", results: [.failed("text not found: urgnet"), .ok("selected")])
        let provider = ScriptedProvider([
            answer(call("select_text", #"{"text": "urgnet"}"#), finish()),
            answer(call("select_text", #"{"text": "urgent"}"#), finish("Selected")),
        ])
        let run = await loop(provider, [select]).run(screen, command: "select urgent")
        #expect(run.outcome == .done("Selected"))
        #expect(run.modelCalls == 2)
        let toolMessages = provider.lastMessages.filter { $0.role == .tool }.compactMap(\.content)
        #expect(toolMessages.contains("error: text not found: urgnet"))
    }

    @Test func everyToolCallGetsAnAnswerWithItsID() async {
        // A failed call keeps the loop going, so the second request shows the answers to the first.
        let provider = ScriptedProvider([answer(call("nope"), finish()), answer(finish())])
        _ = await loop(provider, []).run(screen, command: "x")
        let sent = provider.lastMessages
        let assistant = sent.first { $0.role == .assistant }!
        let answered = Set(sent.filter { $0.role == .tool }.compactMap(\.toolCallID))
        #expect(Set(assistant.toolCalls.map(\.id)) == answered)
    }

    @Test func unknownToolsAndBadArgumentsAreReportedNotRun() async {
        let tool = TestTool("format_selection", schema: Schema.object(
            ["style": Schema.string("style", oneOf: ["bold", "italic"])], required: ["style"]))
        let provider = ScriptedProvider([
            answer(call("click_everything"), call("format_selection", #"{"style": "huge"}"#),
                   call("format_selection", "{not json"), call("format_selection", "{}")),
            answer(finish("No", status: "cannot")),
        ])
        let run = await loop(provider, [tool]).run(screen, command: "x")
        #expect(tool.runs == 0)
        #expect(run.outcome == .cannot("No"))
        let errors = provider.lastMessages.filter { $0.role == .tool }.compactMap(\.content)
        #expect(errors == ["error: unknown tool click_everything",
                           "error: invalid arguments: style must be one of: bold, italic",
                           "error: arguments are not valid JSON",
                           "error: invalid arguments: missing style"])
    }

    @Test func riskyCallsAreConfirmedAndTheWaitIsNotCounted() async {
        let clock = FakeClock()
        let click = TestTool("click", risk: .safe)
        let provider = ScriptedProvider([answer(call("click", #"{"text": "Delete"}"#))])
        provider.onSend = { clock.advance(1000) }
        var loop = loop(provider, [click], limits: AgentLimits(timeBudgetMs: 5000), clock: clock)
        loop.confirm = { pending in
            #expect(pending.tool == "click")
            clock.advance(60000)
            return true
        }
        let run = await loop.run(screen, command: "click delete")
        #expect(click.runs == 1)
        #expect(run.outcome == .done("click «Delete»"))
    }

    @Test func aDeclinedCallIsNotRunAndTheModelIsTold() async {
        let click = TestTool("click", risk: .risky)
        let provider = ScriptedProvider([answer(call("click", #"{"text": "Send"}"#), finish()),
                                         answer(finish("Not sent", status: "cannot"))])
        let run = await loop(provider, [click], confirm: false).run(screen, command: "send")
        #expect(click.runs == 0)
        #expect(run.outcome == .cannot("Not sent"))
        #expect(provider.lastMessages.contains { $0.content == "error: the user declined this action" })
    }

    @Test func stepsRunOut() async {
        let look = TestTool("look", risk: .read)
        let provider = ScriptedProvider([])   // always calls look
        let run = await loop(provider, [look], limits: AgentLimits(maxSteps: 3)).run(screen, command: "x")
        #expect(run.outcome == .budget)
        #expect(run.modelCalls == 3)
        #expect(look.runs == 3)
    }

    @Test func timeRunsOut() async {
        let clock = FakeClock()
        let provider = ScriptedProvider([])
        provider.onSend = { clock.advance(20000) }
        let run = await loop(provider, [TestTool("look", risk: .read)], limits: AgentLimits(timeBudgetMs: 30000),
                             clock: clock).run(screen, command: "x")
        #expect(run.outcome == .budget)
        #expect(run.modelCalls == 2)
    }

    @Test func cancellingStopsTheLoop() async {
        let provider = ScriptedProvider([])
        let task = Task { await loop(provider, [TestTool("look", risk: .read)]).run(screen, command: "x") }
        task.cancel()
        let run = await task.value
        #expect(run.outcome == .cancelled)
    }

    @Test func providerErrorsEndTheRun() async {
        struct Down: LocalizedError { var errorDescription: String? { "Server unreachable" } }
        let provider = ScriptedProvider(results: [.failure(Down())])
        let run = await loop(provider, []).run(screen, command: "x")
        #expect(run.outcome == .failed("Server unreachable"))
    }

    @Test func aTextAnswerEndsTheLoop() async {
        let none = await loop(ScriptedProvider([ChatResponse(text: "It is sunny.")]), []).run(screen, command: "weather?")
        #expect(none.outcome == .cannot("It is sunny."))
        let type = TestTool("type_text")
        let after = await loop(ScriptedProvider([answer(call("type_text", #"{"text": "a"}"#), call("continue")),
                                                 ChatResponse(text: "Typed.")]),
                               [type]).run(screen, command: "write a")
        #expect(after.outcome == .done("Typed."))
    }

    @Test func aDryRunOnlyRunsReadTools() async {
        let look = TestTool("look", risk: .read, results: [.ok("2 buttons")])
        let send = TestTool("send", risk: .risky)
        let provider = ScriptedProvider([answer(call("look"), call("send", #"{"text": "x"}"#), finish())])
        let run = await loop(provider, [look, send], dryRun: true, confirm: false).run(screen, command: "x")
        #expect(look.runs == 1)
        #expect(send.runs == 0)
        #expect(run.outcome == .done("Done"))
        #expect(run.trace.map(\.result) == ["2 buttons", "ok (simulated)", "Done"])
    }

    @Test func progressReportsStepsAndRuns() async {
        let log = EventLog()
        let provider = ScriptedProvider([answer(call("type_text", #"{"text": "hi"}"#), finish())])
        _ = await loop(provider, [TestTool("type_text")], events: { log.add($0) }).run(screen, command: "x")
        #expect(log.events == [.thinking(step: 1), .running(step: 1, summary: "type_text «hi»"),
                               .ran(step: 1, summary: "type_text «hi»", ok: true)])
    }

    @Test func theFirstRequestHasTheFixedPromptTheContextAndAllTools() async {
        let provider = ScriptedProvider([answer(finish())])
        _ = await loop(provider, [TestTool("type_text")]).run(screen, command: "make it bold")
        let first = provider.received[0]
        #expect(first[0] == .system(AgentPrompt.system))
        #expect(first[1].content?.hasSuffix("COMMAND\nmake it bold") == true)
        #expect(first[1].content?.contains("selection: \"\"\"\nwe need it by Friday\n\"\"\"") == true)
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { list.append(e) } }
    var events: [AgentEvent] { lock.withLock { list } }
}

// MARK: - Registry, schema, prompt, settings

@Suite struct AgentToolsTests {
    @Test func registryKeepsTheFirstValidEnabledName() {
        let first = TestTool("type_text")
        let registry = ToolRegistry([first, TestTool("type_text"), TestTool("Bad Name"), TestTool("open_url")],
                                    disabled: ["open_url"])
        #expect(registry.specs.map(\.name) == ["type_text"])
        #expect((registry.tool(named: "type_text") as? TestTool) === first)
    }

    @Test func overridesChangeTheLevelButNotAnEscalation() {
        let click = TestTool("click", risk: .safe)
        let lowered = ToolRegistry([click], riskOverrides: ["click": .read])
        #expect(lowered.risk(of: click, arguments: .object(["text": .string("Share")])) == .read)
        #expect(lowered.risk(of: click, arguments: .object(["text": .string("Delete")])) == .risky)
        let raised = ToolRegistry([click], riskOverrides: ["click": .risky])
        #expect(raised.risk(of: click, arguments: .object(["text": .string("Share")])) == .risky)
    }

    @Test func schemaValidation() {
        let schema = Schema.object(["keys": Schema.strings("keys"), "n": .object(["type": .string("integer")])],
                                   required: ["keys"])
        #expect(SchemaValidator.validate(.object(["keys": .array([.string("cmd+a")])]), against: schema) == nil)
        #expect(SchemaValidator.validate(.object([:]), against: schema) == "missing keys")
        #expect(SchemaValidator.validate(.object(["keys": .string("cmd+a")]), against: schema) == "keys must be an array")
        #expect(SchemaValidator.validate(.object(["keys": .array([.number(1)])]), against: schema) == "keys[0] must be a string")
        #expect(SchemaValidator.validate(.object(["keys": .array([]), "n": .number(1.5)]), against: schema) == "n must be a integer")
        #expect(SchemaValidator.validate(.object(["keys": .array([]), "x": .null]), against: schema) == "unknown argument x")
        #expect(SchemaValidator.validate(.string("a"), against: schema) == "arguments must be an object")
    }

    @Test func promptsAreEnglishAndTheFinishToolIsValid() {
        // Project rule: every prompt is written in English: no letters outside ASCII (typographic
        // marks such as › and … in menu paths are fine).
        let ascii = (AgentPrompt.system + AgentPrompt.finish.description).unicodeScalars
            .filter(\.properties.isAlphabetic).allSatisfy(\.isASCII)
        #expect(ascii)
        #expect(ToolRegistry.isValidName(AgentPrompt.finish.name))
        #expect(SchemaValidator.validate(.object(["summary": .string("ok"), "status": .string("done")]),
                                         against: AgentPrompt.finish.inputSchema) == nil)
    }

    @Test func userMessageShowsWhatIsMissing() {
        let text = AgentPrompt.user(ScreenContext(app: "Terminal", channel: "Codex · fxmic", textFormat: "plain",
                                                  channels: ["Codex · fxmic"], skills: ["/review"]), command: "run the review")
        #expect(text.contains("app: Terminal\nchannel: Codex · fxmic"))
        #expect(text.contains("selection: (none)"))
        #expect(text.contains("intents: (none)"))
        #expect(text.contains("skills: \"/review\""))
        #expect(text.hasSuffix("COMMAND\nrun the review"))
    }

    @Test func agentSettingsDefaultAndClamp() throws {
        #expect(AppConfig().agent.maxSteps == 8)
        // "engine" is from the preview (phases 3–6): ignored now that the agent is the only path.
        let json = #"{"agent": {"engine": "legacy", "maxSteps": 500, "timeBudgetMs": 10, "riskOverrides": {"click": "risky"}}}"#
        let agent = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).agent
        #expect(agent.maxSteps == 30)
        #expect(agent.timeBudgetMs == 2000)
        #expect(agent.riskOverrides == ["click": .risky])
        let roundTrip = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(AppConfig()))
        #expect(roundTrip == AppConfig())
    }
}

// MARK: - Parity tools

final class MacLog: MacActions, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    var calls: [String] { lock.withLock { list } }
    private func add(_ s: String) -> ToolResult { lock.withLock { list.append(s) }; return .ok() }
    func typeText(_ text: String) async -> ToolResult { add("type \(text)") }
    func pressKeys(_ keys: [String]) async -> ToolResult { add("keys " + keys.joined(separator: " ")) }
    func replaceSelection(_ text: String) async -> ToolResult { add("replace \(text)") }
    func switchChannel(_ name: String) async -> ToolResult { add("channel \(name)") }
    func runSkill(_ name: String) async -> ToolResult { add("skill \(name)") }
    func runIntent(_ name: String) async -> ToolResult { add("intent \(name)") }
    var selected: String?
    func readFocusedText() async -> ToolResult { .ok("field text:\nhello") }
    func selectText(_ text: String, occurrence: Int) async -> ToolResult {
        selected = text
        return add("select \(text) \(occurrence)")
    }
    func currentSelection() async -> String? { selected }
}

@Suite struct BuiltInToolsTests {
    let screen = ScreenContext(app: "Claude", channels: ["Claude · api-project", "Codex · fxmic-bridge"],
                               skills: ["/review"], intents: ["interrupt", "newSession"])

    func tool(_ name: String, _ mac: MacActions, screen: ScreenContext? = nil) -> AgentTool {
        BuiltInTools.standard(mac, screen: screen ?? self.screen).first { $0.spec.name == name }!
    }

    @Test func theSetHasStableNamesAndValidSchemas() {
        let names = BuiltInTools.standard(MacLog(), screen: screen).map(\.spec.name)
        #expect(names == ["type_text", "press_keys", "replace_selection", "switch_channel", "run_skill", "run_intent",
                          "read_focused_text", "select_text", "format_selection"])
        // The descriptions are prompt text: English only (project rule), plain ASCII.
        let text = BuiltInTools.standard(MacLog(), screen: screen).map(\.spec.description).joined()
        let ascii = text.unicodeScalars.allSatisfy(\.isASCII)
        #expect(ascii)
    }

    @Test func keysAreCheckedBeforeAnythingIsPressed() async {
        let mac = MacLog()
        let keys = tool("press_keys", mac)
        let bad = await keys.run(.object(["keys": .array([.string("cmd+a"), .string("shift")])]), context: ToolContext())
        #expect(!bad.ok)
        #expect(bad.content.contains("shift is a modifier"))
        let blocked = await keys.run(.object(["keys": .array([.string("cmd+q")])]), context: ToolContext())
        #expect(blocked.content.contains("blocked"))
        #expect(mac.calls.isEmpty)
        let good = await keys.run(.object(["keys": .array([.string("cmd+a"), .string("delete")])]), context: ToolContext())
        #expect(good.ok)
        #expect(mac.calls == ["keys cmd+a delete"])
    }

    @Test func namesResolveAndUnknownOnesListTheChoices() async {
        let mac = MacLog()
        _ = await tool("switch_channel", mac).run(.object(["name": .string("codex")]), context: ToolContext())
        #expect(mac.calls == ["channel Codex · fxmic-bridge"])
        let missing = await tool("run_skill", mac).run(.object(["name": .string("deploy")]), context: ToolContext())
        #expect(missing.content == "no skill called deploy; the skills are: /review")
        // Intents match exactly: "stop" must not pick one.
        let stop = await tool("run_intent", mac).run(.object(["name": .string("stop")]), context: ToolContext())
        #expect(!stop.ok)
        _ = await tool("run_intent", mac).run(.object(["name": .string("Interrupt")]), context: ToolContext())
        #expect(mac.calls.last == "intent interrupt")
    }

    @Test func replacingNeedsASelection() async {
        let mac = MacLog()
        let none = await tool("replace_selection", mac).run(.object(["text": .string("x")]), context: ToolContext())
        #expect(none.content == "nothing is selected")
        var selected = screen
        selected.selection = "ciao"
        let ok = await tool("replace_selection", mac, screen: selected).run(.object(["text": .string("hello")]), context: ToolContext())
        #expect(ok.ok)
        #expect(mac.calls == ["replace hello"])
    }
}

@Suite struct FormattingToolsTests {
    func tools(_ format: String, selection: String? = nil, mac: MacLog) -> [String: AgentTool] {
        let screen = ScreenContext(app: "Notes", textFormat: format, selection: selection)
        return Dictionary(uniqueKeysWithValues: BuiltInTools.standard(mac, screen: screen).map { ($0.spec.name, $0) })
    }

    @Test func richTextUsesShortcutsAndMarkdownWritesMarks() async {
        let mac = MacLog()
        let rich = tools("rich", selection: "urgent", mac: mac)
        #expect(await rich["format_selection"]!.run(.object(["style": .string("bold")]), context: ToolContext()).ok)
        #expect(mac.calls == ["keys cmd+b"])
        let heading = await rich["format_selection"]!.run(.object(["style": .string("heading")]), context: ToolContext())
        #expect(heading.content.contains("no shortcut"))

        let md = MacLog()
        let markdown = tools("markdown", selection: "milk\neggs", mac: md)
        _ = await markdown["format_selection"]!.run(.object(["style": .string("bullet_list")]), context: ToolContext())
        #expect(md.calls == ["replace - milk\n- eggs"])
        // The replacement dropped the selection: a second format has nothing to work on.
        let again = await markdown["format_selection"]!.run(.object(["style": .string("bold")]), context: ToolContext())
        #expect(again.content.contains("nothing is selected"))

        let plain = await tools("plain", selection: "x", mac: MacLog())["format_selection"]!
            .run(.object(["style": .string("bold")]), context: ToolContext())
        #expect(plain.content.contains("plain text"))
    }

    @Test func selectingFirstMakesFormattingAndReplacingPossible() async {
        let mac = MacLog()
        let set = tools("rich", mac: mac)
        #expect(await set["replace_selection"]!.run(.object(["text": .string("x")]), context: ToolContext()).content
                == "nothing is selected")
        _ = await set["select_text"]!.run(.object(["text": .string("urgent"), "occurrence": .number(-1)]), context: ToolContext())
        #expect(await set["format_selection"]!.run(.object(["style": .string("italic")]), context: ToolContext()).ok)
        #expect(mac.calls == ["select urgent -1", "keys cmd+i"])
    }

    @Test func markdownMarks() {
        #expect(FormatSelectionTool.markdown("a", style: "bold") == "**a**")
        #expect(FormatSelectionTool.markdown("a\nb", style: "numbered_list") == "1. a\n2. b")
        #expect(FormatSelectionTool.markdown("a", style: "underline") == nil)
    }

    @Test func profilesHaveATextFormat() throws {
        #expect(Profile.defaults.map(\.textFormat) == [.markdown, .plain, .rich])
        let json = #"{"schemaVersion": 4, "profiles": [{"id": "default", "name": "G", "textFormat": "markdown"}, {"id": "mine", "name": "M"}]}"#
        let profiles = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).profiles
        #expect(profiles.map(\.textFormat) == [.markdown, .rich])
    }
}

@Suite struct PreparingToolsTests {
    @Test func aSelectionAloneDoesNotEndTheCommand() async {
        let mac = MacLog()
        let screen = ScreenContext(app: "Mail", textFormat: "rich", fieldText: "the budget is urgent")
        let provider = ScriptedProvider([
            answer(call("select_text", #"{"text": "urgent"}"#)),
            answer(call("format_selection", #"{"style": "bold"}"#)),
        ])
        let loop = AgentLoop(provider: provider, registry: ToolRegistry(BuiltInTools.standard(mac, screen: screen)),
                             limits: AgentLimits(), confirm: { _ in true })
        let run = await loop.run(screen, command: "make urgent bold")
        #expect(provider.calls == 2)
        #expect(mac.calls == ["select urgent 1", "keys cmd+b"])
        #expect(run.outcome == .done("bold"))
    }
}

extension PreparingToolsTests {
    @Test func selectingWithKeysDoesNotEndTheCommandButOtherKeysDo() {
        let keys = BuiltInTools.standard(MacLog(), screen: ScreenContext(app: "Mail")).first { $0.spec.name == "press_keys" }!
        func prepares(_ list: [String]) -> Bool { keys.prepares(for: .object(["keys": .array(list.map(JSONValue.string))])) }
        #expect(prepares(["cmd+a"]))
        #expect(prepares(["cmd+shift+left"]))
        #expect(!prepares(["cmd+a", "delete"]))
        #expect(!prepares(["shift+return"]))
        #expect(!prepares(["cmd+b"]))
    }
}

// MARK: - Interface tools (phase 5)

final class FakeUI: MacUI, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    var calls: [String] { lock.withLock { list } }
    private func add(_ s: String) -> ToolResult { lock.withLock { list.append(s) }; return .ok() }
    var controls = [UIElementInfo(id: "e1", role: "button", title: "Share"), UIElementInfo(id: "e2", role: "button", title: "Delete"),
                    UIElementInfo(id: "e3", role: "button", title: "Quit")]
    var menus: [String]? = ["File › Export as PDF…", "File › Close Window", "Mail › Quit Mail", "View › Reload Page"]
    func uiElements() async -> [UIElementInfo]? { controls }
    func press(_ id: String) async -> ToolResult { add("press \(id)") }
    func setValue(_ id: String, text: String) async -> ToolResult { add("set \(id) \(text)") }
    func menuItems() async -> [String]? { menus }
    func chooseMenuItem(_ path: String) async -> ToolResult { add("menu \(path)") }
    func windows() async -> [WindowInfo] { [WindowInfo(id: "w1", title: "Re: budget"), WindowInfo(id: "w2", title: "Inbox")] }
    func focusWindow(_ id: String) async -> ToolResult { add("focus \(id)") }
    func closeWindow(_ id: String) async -> ToolResult { add("close \(id)") }
    func openApp(_ name: String) async -> ToolResult { add("open \(name)") }
    func openURL(_ url: URL) async -> ToolResult { add("url \(url.absoluteString)") }
}

@Suite struct InterfaceToolsTests {
    func tools(_ ui: FakeUI, url: Bool = false) -> [String: AgentTool] {
        Dictionary(uniqueKeysWithValues: BuiltInTools.interface(ui, allowOpenURL: url).map { ($0.spec.name, $0) })
    }
    func run(_ tool: AgentTool?, _ args: [String: JSONValue]) async -> ToolResult {
        await tool!.run(.object(args), context: ToolContext())
    }

    @Test func destructiveWordsInSeveralLanguages() {
        #expect(Destructive.isRisky("Delete"))
        #expect(Destructive.isRisky("Elimina conversazione"))
        #expect(Destructive.isRisky("Envoyer"))
        #expect(Destructive.isRisky("Löschen"))
        #expect(Destructive.isRisky("削除"))
        #expect(!Destructive.isRisky("Share"))
        #expect(!Destructive.isRisky("Sender settings"))   // whole words only
        #expect(Destructive.isForbidden("Quit Mail"))
        #expect(!Destructive.isForbidden("Delete"))
    }

    @Test func clicksNeedReadUIAndRiskyTitlesAskFirst() async {
        let ui = FakeUI()
        let set = tools(ui)
        #expect(await run(set["click"], ["element": .string("e1")]).content.contains("call read_ui first"))
        _ = await run(set["read_ui"], [:])
        #expect(set["click"]!.risk(for: .object(["element": .string("e1")])) == .safe)
        #expect(set["click"]!.risk(for: .object(["element": .string("e2")])) == .risky)
        #expect(set["click"]!.summary(for: .object(["element": .string("e2")])) == "click «Delete»")
        #expect(await run(set["click"], ["element": .string("e3")]).content.contains("blocked"))
        _ = await run(set["click"], ["element": .string("E1")])
        #expect(ui.calls == ["press e1"])
    }

    @Test func readUIFiltersAndFallsBackToEverything() async {
        let set = tools(FakeUI())
        #expect(await run(set["read_ui"], ["query": .string("share")]).content == "e1 button «Share»")
        #expect(await run(set["read_ui"], ["query": .string("condividi")]).content.contains("e2 button «Delete»"))
    }

    @Test func menusHideForbiddenItemsAndMatchLoosely() async {
        let ui = FakeUI()
        let set = tools(ui)
        let listed = await run(set["list_menu_items"], [:]).content
        #expect(!listed.contains("Quit"))
        _ = await run(set["choose_menu_item"], ["path": .string("file > export as pdf...")])
        _ = await run(set["choose_menu_item"], ["path": .string("Reload Page")])
        #expect(ui.calls == ["menu File › Export as PDF…", "menu View › Reload Page"])
        #expect(await run(set["choose_menu_item"], ["path": .string("Mail › Quit Mail")]).content.hasPrefix("no menu item"))
        #expect(set["choose_menu_item"]!.risk(for: .object(["path": .string("File › Close Window")])) == .risky)
    }

    @Test func windowsByIdOrTitleAndTheFrontOneIsANoOp() async {
        let ui = FakeUI()
        let set = tools(ui)
        #expect(await run(set["focus_window"], ["window": .string("w1")]).content.contains("already in front"))
        _ = await run(set["focus_window"], ["window": .string("inbox")])
        _ = await run(set["close_window"], [:])
        #expect(ui.calls == ["focus w2", "close w1"])
        #expect(set["close_window"]!.risk == .risky)
    }

    @Test func openURLIsOptInAndLimitedToSomeSchemes() async {
        #expect(tools(FakeUI())["open_url"] == nil)
        let ui = FakeUI()
        let set = tools(ui, url: true)
        #expect(await run(set["open_url"], ["url": .string("file:///etc/passwd")]).content.contains("only http"))
        _ = await run(set["open_url"], ["url": .string("https://example.com")])
        #expect(ui.calls == ["url https://example.com"])
        #expect(set["open_url"]!.risk == .risky)
    }

    @Test func returnSendsInChatsAndTerminalsSoItAsks() {
        func keysTool(_ format: String) -> AgentTool {
            BuiltInTools.standard(MacLog(), screen: ScreenContext(app: "x", textFormat: format)).first { $0.spec.name == "press_keys" }!
        }
        let send: JSONValue = .object(["keys": .array([.string("return")])])
        let newline: JSONValue = .object(["keys": .array([.string("shift+return")])])
        #expect(keysTool("markdown").risk(for: send) == .risky)
        #expect(keysTool("plain").risk(for: send) == .risky)
        #expect(keysTool("rich").risk(for: send) == .safe)
        #expect(keysTool("markdown").risk(for: newline) == .safe)
    }
}

// MARK: - User tools (phase 6)

final class RunnerLog: UserToolRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    var calls: [String] { lock.withLock { list } }
    func runMacro(_ steps: [Action]) async -> ToolResult {
        lock.withLock {
            list.append(steps.map { step -> String in
                switch step {
                case .key(let k): return "key " + k.joined(separator: " ")
                case .text(let t): return "text " + t
                default: return "?"
                }
            }.joined(separator: " | "))
        }
        return .ok()
    }
    func runShortcut(_ name: String, input: String?, returnsOutput: Bool) async -> ToolResult {
        lock.withLock { list.append("shortcut \(name) \(input ?? "-") \(returnsOutput)") }
        return .ok("output")
    }
}

@Suite struct UserToolsTests {
    @Test func namesBecomeSafeToolNames() {
        #expect(UserTool(kind: .macro, name: "Sign e-mail", description: "x").toolName == "user_sign_e_mail")
        #expect(UserTool(kind: .macro, name: "Firma più veloce", description: "x").toolName == "user_firma_piu_veloce")
        #expect(UserTool(kind: .macro, name: "user_add", description: "x").toolName == "user_add")
        #expect(UserTool(kind: .macro, name: "!!!", description: "x").toolName == "user_tool")
        #expect(ToolRegistry.isValidName(UserTool(kind: .macro, name: String(repeating: "a", count: 90), description: "x").toolName))
    }

    @Test func incompleteToolsAreExplainedAndLeftOut() {
        #expect(UserTool(kind: .macro, name: "", description: "x", steps: [.text("a")]).problem == "Give it a name.")
        #expect(UserTool(kind: .macro, name: "a", description: "x").problem == "Add at least one step.")
        #expect(UserTool(kind: .macro, name: "a", description: "x", steps: [.key(["cmd+nope"])]).problem != nil)
        #expect(UserTool(kind: .shortcut, name: "a", description: "x").problem == "Pick a shortcut.")
        let ok = UserTool(kind: .macro, name: "a", description: "x", steps: [.text("a")])
        #expect(BuiltInTools.user([ok, UserTool(kind: .shortcut, name: "b", description: "y")], runner: RunnerLog()).count == 1)
    }

    @Test func macrosFillTheParameterAndShortcutsGetTheInput() async {
        let runner = RunnerLog()
        let search = UserTool(kind: .macro, name: "search", description: "Searches the app",
                              steps: [.key(["cmd+f"]), .text("{{text}}\n")], parameter: "What to look for")
        let remind = UserTool(kind: .shortcut, name: "remind", description: "Adds a reminder", shortcut: "Add Reminder",
                              parameter: "Reminder text", returnsOutput: true)
        let tools = BuiltInTools.user([search, remind], runner: runner)
        #expect(tools[0].spec.inputSchema["required"] == .array([.string("text")]))
        #expect(tools[0].risk == .safe)
        #expect(tools[1].risk == .risky)
        _ = await tools[0].run(.object(["text": .string("budget")]), context: ToolContext())
        let out = await tools[1].run(.object(["text": .string("call Anna")]), context: ToolContext())
        #expect(out.content == "output")
        #expect(runner.calls == ["key cmd+f | text budget\n", "shortcut Add Reminder call Anna true"])
    }

    @Test func userToolsAreSavedInTheConfig() throws {
        var config = AppConfig()
        config.agent.userTools = [UserTool(kind: .shortcut, name: "remind", description: "x", shortcut: "Add Reminder", risk: .safe)]
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(back.agent.userTools == config.agent.userTools)
        #expect(back.agent.userTools[0].risk == .safe)
    }

    @Test func theCatalogListsEveryBuiltInToolOnce() {
        let names = ToolCatalog.entries.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Set(ToolCatalog.groups.flatMap(\.tools)) == Set(names))
        #expect(ToolCatalog.entries.first { $0.name == "open_url" }?.optIn == true)
    }
}
