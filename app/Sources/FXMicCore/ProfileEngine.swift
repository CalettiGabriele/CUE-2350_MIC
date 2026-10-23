import Foundation

/// A parsed keyboard shortcut such as "cmd+shift+return".
public struct KeyCombo: Equatable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable { case command, shift, option, control }

    public let key: String
    public let modifiers: Set<Modifier>

    private static let aliases: [String: Modifier] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
    ]

    /// Keys the app can post. Single letters and digits are accepted as well.
    public static let namedKeys: Set<String> = [
        "return", "enter", "tab", "space", "delete", "backspace", "forwarddelete", "escape", "esc",
        "left", "right", "up", "down", "home", "end", "pageup", "pagedown",
    ]

    public init?(_ string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { return nil }
        var mods = Set<Modifier>()
        for part in parts.dropLast() {
            guard let mod = Self.aliases[part] else { return nil }
            mods.insert(mod)
        }
        let isChar = last.count == 1 && (last.first!.isLetter || last.first!.isNumber)
        guard isChar || Self.namedKeys.contains(last) else { return nil }
        key = last
        modifiers = mods
    }
}

/// Picks the profile for the frontmost app, keeps each profile's interaction mode and selected
/// slot, and maps gestures to actions (TDD §3.3, One-Pager 001). Pure: the app feeds it bundle
/// IDs and gestures.
public struct ProfileEngine {
    public private(set) var config: AppConfig
    public private(set) var active: Profile
    private var modes: [String: InteractionMode] = [:]
    /// Selected slot index per profile (nil = no slot).
    private var slots: [String: Int] = [:]

    public init(config: AppConfig) {
        self.config = config
        active = Self.fallback(in: config)
    }

    public mutating func reload(_ config: AppConfig) {
        let activeID = active.id
        self.config = config
        active = config.profiles.first { $0.id == activeID } ?? Self.fallback(in: config)
        modes = modes.filter { id, _ in config.profiles.contains { $0.id == id } }
        slots = slots.filter { id, _ in config.profiles.contains { $0.id == id } }
        position = channelPosition
    }

    // MARK: Channels (orange, One-Pager 004 §4)

    /// The channel you are on: the one you jumped to with orange, or the one whose window is in
    /// front. nil = free: the voice goes wherever the cursor is, with no jump.
    private var position: Int?

    public var channels: [Channel] { config.channels }

    public var channelPosition: Int? {
        position.flatMap { config.channels.indices.contains($0) ? $0 : nil }
    }

    /// nil while free.
    public var channel: Channel? { channelPosition.map { config.channels[$0] } }

    /// You are on this channel (nil = free). Also used when the window in front changes.
    public mutating func setFocus(_ index: Int?) {
        position = index.flatMap { config.channels.indices.contains($0) ? $0 : nil }
    }

    public mutating func select(channel index: Int) { setFocus(index) }

    /// The channel `window` belongs to: the most specific one that matches it (a session beats a
    /// whole app), nil if none does, which means free.
    public func channelIndex(forWindow window: Channel) -> Int? {
        var best: (index: Int, specificity: Int)?
        for (index, channel) in config.channels.enumerated() where channel.matches(window: window) {
            if best == nil || channel.specificity > best!.specificity { best = (index, channel.specificity) }
        }
        return best?.index
    }

    /// From free it goes to the first channel.
    public mutating func nextChannel() {
        let count = config.channels.count
        guard count > 0 else { position = nil; return }
        position = channelPosition.map { ($0 + 1) % count } ?? 0
    }

    /// From free it goes to the last channel.
    public mutating func previousChannel() {
        let count = config.channels.count
        guard count > 0 else { position = nil; return }
        position = channelPosition.map { ($0 + count - 1) % count } ?? count - 1
    }

    public struct BindOutcome: Equatable, Sendable {
        public enum Kind: Sendable { case added, updated, replaced }
        public let index: Int
        public let kind: Kind
    }

    /// Binds a window. The same window again updates its channel. A new one takes the next free
    /// channel; with all four taken it replaces the channel you are on (the last one if free).
    @discardableResult
    public mutating func bind(_ channel: Channel) -> BindOutcome {
        if let existing = config.channels.firstIndex(where: { $0.sameTarget(as: channel) }) {
            config.channels[existing] = channel
            position = existing
            return BindOutcome(index: existing, kind: .updated)
        }
        if config.channels.count < Channel.maxCount {
            config.channels.append(channel)
            position = config.channels.count - 1
            return BindOutcome(index: config.channels.count - 1, kind: .added)
        }
        let target = channelPosition ?? Channel.maxCount - 1
        config.channels[target] = channel
        position = target
        return BindOutcome(index: target, kind: .replaced)
    }

    /// Removes the channel you are on; true if there was one. You are free afterwards.
    @discardableResult
    public mutating func unbindChannel() -> Bool {
        guard let index = channelPosition else { return false }
        config.channels.remove(at: index)
        position = nil
        return true
    }

    /// Unbinds all channels and returns them, so the app can offer to undo.
    @discardableResult
    public mutating func clearChannels() -> [Channel] {
        let removed = config.channels
        config.channels = []
        position = nil
        return removed
    }

    /// Puts back channels removed by `clearChannels` (only if none were bound since).
    public mutating func restoreChannels(_ channels: [Channel]) {
        guard config.channels.isEmpty else { return }
        config.channels = Array(channels.prefix(Channel.maxCount))
        position = nil
    }

    private static func fallback(in config: AppConfig) -> Profile {
        config.profiles.first { $0.apps.isEmpty } ?? config.profiles.first ?? Profile(id: "default", name: "Generale")
    }

    /// Returns true if the active profile changed.
    @discardableResult
    public mutating func activate(bundleID: String?) -> Bool {
        let profile = bundleID.flatMap { id in config.profiles.first { $0.apps.contains(id) } }
            ?? Self.fallback(in: config)
        guard profile.id != active.id else { return false }
        active = profile
        return true
    }

    // MARK: Interaction mode (orange)

    public var mode: InteractionMode {
        let enabled = active.interaction.enabled
        if let chosen = modes[active.id], enabled.contains(chosen) { return chosen }
        return enabled.contains(active.interaction.defaultMode) ? active.interaction.defaultMode : (enabled.first ?? .dictation)
    }

    public mutating func cycleMode() {
        let enabled = active.interaction.enabled
        guard !enabled.isEmpty else { return }
        let index = enabled.firstIndex(of: mode) ?? -1
        modes[active.id] = enabled[(index + 1) % enabled.count]
    }

    public mutating func resetMode() {
        modes[active.id] = nil
    }

    public mutating func select(mode: InteractionMode) {
        guard active.interaction.enabled.contains(mode) else { return }
        modes[active.id] = mode
    }

    // MARK: Slots (white)

    public var slotIndex: Int? {
        guard let i = slots[active.id], active.slots.indices.contains(i) else { return nil }
        return i
    }

    public var slot: Slot? { slotIndex.map { active.slots[$0] } }

    /// Slot number shown on the white LEDs in binary (1…15), nil = none.
    public var slotNumber: Int? { slotIndex.map { $0 + 1 } }

    /// none → 1 → 2 … → last → none
    public mutating func nextSlot() {
        guard !active.slots.isEmpty else { return }
        let next = (slotIndex ?? -1) + 1
        slots[active.id] = next < active.slots.count ? next : nil
    }

    /// none → last → … → 1 → none
    public mutating func previousSlot() {
        guard !active.slots.isEmpty else { return }
        if let i = slotIndex {
            slots[active.id] = i > 0 ? i - 1 : nil
        } else {
            slots[active.id] = active.slots.count - 1
        }
    }

    public mutating func clearSlot() {
        slots[active.id] = nil
    }

    public mutating func select(slot index: Int?) {
        slots[active.id] = index.flatMap { active.slots.indices.contains($0) ? $0 : nil }
    }

    // MARK: Labels

    public var modeName: String { mode.label }
    public var slotName: String { slot?.name ?? "No slot" }

    /// Logical LED mask for the idle state (see `LedPattern`).
    public var idleLEDs: UInt8 { LedPattern.idle(channel: channelPosition, slot: slotNumber) }

    /// The configured action for a gesture in the active profile (nil = handled elsewhere).
    public func action(for gesture: Gesture) -> Action? {
        switch gesture {
        case .tap(.orange): return active.orange.tap
        case .doubleTap(.orange): return active.orange.doubleTap
        case .longPress(.orange): return active.orange.longPress
        case .veryLongPress(.orange): return active.orange.veryLongPress
        case .veryLongPress(.white): return active.white.veryLongPress
        case .veryLongPress(.grey): return active.grey.veryLongPress
        case .tap(.white): return active.white.tap
        case .doubleTap(.white): return active.white.doubleTap
        case .longPress(.white): return active.white.longPress
        case .tap(.grey): return active.grey.tap
        case .doubleTap(.grey): return active.grey.doubleTap
        case .longPress(.grey): return active.grey.longPress
        case .chordGrey: return active.chord
        case .handleDoubleClick: return active.handle.doubleClick
        case .shake: return active.shake.short
        case .shakeHold: return active.shake.hold
        case .pttDown, .pttUp: return nil
        }
    }
}

/// LED masks. Logical bits: 0–3 = red LEDs top→bottom, 4–7 = white LEDs top→bottom.
/// `physical(_:map:)` converts to `ui.led_level` indices using `device.ledMap`.
public enum LedPattern {
    public static func red(_ index: Int) -> UInt8 { index >= 0 && index < 4 ? UInt8(1) << UInt8(index) : 0 }

    /// Slot number 1…15 in binary on the white LEDs (top LED = 1, then 2, 4, 8).
    public static func white(slot: Int?) -> UInt8 {
        guard let slot, slot > 0 else { return 0 }
        return UInt8(slot & 0x0F) << 4
    }

    public static func idle(mode: InteractionMode, slot: Int?) -> UInt8 {
        red(mode.ledIndex) | white(slot: slot)
    }

    /// Idle: the red LED of the channel you are on (0 = top; none while free) and the slot in binary.
    public static func idle(channel: Int?, slot: Int?) -> UInt8 {
        (channel.map(red) ?? 0) | white(slot: slot)
    }

    /// Recording: one red LED sweeping up and down (0 1 2 3 2 1 …).
    public static func kitt(frame: Int, slot: Int?) -> UInt8 {
        let sweep = [0, 1, 2, 3, 2, 1]
        return red(sweep[((frame % sweep.count) + sweep.count) % sweep.count]) | white(slot: slot)
    }

    /// LLM processing: alternating 1+3 / 2+4 red LEDs.
    public static func processing(frame: Int, slot: Int?) -> UInt8 {
        (frame % 2 == 0 ? 0b0101 : 0b1010) | white(slot: slot)
    }

    /// Connection "boot": one LED at a time down the column (red 1–4, then white 1–4).
    public static let bootFrames = 8
    public static func boot(frame: Int) -> UInt8 {
        frame >= 0 && frame < bootFrames ? UInt8(1) << UInt8(frame) : 0
    }

    /// Error: all red LEDs blinking (on for even frames).
    public static func error(frame: Int) -> UInt8 {
        frame % 2 == 0 ? 0x0F : 0
    }

    /// Maps logical bits to physical `led_level` indices.
    public static func physical(_ logical: UInt8, map: [Int]) -> UInt8 {
        guard map.count == 8 else { return logical }
        var out: UInt8 = 0
        for bit in 0..<8 where logical & (1 << bit) != 0 {
            out |= 1 << UInt8(map[bit])
        }
        return out
    }
}

/// Builds the chat messages for post-processing (TDD §3.4).
public enum PromptComposer {
    public struct Context: Sendable {
        public var appName: String
        public var language: String
        public var date: String
        public init(appName: String, language: String, date: String) {
            self.appName = appName
            self.language = language
            self.date = date
        }
    }

    public static func messages(base: String, mode: PromptPreset, style: PromptPreset?, context: Context,
                                transcript: String, selection: String?) -> (system: String, user: String) {
        var system = base + "\n\n## Instruction: " + mode.prompt
        if let style, !style.prompt.isEmpty { system += "\n## Style: " + style.prompt }
        if selection != nil {
            system += "\n## Task: apply the dictated instruction to the given text and reply with the modified text only."
        }
        system += "\n## Context: app=\(context.appName), language=\(context.language), date=\(context.date)"
        let user: String
        if let selection {
            user = "Text:\n\(selection)\n\nInstruction:\n\(transcript)"
        } else {
            user = transcript
        }
        return (system, user)
    }

    /// Extra Whisper vocabulary for voice commands: command words are often English or short and
    /// get misheard ("bullet point" → "ballet point").
    public static let commandVocabulary = [
        "bullet point", "elenco puntato", "punto elenco", "elenco numerato", "a capo", "nuova riga",
        "nuovo paragrafo", "seleziona", "deseleziona", "cancella", "grassetto", "corsivo", "annulla", "ripeti",
    ]

    /// What the model needs to know to turn a spoken command into actions (One-Pager 004 §6.3).
    public struct CommandContext: Sendable {
        public var appName: String
        public var language: String
        /// Names of the bound channels, of the slots of the active profile and of its intents.
        public var channels: [String]
        public var slots: [String]
        public var intents: [String]
        /// The selected text, if any (cut to `maxSelection`).
        public var selection: String?
        public var hints: String

        public static let maxSelection = 2000

        public init(appName: String, language: String, channels: [String] = [], slots: [String] = [],
                    intents: [String] = [], selection: String? = nil, hints: String = "") {
            self.appName = appName
            self.language = language
            self.channels = channels
            self.slots = slots
            self.intents = intents
            self.selection = selection.map { String($0.prefix(Self.maxSelection)) }
            self.hints = hints
        }
    }

    /// Voice command (grey pressed while talking): the model answers with a JSON list of actions
    /// from a closed vocabulary, which `CommandParser` validates. The instructions are in English
    /// and language-neutral: the request can come in any language Whisper recognises.
    public static func commandMessages(context: CommandContext, transcript: String) -> (system: String, user: String) {
        func list(_ items: [String]) -> String { items.isEmpty ? "(none)" : items.map { "\"\($0)\"" }.joined(separator: ", ") }
        var system = """
        You turn a spoken command into actions on a Mac. The command can be in any language and comes from \
        speech recognition, so it may contain mistakes: interpret words that sound alike.
        Reply ONLY with valid JSON, with nothing before or after, in this form:
        {"actions": [{"type": "text", "text": "..."}, {"type": "key", "keys": ["shift+return"]}]}
        Action types:
        - "text": types the text in the focused field.
        - "key": presses the shortcuts in order. Modifiers: cmd, shift, opt, ctrl. \
        Keys: letters, digits, return, tab, space, delete, forwarddelete, escape, left, right, up, down, home, end.
        - "replaceSelection": replaces the selected text with the given text. Only when SELECTION is not "(none)".
        - "switchChannel": goes to one of the CHANNELS (field "name").
        - "runSlot": runs one of the SLOTS (field "name").
        - "intent": does one of the INTENTS (field "name").
        Rules:
        - Use only the actions the command needs, in the shortest order. Never add selections, deletions or keys it does not ask for.
        - Names must be copied exactly from the lists. If none matches, answer {"actions": []}.
        - A command that mentions a channel (or part of its name), as in "go to X", "switch to X" or "passa a X", is "switchChannel". \
        One that names a slot ("run X", "lancia X") is "runSlot". Stopping, interrupting or starting a new session uses an INTENT if one fits.
        - "text" is ONLY for two cases: the command starts with "write", "type", "scrivi", "escribe", "écris" or similar \
        (type everything after it as it is, in its own language), or it asks for a list marker such as "- " or "1. ". \
        Never type anything else: never answer questions, never invent or complete content.
        - A question, a chat or anything you cannot do with these actions is {"actions": []}. When unsure, do nothing: \
        {"actions": []} is always better than a wrong action.
        - "return" alone SENDS the message. A new line is always "shift+return".
        - If the command changes the selected text (translate, shorten, rewrite, fix, make a list), use "replaceSelection" \
        with the new text only. "Delete it" on a selection is key "delete".
        - Delete, remove and cancel never type text: they use keys.
        - If nothing fits, answer {"actions": []}.
        Examples (command -> answer):
        "new line" / "vai a capo" / "nouvelle ligne" -> {"actions":[{"type":"key","keys":["shift+return"]}]}
        "send" / "invia" / "enviar" -> {"actions":[{"type":"key","keys":["return"]}]}
        "select all" / "seleziona tutto" -> {"actions":[{"type":"key","keys":["cmd+a"]}]}
        "delete the last word" / "cancella l'ultima parola" -> {"actions":[{"type":"key","keys":["opt+delete"]}]}
        "delete the line" / "cancella la riga" -> {"actions":[{"type":"key","keys":["cmd+shift+left","delete"]}]}
        "delete everything" / "cancella tutto" -> {"actions":[{"type":"key","keys":["cmd+a","delete"]}]}
        "go to the end of the line" / "vai a fine riga" -> {"actions":[{"type":"key","keys":["cmd+right"]}]}
        "undo" / "annulla" -> {"actions":[{"type":"key","keys":["cmd+z"]}]}
        "bullet list" / "elenco puntato" -> {"actions":[{"type":"text","text":"- "}]}
        "numbered list" / "elenco numerato" -> {"actions":[{"type":"text","text":"1. "}]}
        "write see you soon" / "scrivi a presto" -> {"actions":[{"type":"text","text":"see you soon"}]}
        "what is the weather" / "che tempo fa" -> {"actions":[]}
        "turn on dark mode" / "attiva la modalità scura" -> {"actions":[]}
        With SELECTION "buon lavoro a tutti": "translate to English" -> {"actions":[{"type":"replaceSelection","text":"good work everyone"}]}
        "copy" / "copia" -> {"actions":[{"type":"key","keys":["cmd+c"]}]}
        "paste" / "incolla" -> {"actions":[{"type":"key","keys":["cmd+v"]}]}
        ## Context
        App: \(context.appName). Language setting: \(context.language).
        CHANNELS: \(list(context.channels))
        SLOTS: \(list(context.slots))
        INTENTS: \(list(context.intents))
        SELECTION: \(context.selection.map { "\"\($0)\"" } ?? "(none)")
        """
        if !context.hints.isEmpty { system += "\n## App notes: \(context.hints)" }
        return (system, transcript)
    }

    /// Removes reasoning blocks and wrapping quotes/whitespace from a model response.
    public static func clean(_ response: String) -> String {
        var text = response
        while let start = text.range(of: "<think>"), let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // A closing tag without its opening one: everything before it is leaked reasoning.
        if let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let first = text.first, let last = text.last,
           (first == "\"" && last == "\"") || (first == "«" && last == "»") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

extension CommandStep {
    /// Short description for the pill, the history and the Settings test.
    public var summary: String {
        switch self {
        case .text(let text): return L.f("type «%@»", text)
        case .keys(let keys): return keys.joined(separator: " ")
        case .replaceSelection: return L.t("replace the selection")
        case .switchChannel(let name): return L.f("channel %@", name)
        case .runSlot(let name): return L.f("slot %@", name)
        case .intent(let name): return name
        }
    }
}

/// Finds the channel or slot a spoken name refers to. The model is told to copy names exactly,
/// but speech and small models drift ("progetto api" for "Claude · progetto-api").
public enum NameMatcher {
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The index of the best match: the exact name, the part after " · ", a name that contains
    /// the request, or (for names of 3+ letters) a request that contains the name.
    public static func index(of query: String, in names: [String]) -> Int? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        let normalized = names.map(normalize)
        if let i = normalized.firstIndex(of: q) { return i }
        if let i = normalized.firstIndex(where: { $0.components(separatedBy: " · ").last == q }) { return i }
        if let i = normalized.firstIndex(where: { $0.contains(q) }) { return i }
        return normalized.firstIndex { $0.count >= 3 && q.contains($0) }
    }
}

/// Validated output of a voice command.
public enum CommandStep: Equatable, Sendable {
    case text(String)
    case keys([String])
    /// Replaces the selected text with the transformed version.
    case replaceSelection(String)
    /// Names of a channel, a slot or an intent: checked by the app against its own lists.
    case switchChannel(String)
    case runSlot(String)
    case intent(String)
}

public enum CommandParser {
    public enum Failure: Error, Equatable {
        case notJSON
        case forbidden(String)
        case tooMany
    }

    /// Shortcuts that could close windows, quit apps or change the system: never executed.
    public static let forbidden: Set<String> = [
        "cmd+q", "cmd+w", "cmd+shift+w", "cmd+opt+w", "cmd+h", "cmd+m", "cmd+opt+escape", "cmd+opt+esc",
        "cmd+shift+q", "cmd+ctrl+q", "cmd+tab", "cmd+space", "cmd+shift+3", "cmd+shift+4", "cmd+shift+5",
        "cmd+n", "cmd+t", "cmd+s", "cmd+p", "cmd+o", "cmd+shift+delete", "cmd+delete",
    ]

    public static func parse(_ response: String) -> Result<[CommandStep], Failure> {
        guard let actions = firstActionsObject(in: PromptComposer.clean(response)) else { return .failure(.notJSON) }
        guard actions.count <= 20 else { return .failure(.tooMany) }
        var steps: [CommandStep] = []
        for action in actions {
            switch action["type"] as? String {
            case "text":
                if let t = action["text"] as? String, !t.isEmpty { steps.append(.text(t)) }
            case "key":
                let keys = (action["keys"] as? [String]) ?? ((action["keys"] as? String).map { [$0] } ?? [])
                for key in keys {
                    guard let combo = KeyCombo(key) else { return .failure(.notJSON) }
                    if forbidden.contains(normalized(combo)) { return .failure(.forbidden(key)) }
                }
                if !keys.isEmpty { steps.append(.keys(keys)) }
            case "replaceSelection":
                guard let t = action["text"] as? String else { return .failure(.notJSON) }
                steps.append(.replaceSelection(t))
            case "switchChannel", "runSlot", "intent":
                guard let name = action["name"] as? String, !name.isEmpty, name.count <= 80 else { return .failure(.notJSON) }
                switch action["type"] as? String {
                case "switchChannel": steps.append(.switchChannel(name))
                case "runSlot": steps.append(.runSlot(name))
                default: steps.append(.intent(name))
                }
            default:
                return .failure(.notJSON)
            }
        }
        return .success(steps)
    }

    /// The first balanced `{…}` block that decodes to `{"actions": [...]}`. Models sometimes wrap
    /// the JSON in code fences or repeat it.
    static func firstActionsObject(in text: String) -> [[String: Any]]? {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            guard chars[index] == "{" else { index += 1; continue }
            var depth = 0
            var inString = false
            var escaped = false
            var end: Int?
            for j in index..<chars.count {
                let c = chars[j]
                if inString {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                    continue
                }
                if c == "\"" { inString = true } else if c == "{" { depth += 1 } else if c == "}" {
                    depth -= 1
                    if depth == 0 { end = j; break }
                }
            }
            guard let end else { return nil }
            let candidate = String(chars[index...end])
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let actions = json["actions"] as? [[String: Any]] {
                return actions
            }
            index += 1
        }
        return nil
    }

    /// Canonical "cmd+shift+…+key" form, for the forbidden list.
    static func normalized(_ combo: KeyCombo) -> String {
        let order: [(KeyCombo.Modifier, String)] = [(.command, "cmd"), (.control, "ctrl"), (.option, "opt"), (.shift, "shift")]
        let mods = order.filter { combo.modifiers.contains($0.0) }.map(\.1)
        let key = combo.key == "esc" ? "escape" : (combo.key == "backspace" ? "delete" : combo.key)
        return (mods + [key]).joined(separator: "+")
    }
}
