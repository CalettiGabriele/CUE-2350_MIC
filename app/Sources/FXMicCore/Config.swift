import Foundation

/// Configuration schema (TDD §3.3, One-Pager 001), stored in
/// ~/Library/Application Support/FXMicBridge/config.json. Every key is optional: missing keys
/// fall back to the defaults below, so a partial file is valid. Schema 1 files (modes/styles)
/// are migrated on read.
public struct AppConfig: Codable, Equatable, Sendable {
    public var schemaVersion = 4
    public var audio = Audio()
    public var speech = Speech()
    public var llm = LLM()
    /// The voice command agent: limits, tools and safety (TDD voice command agent §3.1).
    public var agent = Agent()
    public var injection = Injection()
    public var ui = UI()
    public var history = History()
    public var device = Device()
    /// Destinations the orange button switches between, one red LED each (One-Pager 004 §4).
    public var channels: [Channel] = []
    /// Extra apps whose sessions can be told apart and reopened (see `SessionAdapter`); Claude and
    /// Codex desktop are built in.
    public var sessionAdapters: [SessionAdapter] = []
    /// Menu label of each organization (id → label), learned the first time the app switches to it.
    public var organizationLabels: [String: String] = [:]
    public var profiles: [Profile] = Profile.defaults

    public init() {}

    public struct History: Codable, Equatable, Sendable {
        public var enabled = true
        /// Entries older than this are deleted (TDD §4).
        public var retentionDays = 7
        public init() {}
    }

    public struct UI: Codable, Equatable, Sendable {
        /// Menu bar icon when idle: "auto" (mic), a preset id from
        /// `MenuBarIconPreset`, or "file" to use `menuBarIconFile`.
        public var menuBarIcon = "auto"
        /// Absolute path of a custom SVG/PNG/PDF icon (copied into the app's support folder).
        public var menuBarIconFile: String?
        /// Language of menus, windows and messages (default English).
        public var language: L.Language = .en
        public init() {}
    }

    public struct Device: Codable, Equatable, Sendable {
        /// How the app talks to the mic (One-Pager 002): the USB-C serial line, the 3.5 mm jack
        /// (acoustic codes from the FXMic firmware), or whichever is there.
        public enum Transport: String, Codable, CaseIterable, Sendable { case auto, usb, jack }
        public var transport: Transport = .auto
        /// Physical `ui.led_level` index for each logical LED:
        /// [red 1…4 top→bottom, white 1…4 top→bottom]. Unverified default, see TEST_NOTES.
        public var ledMap = [0, 1, 2, 3, 4, 5, 6, 7]
        /// Frame time of the LED animations (recording "KITT", processing).
        public var ledAnimationMs: Double = 120
        public init() {}
    }

    public struct Audio: Codable, Equatable, Sendable {
        /// CoreAudio UID of the input device; nil = system default input.
        public var inputDeviceUID: String?
        public var minDurationMs: Double = 300
        public var silenceThresholdDBFS: Float = -50
        /// One-Pager 005: pause the music while the handle is held.
        public var pauseMedia = PauseMedia()
        public init() {}
    }

    public struct PauseMedia: Codable, Equatable, Sendable {
        public var enabled = false
        /// Player ids (`MediaPlayerID`).
        public var apps: [String] = [MediaPlayerID.spotify, MediaPlayerID.music]
        /// The pause is sent after the handle has been held this long: a click does not stop the music.
        public var holdMs: Double = 150
        public init() {}
    }

    public struct Speech: Codable, Equatable, Sendable {
        public var model = "openai_whisper-large-v3-v20240930_turbo_632MB"
        /// "auto" or an ISO code such as "it".
        public var language = "auto"
        public var vocabulary = ["Claude", "Claude Code", "MCP", "repo", "commit", "pull request"]
        public init() {}
    }

    /// One model for everything: the voice command and the LLM skills (TDD voice command agent §3.1).
    public struct LLM: Codable, Equatable, Sendable {
        /// Saved servers; `activeProvider` is the one in use.
        public var providers: [LLMProvider] = [.ollama]
        public var activeProvider = LLMProvider.ollama.id
        public var model = "qwen3.5:4b"
        public var timeoutMs: Double = 8000
        public var temperature = 0.2
        /// Asks reasoning models (Qwen 3.x, …) to answer without a thinking phase: much faster.
        public var disableThinking = true
        public var baseSystemPrompt = """
        You are a dictation post-processor. You receive text transcribed from speech and transform \
        it following the instructions. Keep the language of the dictated text unless the \
        instruction asks for another one. Reply with the final text only: no comments, quotes or \
        explanations.
        """
        public init() {}

        /// The provider in use (the first one if the id is unknown).
        public var active: LLMProvider {
            get { providers.first { $0.id == activeProvider } ?? providers.first ?? .ollama }
            set {
                if let i = providers.firstIndex(where: { $0.id == newValue.id }) { providers[i] = newValue }
                else { providers.append(newValue) }
                activeProvider = newValue.id
            }
        }

        /// True when the provider in use is on this Mac (TDD §4: warn otherwise).
        public var isLocal: Bool { active.isLocal }

        /// The client for the provider in use; the key comes from the caller (the Keychain).
        public func client(apiKey: String?) -> OpenAICompatibleClient {
            OpenAICompatibleClient(provider: active, model: model, apiKey: apiKey, timeoutMs: timeoutMs,
                                   disableThinking: disableThinking)
        }
    }

    public struct Agent: Codable, Equatable, Sendable {
        /// Model calls per command.
        public var maxSteps = 8
        /// Wall time per command; the time spent waiting for a confirmation does not count.
        public var timeBudgetMs: Double = 30000
        /// No answer to a confirmation within this time means no.
        public var confirmTimeoutMs: Double = 10000
        /// Not sent to providers that reject it (Anthropic).
        public var temperature: Double = 0
        public var disabledTools: [String] = []
        /// Tools that are off unless named here: "open_url".
        public var enabledTools: [String] = []
        /// Settings › Voice command › My tools.
        public var userTools: [UserTool] = []
        public var riskOverrides: [String: Risk] = [:]
        public init() {}
    }

    public struct Injection: Codable, Equatable, Sendable {
        public var defaultStrategy: InjectionStrategy = .paste
        public var restoreClipboardMs: Double = 250
        public init() {}
    }
}

public enum InjectionStrategy: String, Codable, Sendable {
    case paste, ax, type
}

/// Kept for schema-1 migration and for LLM previews.
public struct PromptPreset: Codable, Equatable, Sendable {
    public var name: String
    public var prompt: String
    public init(name: String, prompt: String) {
        self.name = name
        self.prompt = prompt
    }
}

// MARK: - Channels (orange button, One-Pager 004 §4)

/// A destination for the dictation: an app, a document or a window, bound with a long press on
/// orange. The app is brought to the front when you talk to the channel.
public struct Channel: Codable, Equatable, Sendable {
    public var name: String
    public var bundleID: String
    /// `AXDocument` of the window (a `file://` URL), when the app exposes it.
    public var document: String?
    /// Window title at binding time: a hint only, titles change.
    public var title: String?
    /// Session or thread id for apps that keep several in one window (Claude and Codex desktop).
    public var session: String?
    /// Deep link that opens the page the window showed, for apps whose pages live in a web view
    /// (a Claude chat or project): without it a chat cannot be reached from the Code view.
    public var link: String?
    /// Organization (workspace) the session or chat belongs to, for apps that hold several under
    /// one account (Claude desktop): orange switches to it before opening the link.
    public var organization: String?

    public static let maxCount = 4

    public init(name: String, bundleID: String, document: String? = nil, title: String? = nil,
                session: String? = nil, link: String? = nil, organization: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.document = document
        self.title = title
        self.session = session
        self.link = link
        self.organization = organization
    }

    /// How narrowly the channel points: a session, a document, a window title or the whole app.
    public var specificity: Int { session != nil || link != nil ? 3 : (document != nil ? 2 : (title != nil ? 1 : 0)) }

    /// True when `window`, the description of the window in front, is what this channel points to.
    public func matches(window: Channel) -> Bool {
        guard bundleID == window.bundleID else { return false }
        if let link { return link == window.link }
        if let session { return session == window.session }
        if let document { return document == window.document }
        if let title { return title == window.title }
        return true
    }

    /// Same app and same session/document/window: binding it again moves to that channel.
    public func sameTarget(as other: Channel) -> Bool {
        guard bundleID == other.bundleID else { return false }
        if link != nil || other.link != nil { return link == other.link }
        if session != nil || other.session != nil { return session == other.session }
        return document == other.document && (document != nil || title == other.title)
    }
}

// MARK: - Interaction modes (superseded by channels, kept for old config files)

public enum InteractionMode: String, Codable, CaseIterable, Sendable {
    case dictation, enhanced, command, computerUse

    /// Red LED (0 = top) that shows the mode.
    public var ledIndex: Int {
        switch self {
        case .dictation: return 0
        case .enhanced: return 1
        case .command: return 2
        case .computerUse: return 3
        }
    }

    public var label: String {
        switch self {
        case .dictation: return "Dictation"
        case .enhanced: return "Enhanced"
        case .command: return "Command"
        case .computerUse: return "Computer Use"
        }
    }

    public var usesLLM: Bool { self == .enhanced || self == .command }
    /// Computer Use is a placeholder for now.
    public var isAvailable: Bool { self != .computerUse }
}

public struct InteractionSettings: Codable, Equatable, Sendable {
    /// Modes the orange button cycles through, in this order.
    public var enabled: [InteractionMode] = InteractionMode.allCases
    public var defaultMode: InteractionMode = .dictation
    /// LLM instruction for "Migliorato".
    public var enhancePrompt = "Fix punctuation, capitalisation and transcription errors. Keep the words and the meaning."
    /// App-specific hints for "Comando" (e.g. "the field accepts Markdown").
    public var commandHints = ""
    public init() {}
}

// MARK: - Slots (white button, One-Pager 001 §2)

public enum SlotKind: String, Codable, CaseIterable, Sendable {
    /// Grey runs `action` right away.
    case run
    /// The next dictation is written inside `template` ({{text}} = dictated text).
    case template
    /// The next dictation is transformed by the LLM with `template` as instruction.
    case llm
}

public struct Slot: Codable, Equatable, Sendable {
    public var name: String
    public var kind: SlotKind
    public var action: Action = .none
    public var template = ""

    public init(name: String, kind: SlotKind, action: Action = .none, template: String = "") {
        self.name = name
        self.kind = kind
        self.action = action
        self.template = template
    }

    public static func run(_ name: String, _ action: Action) -> Slot { Slot(name: name, kind: .run, action: action) }
    public static func template(_ name: String, _ text: String) -> Slot { Slot(name: name, kind: .template, template: text) }
    public static func llm(_ name: String, _ prompt: String) -> Slot { Slot(name: name, kind: .llm, template: prompt) }

    /// Puts the dictated text into a template slot. Without a placeholder it is appended.
    public func fill(_ dictated: String) -> String {
        for placeholder in ["{{testo}}", "{{text}}"] where template.contains(placeholder) {
            return template.replacingOccurrences(of: placeholder, with: dictated)
        }
        return template.isEmpty ? dictated : template + " " + dictated
    }

    public static let maxCount = 15
}

// MARK: - Actions

/// What a gesture does. JSON: `{"type": "key", "keys": ["cmd+a", "delete"]}`.
public enum Action: Equatable, Sendable {
    case key([String])
    case text(String)
    case undoLastInsertion
    case reinsertLast(raw: Bool)
    case cancel
    case editSelection
    /// Orange: channels. `bindChannel` ties the frontmost window to the current channel.
    case nextChannel
    case previousChannel
    case bindChannel
    /// Unbinds all four channels (orange held for 3 s).
    case clearChannels
    /// Legacy orange actions (interaction modes).
    case cycleMode
    case resetMode
    /// White: slot navigation.
    case nextSlot
    case previousSlot
    case clearSlot
    /// Grey: run the selected slot; with no slot selected it presses Return.
    case runSlot
    /// Does what the active profile's `intents` say for this name (e.g. "interrupt").
    case intent(String)
    case none
}

extension Action: Codable {
    private enum CodingKeys: String, CodingKey { case type, keys, text, variant, name }

    private static let simple: [String: Action] = [
        "undoLastInsertion": .undoLastInsertion, "cancel": .cancel, "editSelection": .editSelection,
        "nextChannel": .nextChannel, "previousChannel": .previousChannel, "bindChannel": .bindChannel,
        "clearChannels": .clearChannels,
        "cycleMode": .cycleMode, "resetMode": .resetMode, "nextSlot": .nextSlot,
        "previousSlot": .previousSlot, "clearSlot": .clearSlot, "runSlot": .runSlot, "none": .none,
    ]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "key":
            if let keys = try? c.decode([String].self, forKey: .keys) {
                self = .key(keys)
            } else {
                self = .key([try c.decode(String.self, forKey: .keys)])
            }
        case "text": self = .text(try c.decode(String.self, forKey: .text))
        case "reinsertLast": self = .reinsertLast(raw: (try? c.decode(String.self, forKey: .variant)) != "processed")
        case "intent": self = .intent((try? c.decode(String.self, forKey: .name)) ?? "")
        case "cycleStyle": self = .nextSlot   // schema 1: the white button now walks the slots
        default: self = Self.simple[type] ?? .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let keys):
            try c.encode("key", forKey: .type)
            try c.encode(keys, forKey: .keys)
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .reinsertLast(let raw):
            try c.encode("reinsertLast", forKey: .type)
            try c.encode(raw ? "raw" : "processed", forKey: .variant)
        case .intent(let name):
            try c.encode("intent", forKey: .type)
            try c.encode(name, forKey: .name)
        default:
            let name = Self.simple.first { $0.value == self }?.key ?? "none"
            try c.encode(name, forKey: .type)
        }
    }
}

public struct ButtonActions: Codable, Equatable, Sendable {
    public var tap: Action = .none
    public var doubleTap: Action = .none
    public var longPress: Action = .none
    /// Held for 3 s: a deliberate gesture for things that must not happen by accident.
    public var veryLongPress: Action = .none
    public init(tap: Action = .none, doubleTap: Action = .none, longPress: Action = .none, veryLongPress: Action = .none) {
        self.tap = tap
        self.doubleTap = doubleTap
        self.longPress = longPress
        self.veryLongPress = veryLongPress
    }
}

public struct HandleActions: Codable, Equatable, Sendable {
    public var doubleClick: Action = .key(["shift+return"])
    public init(doubleClick: Action = .key(["shift+return"])) { self.doubleClick = doubleClick }
}

public struct ShakeActions: Codable, Equatable, Sendable {
    public var short: Action = .cancel
    public var hold: Action = .key(["cmd+a", "delete"])
    public init(short: Action = .cancel, hold: Action = .key(["cmd+a", "delete"])) {
        self.short = short
        self.hold = hold
    }
}

// MARK: - Profile

/// rich: shortcuts such as ⌘B work; markdown: formatting is written as marks (**bold**);
/// plain: no formatting (terminals).
public enum TextFormat: String, Codable, CaseIterable, Sendable {
    case rich, markdown, plain
}

public struct Profile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Bundle identifiers of the apps this profile applies to. Empty = fallback profile.
    public var apps: [String] = []
    public var interaction = InteractionSettings()
    /// Up to 15 slots, shown in binary on the white LEDs.
    public var slots: [Slot] = []
    public var orange = ButtonActions(tap: .nextChannel, doubleTap: .previousChannel, longPress: .bindChannel,
                                      veryLongPress: .clearChannels)
    public var white = ButtonActions(tap: .nextSlot, doubleTap: .previousSlot, longPress: .clearSlot)
    public var grey = ButtonActions(tap: .runSlot, doubleTap: .undoLastInsertion, longPress: .intent("interrupt"))
    /// Grey pressed while the handle is held: the dictation becomes a voice command.
    public var chord: Action = .editSelection
    /// What the voice command and the buttons mean in this app, by name (One-Pager 004 §6.2).
    /// "interrupt" is built in; the others (approve, newSession…) are added per profile.
    public var intents: [String: Action] = ["interrupt": .key(["escape"])]
    public var handle = HandleActions()
    public var shake = ShakeActions()
    /// nil = use `injection.defaultStrategy`.
    public var injection: InjectionStrategy?
    /// nil = use `speech.language`.
    public var language: String?
    /// How the voice command formats text in these apps (format_selection).
    public var textFormat: TextFormat

    public init(id: String, name: String) {
        self.id = id
        self.name = name
        textFormat = Profile.defaultTextFormat(id)
    }
}

extension Profile {
    public static let claudeDesktopID = "com.anthropic.claudefordesktop"

    /// The text format of the built-in profiles: Markdown in the Claude input, plain text in
    /// terminals, rich text elsewhere.
    public static func defaultTextFormat(_ id: String) -> TextFormat {
        switch id {
        case "claude-desktop": return .markdown
        case "coding-agent": return .plain
        default: return .rich
        }
    }

    public static let defaults: [Profile] = {
        var claude = Profile(id: "claude-desktop", name: "Claude")
        claude.apps = [claudeDesktopID]
        claude.interaction.enhancePrompt = "Fix punctuation, capitalisation and transcription errors and make the request clear for an AI assistant. Keep the meaning and the details."
        claude.interaction.commandHints = "The input field accepts Markdown: bullet list \"- \", numbered list \"1. \", bold **text**. Return sends the message: use shift+return for a new line."
        claude.slots = [
            .run("New chat", .key(["cmd+n"])),
            .run("Stop response", .key(["escape"])),
            .template("Summarize", "Summarize concisely:\n{{text}}"),
            .template("Translate to English", "Translate into English:\n{{text}}"),
            .template("Explain simply", "Explain this simply, as to a beginner:\n{{text}}"),
            .template("Brainstorm", "Brainstorm ideas about: {{text}}"),
        ]

        var coding = Profile(id: "coding-agent", name: "Coding agent")
        coding.apps = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                       "com.microsoft.VSCode", "dev.warp.Warp-Stable"]
        coding.interaction.enhancePrompt = "Rewrite as a clear, complete instruction for a coding agent. Keep file names, symbols, commands and numbers exact."
        coding.interaction.commandHints = "This is a terminal running Claude Code. Return sends. Ctrl+U clears the line, Esc interrupts."
        coding.slots = [
            .run("/compact", .text("/compact\n")),
            .run("/clear", .text("/clear\n")),
            .run("/review", .text("/review\n")),
            .template("Bug report", "Fix this bug. Observed behaviour: {{text}}"),
            .llm("Commit message", "Write a commit message in Conventional Commits style, in English."),
        ]
        coding.grey = ButtonActions(tap: .runSlot, doubleTap: .undoLastInsertion, longPress: .key(["escape"]))
        // Terminals: ⌘A selects the scrollback, so clear the input line instead.
        coding.shake = ShakeActions(short: .cancel, hold: .key(["ctrl+e", "ctrl+u"]))

        var general = Profile(id: "default", name: "General")
        general.slots = [
            .llm("Email", "Rewrite as a clear, polite email with a greeting and a closing."),
            .llm("Translate to English", "Translate into natural English."),
            .llm("Bullet list", "Turn into a short bullet list."),
            .llm("Shorter", "Rewrite it shorter, keeping the meaning."),
        ]
        return [claude, coding, general]
    }()
}

// MARK: - Lenient decoding (missing keys → defaults)

extension KeyedDecodingContainer {
    fileprivate func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
}

extension AppConfig {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, audio, speech, llm, agent, injection, ui, history, device, channels, sessionAdapters, organizationLabels, profiles
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        schemaVersion = 4
        channels = Array(c.value(.channels, [Channel]()).prefix(Channel.maxCount))
        sessionAdapters = c.value(.sessionAdapters, [SessionAdapter]())
        organizationLabels = c.value(.organizationLabels, [String: String]())
        audio = c.value(.audio, d.audio)
        speech = c.value(.speech, d.speech)
        llm = c.value(.llm, d.llm)
        agent = c.value(.agent, d.agent)
        injection = c.value(.injection, d.injection)
        ui = c.value(.ui, d.ui)
        history = c.value(.history, d.history)
        device = c.value(.device, d.device)
        var decoded = c.value(.profiles, [Profile]())
        // Schema 1 → 2: add the new built-in profiles (e.g. Claude desktop) the file doesn't have.
        if c.value(.schemaVersion, 1) < 2 {
            for (index, profile) in d.profiles.enumerated() where !decoded.contains(where: { $0.id == profile.id }) {
                decoded.insert(profile, at: min(index, decoded.count))
            }
        }
        profiles = decoded.isEmpty ? d.profiles : decoded
    }
}

extension AppConfig.Audio {
    private enum CodingKeys: String, CodingKey { case inputDeviceUID, minDurationMs, silenceThresholdDBFS, pauseMedia }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        inputDeviceUID = c.value(.inputDeviceUID, nil)
        minDurationMs = c.value(.minDurationMs, d.minDurationMs)
        silenceThresholdDBFS = c.value(.silenceThresholdDBFS, d.silenceThresholdDBFS)
        pauseMedia = c.value(.pauseMedia, d.pauseMedia)
    }
}

extension AppConfig.PauseMedia {
    private enum CodingKeys: String, CodingKey { case enabled, apps, holdMs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c.value(.enabled, d.enabled)
        apps = c.value(.apps, d.apps)
        holdMs = min(1000, max(0, c.value(.holdMs, d.holdMs)))
    }
}

extension AppConfig.Speech {
    private enum CodingKeys: String, CodingKey { case model, language, vocabulary }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        model = c.value(.model, d.model)
        language = c.value(.language, d.language)
        vocabulary = c.value(.vocabulary, d.vocabulary)
    }
}

extension AppConfig.LLM {
    private enum CodingKeys: String, CodingKey {
        case providers, activeProvider, model, timeoutMs, temperature, disableThinking, baseSystemPrompt
        case baseURL   // schema 3
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        let saved = c.value(.providers, [LLMProvider]())
        if !saved.isEmpty {
            var seen = Set<String>()
            providers = saved.filter { seen.insert($0.id).inserted }
            activeProvider = c.value(.activeProvider, providers[0].id)
        } else if let url = try? c.decodeIfPresent(String.self, forKey: .baseURL) {
            // Schema 3 → 4: the single URL becomes the only provider.
            let ollama = url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == ProviderPreset.ollama.defaultURL
            providers = [ollama ? .ollama : LLMProvider(id: "custom", preset: .custom, name: "Custom", baseURL: url)]
            activeProvider = providers[0].id
        }
        model = c.value(.model, d.model)
        timeoutMs = c.value(.timeoutMs, d.timeoutMs)
        temperature = c.value(.temperature, d.temperature)
        disableThinking = c.value(.disableThinking, d.disableThinking)
        baseSystemPrompt = c.value(.baseSystemPrompt, d.baseSystemPrompt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providers, forKey: .providers)
        try c.encode(activeProvider, forKey: .activeProvider)
        try c.encode(model, forKey: .model)
        try c.encode(timeoutMs, forKey: .timeoutMs)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(disableThinking, forKey: .disableThinking)
        try c.encode(baseSystemPrompt, forKey: .baseSystemPrompt)
    }
}

extension AppConfig.Agent {
    private enum CodingKeys: String, CodingKey {
        case maxSteps, timeBudgetMs, confirmTimeoutMs, temperature, disabledTools, enabledTools, riskOverrides
        case userTools
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        maxSteps = min(30, max(1, c.value(.maxSteps, d.maxSteps)))
        timeBudgetMs = max(2000, c.value(.timeBudgetMs, d.timeBudgetMs))
        confirmTimeoutMs = max(2000, c.value(.confirmTimeoutMs, d.confirmTimeoutMs))
        temperature = c.value(.temperature, d.temperature)
        disabledTools = c.value(.disabledTools, d.disabledTools)
        enabledTools = c.value(.enabledTools, d.enabledTools)
        userTools = c.value(.userTools, d.userTools)
        riskOverrides = c.value(.riskOverrides, d.riskOverrides)
    }
}

extension AppConfig.Injection {
    private enum CodingKeys: String, CodingKey { case defaultStrategy, restoreClipboardMs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        defaultStrategy = c.value(.defaultStrategy, d.defaultStrategy)
        restoreClipboardMs = c.value(.restoreClipboardMs, d.restoreClipboardMs)
    }
}

extension AppConfig.History {
    private enum CodingKeys: String, CodingKey { case enabled, retentionDays }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c.value(.enabled, d.enabled)
        retentionDays = max(0, c.value(.retentionDays, d.retentionDays))
    }
}

extension AppConfig.Device {
    private enum CodingKeys: String, CodingKey { case ledMap, ledAnimationMs, transport }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        let map = c.value(.ledMap, d.ledMap)
        // Must be a permutation of 0…7, otherwise fall back to the default.
        ledMap = map.sorted() == Array(0..<8) ? map : d.ledMap
        ledAnimationMs = max(40, c.value(.ledAnimationMs, d.ledAnimationMs))
        transport = c.value(.transport, d.transport)
    }
}

extension AppConfig.UI {
    private enum CodingKeys: String, CodingKey { case menuBarIcon, menuBarIconFile, language }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarIcon = c.value(.menuBarIcon, "auto")
        menuBarIconFile = c.value(.menuBarIconFile, nil)
        language = c.value(.language, .en)
    }
}

/// Built-in menu bar icons (SF Symbols), selectable from the menu.
public enum MenuBarIconPreset: String, CaseIterable, Sendable {
    case mic, micCircle, waveform, dot, sparkles

    public var symbolName: String {
        switch self {
        case .mic: return "mic"
        case .micCircle: return "mic.circle"
        case .waveform: return "waveform"
        case .dot: return "circle.fill"
        case .sparkles: return "sparkles"
        }
    }

    public var label: String {
        switch self {
        case .mic: return "Microphone"
        case .micCircle: return "Microphone in a circle"
        case .waveform: return "Sound wave"
        case .dot: return "Dot"
        case .sparkles: return "Sparkles"
        }
    }
}

extension InteractionSettings {
    private enum CodingKeys: String, CodingKey { case enabled, defaultMode, enhancePrompt, commandHints }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        let enabled = c.value(.enabled, d.enabled)
        self.enabled = enabled.isEmpty ? [.dictation] : enabled
        defaultMode = c.value(.defaultMode, d.defaultMode)
        enhancePrompt = c.value(.enhancePrompt, d.enhancePrompt)
        commandHints = c.value(.commandHints, d.commandHints)
    }
}

extension Slot {
    private enum CodingKeys: String, CodingKey { case name, kind, action, template }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "Slot")
        kind = c.value(.kind, .run)
        action = c.value(.action, .none)
        // Prompts are English (the old Italian placeholder is still filled, but rewritten).
        template = c.value(.template, "").replacingOccurrences(of: "{{testo}}", with: "{{text}}")
    }
}

extension ButtonActions {
    private enum CodingKeys: String, CodingKey { case tap, doubleTap, longPress, veryLongPress }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tap = c.value(.tap, .none)
        doubleTap = c.value(.doubleTap, .none)
        longPress = c.value(.longPress, .none)
        veryLongPress = c.value(.veryLongPress, .none)
    }
}

extension HandleActions {
    private enum CodingKeys: String, CodingKey { case doubleClick }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        doubleClick = c.value(.doubleClick, Self().doubleClick)
    }
}

extension ShakeActions {
    private enum CodingKeys: String, CodingKey { case short, hold }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        short = c.value(.short, d.short)
        hold = c.value(.hold, d.hold)
    }
}

extension Profile {
    private enum CodingKeys: String, CodingKey {
        case id, name, apps, interaction, slots, orange, white, grey, chord, intents, handle, shake, injection, language
        case textFormat
        case modes   // schema 1
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id: String = c.value(.id, "profile")
        var p = Profile(id: id, name: c.value(.name, id))
        p.apps = c.value(.apps, p.apps)
        if let interaction = try? c.decodeIfPresent(InteractionSettings.self, forKey: .interaction) {
            p.interaction = interaction
        } else if let modes = try? c.decodeIfPresent([PromptPreset].self, forKey: .modes) {
            // Schema 1: the first mode becomes "Migliorato", the others become LLM slots.
            if let first = modes.first { p.interaction.enhancePrompt = first.prompt }
            p.slots = modes.dropFirst().map { .llm($0.name, $0.prompt) }
        }
        p.slots = Array(c.value(.slots, p.slots).prefix(Slot.maxCount))
        let defaults = Profile(id: id, name: id)
        // Schema 1 button defaults (cycleStyle, key return) are upgraded to the new roles.
        p.orange = c.value(.orange, defaults.orange)
        p.white = c.value(.white, defaults.white)
        p.grey = c.value(.grey, defaults.grey)
        if p.grey.tap == .key(["return"]) { p.grey.tap = .runSlot }
        // Schema 3: a long press on grey interrupts instead of rewriting the last text.
        if p.grey.longPress == .reinsertLast(raw: true) { p.grey.longPress = .intent("interrupt") }
        // Schema 3: the orange button switches channels instead of interaction modes.
        if p.orange.tap == .cycleMode { p.orange.tap = .nextChannel }
        if p.orange.tap == .nextChannel {
            if p.orange.doubleTap == .none { p.orange.doubleTap = .previousChannel }
            if p.orange.longPress == .none || p.orange.longPress == .resetMode { p.orange.longPress = .bindChannel }
            if p.orange.veryLongPress == .none { p.orange.veryLongPress = .clearChannels }
        }
        if p.white.tap == .nextSlot, p.white.doubleTap == .none { p.white.doubleTap = .previousSlot }
        if p.white.tap == .nextSlot, p.white.longPress == .none { p.white.longPress = .clearSlot }
        p.chord = c.value(.chord, p.chord)
        p.intents = c.value(.intents, p.intents)
        p.handle = c.value(.handle, p.handle)
        p.shake = c.value(.shake, p.shake)
        p.injection = c.value(.injection, p.injection)
        p.language = c.value(.language, p.language)
        p.textFormat = c.value(.textFormat, p.textFormat)
        self = p
    }
}

extension Profile {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(apps, forKey: .apps)
        try c.encode(interaction, forKey: .interaction)
        try c.encode(slots, forKey: .slots)
        try c.encode(orange, forKey: .orange)
        try c.encode(white, forKey: .white)
        try c.encode(grey, forKey: .grey)
        try c.encode(chord, forKey: .chord)
        try c.encode(intents, forKey: .intents)
        try c.encode(handle, forKey: .handle)
        try c.encode(shake, forKey: .shake)
        try c.encodeIfPresent(injection, forKey: .injection)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encode(textFormat, forKey: .textFormat)
    }
}
