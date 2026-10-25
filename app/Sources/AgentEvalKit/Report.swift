import Foundation

/// One scored run of one case.
public struct EvalRun: Codable, Sendable {
    public var id: String
    public var group: String
    public var category: String
    public var lang: String
    public var command: String
    public var passed: Bool
    public var latencyMs: Double
    public var actions: [EvalAction]?
    public var note: String?
    public var raw: String

    public init(id: String, group: String, category: String, lang: String, command: String, passed: Bool,
                latencyMs: Double, actions: [EvalAction]?, note: String?, raw: String) {
        self.id = id
        self.group = group
        self.category = category
        self.lang = lang
        self.command = command
        self.passed = passed
        self.latencyMs = latencyMs
        self.actions = actions
        self.note = note
        self.raw = raw
    }
}

/// Accuracy and latency of a set of runs, written to the terminal and to a JSON file.
public struct EvalReport: Codable, Sendable {
    public var date: String
    public var engine: String
    public var model: String
    public var baseURL: String
    public var corpusVersion: Int
    public var repeats: Int
    public var runs: [EvalRun]

    public init(date: String, engine: String, model: String, baseURL: String, corpusVersion: Int,
                repeats: Int, runs: [EvalRun]) {
        self.date = date
        self.engine = engine
        self.model = model
        self.baseURL = baseURL
        self.corpusVersion = corpusVersion
        self.repeats = repeats
        self.runs = runs
    }

    public struct Line: Sendable {
        public var label: String
        public var passed: Int
        public var total: Int
        public var p50: Double
        public var p90: Double
        public var max: Double

        public var accuracy: Double { total == 0 ? 0 : Double(passed) / Double(total) }
    }

    public static func line(_ label: String, _ runs: [EvalRun]) -> Line {
        // Runs that never reached the model have no meaningful latency.
        let times = runs.filter { $0.actions != nil }.map(\.latencyMs).sorted()
        func percentile(_ p: Double) -> Double {
            times.isEmpty ? 0 : times[min(times.count - 1, Int((Double(times.count - 1) * p).rounded()))]
        }
        return Line(label: label, passed: runs.filter(\.passed).count, total: runs.count,
                    p50: percentile(0.5), p90: percentile(0.9), max: times.last ?? 0)
    }

    /// Overall, by group, by category and by language.
    public var lines: [(section: String, lines: [Line])] {
        func grouped(_ key: (EvalRun) -> String) -> [Line] {
            Dictionary(grouping: runs, by: key).sorted { $0.key < $1.key }.map { Self.line($0.key, $0.value) }
        }
        return [("overall", [Self.line("all", runs)]), ("group", grouped(\.group)),
                ("category", grouped { "\($0.group)/\($0.category)" }), ("language", grouped(\.lang))]
    }

    public func text() -> String {
        var out = "engine \(engine) · model \(model) · \(baseURL) · corpus v\(corpusVersion) · \(runs.count) runs (×\(repeats))\n"
        for (section, lines) in lines {
            out += "\n\(section.uppercased())\n"
            out += "  " + "".padding(toLength: 26, withPad: " ", startingAt: 0) + "  ok/total   acc   p50 ms  p90 ms  max ms\n"
            for l in lines {
                out += "  " + l.label.padding(toLength: 26, withPad: " ", startingAt: 0)
                out += String(format: "  %3d/%-4d  %4.0f%%  %6.0f  %6.0f  %6.0f\n",
                              l.passed, l.total, l.accuracy * 100, l.p50, l.p90, l.max)
            }
        }
        let failures = runs.filter { !$0.passed }
        if !failures.isEmpty {
            out += "\nFAILURES\n"
            for f in failures {
                let got = f.actions.map { $0.isEmpty ? "(no action)" : $0.map(\.summary).joined(separator: " → ") } ?? "(no answer)"
                out += "  \(f.id) «\(f.command)» → \(got)\(f.note.map { " [\($0)]" } ?? "")\n"
            }
        }
        return out
    }
}
