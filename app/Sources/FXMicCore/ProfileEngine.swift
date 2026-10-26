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
    /// Free (no channel in front): every red LED lit.
    public static let allRed: UInt8 = 0b0000_1111
    public static func red(_ index: Int) -> UInt8 { index >= 0 && index < 4 ? UInt8(1) << UInt8(index) : 0 }

    /// Slot number 1…15 in binary on the white LEDs (top LED = 1, then 2, 4, 8).
    public static func white(slot: Int?) -> UInt8 {
        guard let slot, slot > 0 else { return 0 }
        return UInt8(slot & 0x0F) << 4
    }

    public static func idle(mode: InteractionMode, slot: Int?) -> UInt8 {
        red(mode.ledIndex) | white(slot: slot)
    }

    /// Idle: the red LED of the channel you are on (0 = top; all four while free) and the slot in binary.
    public static func idle(channel: Int?, slot: Int?) -> UInt8 {
        (channel.map(red) ?? allRed) | white(slot: slot)
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

/// What the voice command asks the app itself to do: go to a channel, run a slot, do an intent.
public enum CommandStep: Equatable, Sendable {
    case switchChannel(String)
    case runSlot(String)
    case intent(String)
}

extension KeyCombo {
    /// Shortcuts that could close windows, quit apps or change the system: never pressed by the
    /// voice command.
    public static let blocked: Set<String> = [
        "cmd+q", "cmd+w", "cmd+shift+w", "cmd+opt+w", "cmd+h", "cmd+m", "cmd+opt+escape", "cmd+opt+esc",
        "cmd+shift+q", "cmd+ctrl+q", "cmd+tab", "cmd+space", "cmd+shift+3", "cmd+shift+4", "cmd+shift+5",
        "cmd+n", "cmd+t", "cmd+s", "cmd+p", "cmd+o", "cmd+shift+delete", "cmd+delete",
    ]

    /// "cmd+shift+…+key" with modifiers in a fixed order and key aliases resolved.
    public var canonical: String {
        let order: [(Modifier, String)] = [(.command, "cmd"), (.control, "ctrl"), (.option, "opt"), (.shift, "shift")]
        let mods = order.filter { modifiers.contains($0.0) }.map(\.1)
        let aliases = ["esc": "escape", "backspace": "delete", "enter": "return"]
        return (mods + [aliases[key] ?? key]).joined(separator: "+")
    }

    public var isBlocked: Bool { Self.blocked.contains(canonical) }
}
