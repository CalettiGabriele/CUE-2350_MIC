import Foundation

/// The voice-command evaluation set (TDD voice command agent §3.7): spoken commands, the screen
/// they are said on, and the tool calls that count as a right answer.
public struct Corpus: Codable, Sendable {
    public var version: Int
    public var screens: [String: Screen]
    public var cases: [EvalCase]

    public static func load(_ url: URL) throws -> Corpus {
        try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    /// Problems that make the corpus unusable: duplicate ids, unknown screens, empty expectations.
    public func problems() -> [String] {
        var seen = Set<String>()
        var problems: [String] = []
        for c in cases {
            if !seen.insert(c.id).inserted { problems.append("duplicate id \(c.id)") }
            if screens[c.screen] == nil { problems.append("\(c.id): unknown screen \(c.screen)") }
            if c.expect.isEmpty { problems.append("\(c.id): no expectation") }
            if !["today", "new"].contains(c.group) { problems.append("\(c.id): group must be today or new") }
        }
        return problems
    }
}

/// What is in front of the user when the command is said. The legacy one-call path only sees
/// app, profile, channels, intents and selection; the agent will also read the rest.
public struct Screen: Codable, Sendable {
    public var app: String
    /// Id of one of `Profile.defaults`: its slots, intents and hints are used.
    public var profile: String
    public var window: String?
    /// rich | markdown | plain (TDD §3.1).
    public var textFormat: String?
    /// The language setting passed to the model ("auto" when missing).
    public var language: String?
    public var channels: [String]?
    /// Intents added to the profile's own, e.g. "newSession".
    public var extraIntents: [String]?
    public var selection: String?
    public var fieldText: String?
    public var ui: [UIElement]?
    public var menus: [String]?
    public var windows: [Window]?
    public var userTools: [UserTool]?

    public struct UIElement: Codable, Sendable {
        public var id: String
        public var role: String
        public var title: String
    }

    public struct Window: Codable, Sendable {
        public var id: String
        public var title: String
    }

    public struct UserTool: Codable, Sendable {
        public var name: String
        public var description: String
        public var parameter: String?
    }
}

public struct EvalCase: Codable, Sendable {
    public var id: String
    /// "today": what the one-call path is meant to do (levels 1–3 and refusals);
    /// "new": what only the agent can do (formatting, UI, menus, windows, user tools, generation).
    public var group: String
    public var category: String
    public var lang: String
    public var command: String
    public var screen: String
    /// Alternatives: the answer is right if its actions match any of them. `[]` = do nothing.
    public var expect: [[StepMatcher]]
    public var note: String?
}

/// One expected action. Only the fields that are set are checked.
public struct StepMatcher: Codable, Sendable, Equatable {
    public var tool: String
    /// press_keys: the keys, in order (consecutive press_keys are merged before matching).
    public var keys: [String]?
    /// The "text" argument, compared loosely (case, accents, spaces, final punctuation).
    public var text: String?
    /// Every group must appear in the "text" argument; a group is one string or alternatives.
    public var textIncludes: [OneOrMany]?
    public var textExcludes: [String]?
    /// The "text" argument must be shorter than the screen's selection.
    public var shorterThanSelection: Bool?
    /// switch_channel / run_skill: resolved with `NameMatcher` like the app does; others: loose.
    public var name: String?
    /// Any other argument, compared loosely; a list means any of them.
    public var args: [String: OneOrMany]?

    public init(tool: String, keys: [String]? = nil, text: String? = nil, textIncludes: [OneOrMany]? = nil,
                textExcludes: [String]? = nil, shorterThanSelection: Bool? = nil, name: String? = nil,
                args: [String: OneOrMany]? = nil) {
        self.tool = tool
        self.keys = keys
        self.text = text
        self.textIncludes = textIncludes
        self.textExcludes = textExcludes
        self.shorterThanSelection = shorterThanSelection
        self.name = name
        self.args = args
    }
}

/// A JSON string or a list of strings.
public struct OneOrMany: Codable, Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
    public var values: [String]

    public init(_ values: [String]) { self.values = values }
    public init(stringLiteral value: String) { values = [value] }
    public init(arrayLiteral elements: String...) { values = elements }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let one = try? c.decode(String.self) { values = [one] } else { values = try c.decode([String].self) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if values.count == 1 { try c.encode(values[0]) } else { try c.encode(values) }
    }
}
