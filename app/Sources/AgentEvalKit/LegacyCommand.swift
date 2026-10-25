import FXMicCore
import Foundation

/// The one-call voice command the app used until the agent replaced it (TDD voice command agent
/// §7): one model call answers with a JSON of actions, validated here. Kept in the evaluation only,
/// so the phase 0 baseline can be measured again (`AgentEval --engine legacy`).
public enum LegacyCommand {
    public enum Step: Equatable, Sendable {
        case text(String)
        case keys([String])
        case replaceSelection(String)
        case switchChannel(String)
        case runSlot(String)
        case intent(String)
    }

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
    public static func messages(context: CommandContext, transcript: String) -> (system: String, user: String) {
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


    public enum Failure: Error, Equatable {
        case notJSON
        case forbidden(String)
        case tooMany
    }


    public static func parse(_ response: String) -> Result<[Step], Failure> {
        guard let actions = firstActionsObject(in: PromptComposer.clean(response)) else { return .failure(.notJSON) }
        guard actions.count <= 20 else { return .failure(.tooMany) }
        var steps: [Step] = []
        for action in actions {
            switch action["type"] as? String {
            case "text":
                if let t = action["text"] as? String, !t.isEmpty { steps.append(.text(t)) }
            case "key":
                let keys = (action["keys"] as? [String]) ?? ((action["keys"] as? String).map { [$0] } ?? [])
                for key in keys {
                    guard let combo = KeyCombo(key) else { return .failure(.notJSON) }
                    if combo.isBlocked { return .failure(.forbidden(key)) }
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
}
