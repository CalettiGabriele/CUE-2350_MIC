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

/// Today's voice command: one call with `PromptComposer.commandMessages`, validated by
/// `CommandParser` (DictationController.runCommand). The baseline of phase 0.
public struct LegacyEngine: EvalEngine {
    public let provider: ChatProvider
    public var name: String { "legacy" }

    public init(provider: ChatProvider) { self.provider = provider }

    public func run(_ testCase: EvalCase, screen: Screen) async -> EngineResult {
        let messages = LegacyCommand.messages(context: Self.context(screen), transcript: testCase.command)
        let start = Date()
        let response: String
        do {
            response = try await provider.complete(system: messages.system, user: messages.user, temperature: 0)
        } catch {
            return EngineResult(actions: nil, note: error.localizedDescription,
                                latencyMs: Date().timeIntervalSince(start) * 1000, raw: "")
        }
        let latency = Date().timeIntervalSince(start) * 1000
        switch LegacyCommand.parse(response) {
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
    public static func context(_ screen: Screen) -> LegacyCommand.CommandContext {
        let profile = Profile.defaults.first { $0.id == screen.profile } ?? Profile.defaults[Profile.defaults.count - 1]
        let intents = profile.intents.filter { $0.value != .none }.keys.sorted() + (screen.extraIntents ?? [])
        return LegacyCommand.CommandContext(
            appName: screen.app, language: screen.language ?? "auto", channels: screen.channels ?? [],
            slots: profile.slots.map(\.name), intents: intents, selection: screen.selection,
            hints: profile.interaction.commandHints)
    }

    /// The same step in the agent's vocabulary.
    public static func action(_ step: LegacyCommand.Step) -> EvalAction {
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

/// The voice command agent on a fake screen: the parity tools run against `RecordingMac`, which
/// records what would have happened. The recorded actions are what the scorer sees.
public struct AgentEngine: EvalEngine {
    public let provider: ChatProvider
    public let limits: AgentLimits
    public var name: String { "agent" }

    public init(provider: ChatProvider, limits: AgentLimits) {
        self.provider = provider
        self.limits = limits
    }

    public func run(_ testCase: EvalCase, screen: Screen) async -> EngineResult {
        let context = Self.context(screen)
        let mac = RecordingMac(screen: screen)
        let loop = AgentLoop(provider: provider, registry: ToolRegistry(BuiltInTools.standard(mac, screen: context) + BuiltInTools.interface(mac)
                                                + BuiltInTools.user(RecordingMac.userTools(screen), runner: mac)),
                             limits: limits, confirm: { _ in true })
        let start = Date()
        let run = await loop.run(context, command: testCase.command)
        let latency = Date().timeIntervalSince(start) * 1000
        let trace = run.trace.map { "\($0.tool) \($0.arguments) → \($0.ok ? "" : "FAILED ")\($0.result)" }.joined(separator: "\n")
        let note = "\(run.modelCalls) calls · \(Int(run.modelMs)) ms · \(run.promptTokens)+\(run.completionTokens) tok · \(run.outcome)"
        if case .failed(let error) = run.outcome, run.trace.isEmpty {
            return EngineResult(actions: nil, note: error, latencyMs: latency, raw: trace)
        }
        return EngineResult(actions: mac.actions, note: note, latencyMs: latency, raw: trace)
    }

    /// What the app's snapshot would read on this screen.
    public static func context(_ screen: Screen) -> ScreenContext {
        let profile = Profile.defaults.first { $0.id == screen.profile } ?? Profile.defaults[Profile.defaults.count - 1]
        let intents = profile.intents.filter { $0.value != .none }.keys.sorted() + (screen.extraIntents ?? [])
        return ScreenContext(app: screen.app, window: screen.window, profile: profile.name,
                             textFormat: screen.textFormat ?? profile.textFormat.rawValue, language: screen.language ?? "auto",
                             selection: screen.selection, fieldText: screen.fieldText, channels: screen.channels ?? [],
                             skills: profile.slots.filter { $0.kind == .run }.map(\.name), intents: intents, appNotes: profile.interaction.commandHints)
    }
}

/// `MacActions` on a fake screen: every call is recorded in the agent's vocabulary, and the
/// focused field is simulated (text, selection) so reading, selecting and formatting behave.
public final class RecordingMac: MacActions, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [EvalAction] = []
    private var text: NSString
    /// The selected range in `text`; length 0 = just the cursor.
    private var selection: NSRange
    /// The controls, menus and windows the interface tools see.
    let screen: Screen

    public init(screen: Screen) {
        self.screen = screen
        let field = (screen.fieldText ?? "") as NSString
        text = field
        if let selected = screen.selection, !selected.isEmpty {
            let found = field.range(of: selected)
            selection = found.location == NSNotFound ? NSRange(location: field.length, length: 0) : found
            if found.location == NSNotFound {   // a selection the field text does not show: keep it at the end
                text = field.appending(selected) as NSString
                selection = NSRange(location: field.length, length: (selected as NSString).length)
            }
        } else {
            selection = NSRange(location: field.length, length: 0)
        }
    }

    public var actions: [EvalAction] { lock.withLock { recorded } }

    func record(_ action: EvalAction, _ answer: String = "ok") -> ToolResult {
        lock.withLock { recorded.append(action) }
        return .ok(answer)
    }

    private func insert(_ new: String) {
        lock.withLock {
            text = text.replacingCharacters(in: selection, with: new) as NSString
            selection = NSRange(location: selection.location + (new as NSString).length, length: 0)
        }
    }

    public func typeText(_ value: String) async -> ToolResult {
        insert(value)
        return record(EvalAction(tool: "type_text", args: ["text": value]), "typed")
    }

    public func pressKeys(_ keys: [String]) async -> ToolResult {
        let canonical = keys.map(Scorer.canonicalKey)
        lock.withLock {
            if canonical.last == "cmd+a" {
                selection = NSRange(location: 0, length: text.length)
            } else if !canonical.allSatisfy({ ["cmd+b", "cmd+i", "cmd+u", "cmd+c"].contains($0) }) {
                selection = NSRange(location: selection.location + selection.length, length: 0)
            }
        }
        return record(EvalAction(tool: "press_keys", keys: keys), "pressed " + keys.joined(separator: " "))
    }

    public func replaceSelection(_ value: String) async -> ToolResult {
        insert(value)
        return record(EvalAction(tool: "replace_selection", args: ["text": value]), "selection replaced")
    }

    public func switchChannel(_ name: String) async -> ToolResult {
        record(EvalAction(tool: "switch_channel", args: ["name": name]), "now on channel \(name)")
    }
    public func runSkill(_ name: String) async -> ToolResult { record(EvalAction(tool: "run_skill", args: ["name": name]), "ran \(name)") }
    public func runIntent(_ name: String) async -> ToolResult { record(EvalAction(tool: "run_intent", args: ["name": name]), "done: \(name)") }

    public func readFocusedText() async -> ToolResult {
        let (all, selected) = lock.withLock { (text as String, selection.length > 0 ? text.substring(with: selection) : nil) }
        guard !all.isEmpty else { return .failed("this app does not expose the field's text") }
        return .ok("field text:\n\(all)\nselected: " + (selected.map { "\"\($0)\"" } ?? "(none)"))
    }

    public func selectText(_ needle: String, occurrence: Int) async -> ToolResult {
        let found: String? = lock.withLock {
            var ranges: [NSRange] = []
            var search = NSRange(location: 0, length: text.length)
            while search.length > 0 {
                let r = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search)
                guard r.location != NSNotFound else { break }
                ranges.append(r)
                let next = r.location + max(1, r.length)
                search = NSRange(location: next, length: text.length - next)
            }
            let index = occurrence < 0 ? ranges.count + occurrence : occurrence - 1
            guard ranges.indices.contains(index) else { return nil }
            selection = ranges[index]
            return text.substring(with: ranges[index])
        }
        guard let found else {
            let start = lock.withLock { String((text as String).prefix(300)) }
            return .failed("text not found; the field starts with: \"\(start)\"")
        }
        return record(EvalAction(tool: "select_text", args: ["text": found]), "selected \"\(found)\"")
    }

    public func currentSelection() async -> String? {
        lock.withLock { selection.length > 0 ? text.substring(with: selection) : nil }
    }
}

/// The interface tools on the fake screen: the corpus lists the controls, menus and windows.
extension RecordingMac: MacUI {
    public func uiElements() async -> [UIElementInfo]? {
        screen.ui.map { $0.map { UIElementInfo(id: $0.id, role: $0.role, title: $0.title) } }
    }
    public func press(_ id: String) async -> ToolResult {
        let title = screen.ui?.first { $0.id == id }?.title ?? id
        return record(EvalAction(tool: "click", args: ["element": id]), "pressed «\(title)»")
    }
    public func setValue(_ id: String, text: String) async -> ToolResult {
        record(EvalAction(tool: "set_value", args: ["element": id, "text": text]), "text set")
    }
    public func menuItems() async -> [String]? { screen.menus ?? [] }
    public func chooseMenuItem(_ path: String) async -> ToolResult {
        record(EvalAction(tool: "choose_menu_item", args: ["path": path]), "chose \(path)")
    }
    public func windows() async -> [WindowInfo] {
        let list: [Screen.Window] = screen.windows ?? screen.window.map { [Screen.Window(id: "w1", title: $0)] } ?? []
        return list.map { WindowInfo(id: $0.id, title: $0.title) }
    }
    public func focusWindow(_ id: String) async -> ToolResult {
        record(EvalAction(tool: "focus_window", args: ["window": id]), "in front")
    }
    public func closeWindow(_ id: String) async -> ToolResult {
        record(EvalAction(tool: "close_window", args: ["window": id]), "closed")
    }
    public func openApp(_ name: String) async -> ToolResult {
        record(EvalAction(tool: "open_app", args: ["name": name]), "\(name) is open")
    }
    public func openURL(_ url: URL) async -> ToolResult {
        record(EvalAction(tool: "open_url", args: ["url": url.absoluteString]), "opened")
    }
}

/// The corpus's user tools: each one is a shortcut named after the tool, so a call records the
/// tool's name and what the agent passed in.
extension RecordingMac: UserToolRunner {
    public func runMacro(_ steps: [Action]) async -> ToolResult { .ok("done") }
    public func runShortcut(_ name: String, input: String?, returnsOutput: Bool) async -> ToolResult {
        let tool = UserTool(kind: .shortcut, name: name, description: "").toolName
        return record(EvalAction(tool: tool, args: input.map { ["text": $0] } ?? [:]), "done")
    }

    /// The screen's user tools as the app would build them from Settings.
    static func userTools(_ screen: Screen) -> [UserTool] {
        (screen.userTools ?? []).map { tool in
            let name = tool.name.hasPrefix("user_") ? String(tool.name.dropFirst(5)) : tool.name
            return UserTool(kind: .shortcut, name: name, description: tool.description, shortcut: name, parameter: tool.parameter)
        }
    }
}
