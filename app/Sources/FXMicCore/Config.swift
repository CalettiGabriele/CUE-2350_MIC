import Foundation

/// Configuration schema (TDD §3.3, One-Pager 001), stored in
/// ~/Library/Application Support/FXMicBridge/config.json. Every key is optional: missing keys
/// fall back to the defaults below, so a partial file is valid. Schema 1 files (modes/styles)
/// are migrated on read.
public struct AppConfig: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var audio = Audio()
    public var speech = Speech()
    public var llm = LLM()
    public var injection = Injection()
    public var ui = UI()
    public var history = History()
    public var device = Device()
    /// Destinations the orange button switches between, one red LED each (One-Pager 004 §4).
    public var channels: [Channel] = []
    /// Extra apps whose sessions can be told apart and reopened (see `SessionAdapter`); Claude and
    /// Codex desktop are built in.
    public var sessionAdapters: [SessionAdapter] = []
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
        public init() {}
    }

    public struct Speech: Codable, Equatable, Sendable {
        public var model = "openai_whisper-large-v3-v20240930_turbo_632MB"
        /// "auto" or an ISO code such as "it".
        public var language = "auto"
        public var vocabulary = ["Claude", "Claude Code", "MCP", "repo", "commit", "pull request"]
        public init() {}
    }

    public struct LLM: Codable, Equatable, Sendable {
        public var baseURL = "http://localhost:11434/v1"
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

        /// True when the endpoint is on this Mac (TDD §4: warn otherwise).
        public var isLocal: Bool {
            guard let host = URL(string: baseURL)?.host else { return false }
            return ["localhost", "127.0.0.1", "::1"].contains(host)
        }
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

    public static let maxCount = 4

    public init(name: String, bundleID: String, document: String? = nil, title: String? = nil, session: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.document = document
        self.title = title
        self.session = session
    }

    /// Same app and same session/document/window: binding it again moves to that channel.
    public func sameTarget(as other: Channel) -> Bool {
        guard bundleID == other.bundleID else { return false }
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
    /// The next dictation is written inside `template` ({{testo}} = dictated text).
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
    public init(tap: Action = .none, doubleTap: Action = .none, longPress: Action = .none) {
        self.tap = tap
        self.doubleTap = doubleTap
        self.longPress = longPress
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

public struct Profile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Bundle identifiers of the apps this profile applies to. Empty = fallback profile.
    public var apps: [String] = []
    public var interaction = InteractionSettings()
    /// Up to 15 slots, shown in binary on the white LEDs.
    public var slots: [Slot] = []
    public var orange = ButtonActions(tap: .nextChannel, doubleTap: .previousChannel, longPress: .bindChannel)
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

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

extension Profile {
    public static let claudeDesktopID = "com.anthropic.claudefordesktop"

    public static let defaults: [Profile] = {
        var claude = Profile(id: "claude-desktop", name: "Claude")
        claude.apps = [claudeDesktopID]
        claude.interaction.enhancePrompt = "Fix punctuation, capitalisation and transcription errors and make the request clear for an AI assistant. Keep the meaning and the details."
        claude.interaction.commandHints = "The input field accepts Markdown: bullet list \"- \", numbered list \"1. \", bold **text**. Return sends the message: use shift+return for a new line."
        claude.slots = [
            .run("New chat", .key(["cmd+n"])),
            .run("Stop response", .key(["escape"])),
            .template("Summarize", "Summarize concisely:\n{{testo}}"),
            .template("Translate to English", "Translate into English:\n{{testo}}"),
            .template("Explain simply", "Explain this simply, as to a beginner:\n{{testo}}"),
            .template("Brainstorm", "Brainstorm ideas about: {{testo}}"),
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
            .template("Bug report", "Fix this bug. Observed behaviour: {{testo}}"),
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
        case schemaVersion, audio, speech, llm, injection, ui, history, device, channels, sessionAdapters, profiles
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        schemaVersion = 3
        channels = Array(c.value(.channels, [Channel]()).prefix(Channel.maxCount))
        sessionAdapters = c.value(.sessionAdapters, [SessionAdapter]())
        audio = c.value(.audio, d.audio)
        speech = c.value(.speech, d.speech)
        llm = c.value(.llm, d.llm)
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
    private enum CodingKeys: String, CodingKey { case inputDeviceUID, minDurationMs, silenceThresholdDBFS }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        inputDeviceUID = c.value(.inputDeviceUID, nil)
        minDurationMs = c.value(.minDurationMs, d.minDurationMs)
        silenceThresholdDBFS = c.value(.silenceThresholdDBFS, d.silenceThresholdDBFS)
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
    private enum CodingKeys: String, CodingKey { case baseURL, model, timeoutMs, temperature, disableThinking, baseSystemPrompt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        baseURL = c.value(.baseURL, d.baseURL)
        model = c.value(.model, d.model)
        timeoutMs = c.value(.timeoutMs, d.timeoutMs)
        temperature = c.value(.temperature, d.temperature)
        disableThinking = c.value(.disableThinking, d.disableThinking)
        baseSystemPrompt = c.value(.baseSystemPrompt, d.baseSystemPrompt)
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
    private enum CodingKeys: String, CodingKey { case ledMap, ledAnimationMs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        let map = c.value(.ledMap, d.ledMap)
        // Must be a permutation of 0…7, otherwise fall back to the default.
        ledMap = map.sorted() == Array(0..<8) ? map : d.ledMap
        ledAnimationMs = max(40, c.value(.ledAnimationMs, d.ledAnimationMs))
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
        template = c.value(.template, "")
    }
}

extension ButtonActions {
    private enum CodingKeys: String, CodingKey { case tap, doubleTap, longPress }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tap = c.value(.tap, .none)
        doubleTap = c.value(.doubleTap, .none)
        longPress = c.value(.longPress, .none)
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
        }
        if p.white.tap == .nextSlot, p.white.doubleTap == .none { p.white.doubleTap = .previousSlot }
        if p.white.tap == .nextSlot, p.white.longPress == .none { p.white.longPress = .clearSlot }
        p.chord = c.value(.chord, p.chord)
        p.intents = c.value(.intents, p.intents)
        p.handle = c.value(.handle, p.handle)
        p.shake = c.value(.shake, p.shake)
        p.injection = c.value(.injection, p.injection)
        p.language = c.value(.language, p.language)
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
    }
}
