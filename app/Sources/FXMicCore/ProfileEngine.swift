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
    public var idleLEDs: UInt8 { LedPattern.idle(mode: mode, slot: slotNumber) }

    /// The configured action for a gesture in the active profile (nil = handled elsewhere).
    public func action(for gesture: Gesture) -> Action? {
        switch gesture {
        case .tap(.orange): return active.orange.tap
        case .doubleTap(.orange): return active.orange.doubleTap
        case .longPress(.orange): return active.orange.longPress
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

    /// Extra Whisper vocabulary while in "Comando" mode: command words are often English or
    /// short and get misheard ("bullet point" → "ballet point").
    public static let commandVocabulary = [
        "bullet point", "elenco puntato", "punto elenco", "elenco numerato", "a capo", "nuova riga",
        "nuovo paragrafo", "seleziona", "deseleziona", "cancella", "grassetto", "corsivo", "annulla", "ripeti",
    ]

    /// "Comando" mode: the model answers with a JSON list of actions (One-Pager 001 §1).
    public static func commandMessages(hints: String, context: Context, transcript: String) -> (system: String, user: String) {
        let system = """
        Trasformi un comando vocale in azioni di tastiera da eseguire nel campo di testo attivo di macOS.
        Rispondi SOLO con JSON valido, senza testo prima o dopo, in questa forma:
        {"actions": [{"type": "text", "text": "..."}, {"type": "key", "keys": ["shift+return"]}]}
        Tipi ammessi:
        - "text": scrive il testo indicato.
        - "key": preme le combinazioni indicate, in ordine. Modificatori: cmd, shift, opt, ctrl. \
        Tasti: lettere, cifre, return, tab, space, delete, forwarddelete, escape, left, right, up, down, home, end.
        Regole:
        - Il comando arriva da una trascrizione vocale e può contenere errori: interpreta parole simili \
        nel suono ("ballet point", "bullet poin", "punto lista" = elenco puntato).
        - Usa solo le azioni necessarie, nell'ordine minimo: non aggiungere selezioni, cancellazioni \
        o altri tasti che il comando non chiede ("deseleziona" non deve mai premere cmd+a).
        - "aggiungi" / "inserisci" + elemento di formattazione (elenco, bullet point, riga, grassetto) \
        significa inserire quella formattazione, non scrivere le parole.
        - "elimina", "cancella", "togli", "rimuovi" non scrivono mai testo: usano solo tasti.
        - Se c'è già una selezione ("cancellalo", "cancella la selezione") basta delete.
        - Se il comando inizia con "scrivi" o "detta", scrivi tutto il testo che segue così com'è, \
        anche se contiene altre parole di comando.
        - Se il comando non è eseguibile con queste azioni rispondi {"actions": []}.
        Esempi (comando -> risposta):
        "elenco puntato" / "bullet point" / "punto elenco" -> {"actions":[{"type":"text","text":"- "}]}
        "aggiungi un bullet point" / "aggiungi ballet point" / "inserisci un punto elenco" -> {"actions":[{"type":"key","keys":["shift+return"]},{"type":"text","text":"- "}]}
        "elenco numerato" -> {"actions":[{"type":"text","text":"1. "}]}
        "vai a capo" / "nuova riga" -> {"actions":[{"type":"key","keys":["shift+return"]}]}
        "nuovo paragrafo" -> {"actions":[{"type":"key","keys":["shift+return","shift+return"]}]}
        "invia" -> {"actions":[{"type":"key","keys":["return"]}]}
        "seleziona tutto" -> {"actions":[{"type":"key","keys":["cmd+a"]}]}
        "deseleziona" / "deseleziona tutto" / "togli la selezione" -> {"actions":[{"type":"key","keys":["right"]}]}
        "seleziona l'ultima parola" -> {"actions":[{"type":"key","keys":["opt+shift+left"]}]}
        "vai alla fine della riga" / "in fondo alla frase" -> {"actions":[{"type":"key","keys":["cmd+right"]}]}
        "vai all'inizio della riga" -> {"actions":[{"type":"key","keys":["cmd+left"]}]}
        "vai alla fine del testo" -> {"actions":[{"type":"key","keys":["cmd+down"]}]}
        "vai all'inizio del testo" -> {"actions":[{"type":"key","keys":["cmd+up"]}]}
        "parola precedente" -> {"actions":[{"type":"key","keys":["opt+left"]}]}
        "parola successiva" -> {"actions":[{"type":"key","keys":["opt+right"]}]}
        "cancella l'ultima parola" -> {"actions":[{"type":"key","keys":["opt+delete"]}]}
        "cancella la riga" -> {"actions":[{"type":"key","keys":["cmd+shift+left","delete"]}]}
        "cancella tutto" -> {"actions":[{"type":"key","keys":["cmd+a","delete"]}]}
        "elimina il bullet point" / "togli il punto elenco" / "rimuovi l'elenco" -> {"actions":[{"type":"key","keys":["cmd+left","forwarddelete","forwarddelete"]}]}
        "cancellalo" / "cancella la selezione" -> {"actions":[{"type":"key","keys":["delete"]}]}
        "annulla" -> {"actions":[{"type":"key","keys":["cmd+z"]}]}
        "ripeti" -> {"actions":[{"type":"key","keys":["cmd+shift+z"]}]}
        "copia" -> {"actions":[{"type":"key","keys":["cmd+c"]}]}
        "incolla" -> {"actions":[{"type":"key","keys":["cmd+v"]}]}
        "grassetto" -> {"actions":[{"type":"text","text":"****"},{"type":"key","keys":["left","left"]}]}
        "scrivi buongiorno a tutti" -> {"actions":[{"type":"text","text":"buongiorno a tutti"}]}
        "scrivi aggiungi il latte alla lista" -> {"actions":[{"type":"text","text":"aggiungi il latte alla lista"}]}
        "inserisci un elenco puntato" -> {"actions":[{"type":"key","keys":["shift+return"]},{"type":"text","text":"- "}]}
        ## Contesto: app=\(context.appName), lingua=\(context.language)
        """ + (hints.isEmpty ? "" : "\n## Note sull'app: \(hints)")
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

/// Validated output of "Comando" mode.
public enum CommandStep: Equatable, Sendable {
    case text(String)
    case keys([String])
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
