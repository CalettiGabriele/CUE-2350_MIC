import AgentEvalKit
import FXMicCore
import Foundation

// Runs the voice-command evaluation set against a real model (TDD voice command agent §3.7).
// Usage: swift run AgentEval [--corpus path] [--engine legacy] [--repeat n] [--filter text]
//                            [--base-url url [--preset ollama|openai|anthropic|…]] [--model name]
//                            [--out file.json] [--rescore report.json]
// The endpoint comes from the app's config.json unless overridden; an API key can be passed in
// AGENT_EVAL_API_KEY (never on the command line).

var options: [String: String] = [:]
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let flag = arguments.next() {
    guard flag.hasPrefix("--"), let value = arguments.next() else {
        FileHandle.standardError.write(Data("bad argument \(flag)\n".utf8))
        exit(2)
    }
    options[String(flag.dropFirst(2))] = value
}

let corpusURL = URL(fileURLWithPath: options["corpus"] ?? "scripts/agent-eval/corpus.json")
let corpus: Corpus
do {
    corpus = try Corpus.load(corpusURL)
} catch {
    FileHandle.standardError.write(Data("cannot read \(corpusURL.path): \(error)\n".utf8))
    exit(1)
}
let problems = corpus.problems()
guard problems.isEmpty else {
    FileHandle.standardError.write(Data((problems.joined(separator: "\n") + "\n").utf8))
    exit(1)
}

func save(_ report: EvalReport) throws {
    guard let out = options["out"] else { return }
    let url = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: url)
    print("saved \(url.path)")
}

// --rescore report.json: scores saved answers again with the current corpus, without the model.
if let path = options["rescore"] {
    var report = try JSONDecoder().decode(EvalReport.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let byID = Dictionary(uniqueKeysWithValues: corpus.cases.map { ($0.id, $0) })
    report.runs = report.runs.compactMap { run in
        guard let c = byID[run.id], let screen = corpus.screens[c.screen] else { return nil }
        var run = run
        run.passed = run.actions.map { Scorer.passes($0, c, screen: screen) } ?? false
        return run
    }
    report.corpusVersion = corpus.version
    print(report.text())
    try save(report)
    exit(0)
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/FXMicBridge/config.json")
let config = (try? JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))) ?? AppConfig()
var llm = config.llm
if let url = options["base-url"] {
    llm.active = LLMProvider(id: "cli", preset: options["preset"].flatMap(ProviderPreset.init(rawValue:)) ?? .custom,
                             baseURL: url)
}
if let model = options["model"] { llm.model = model }
let client = llm.client(apiKey: ProcessInfo.processInfo.environment["AGENT_EVAL_API_KEY"])

// --test-tools yes: one tool call, the same check as Settings › Model › Test tool calling.
if options["test-tools"] != nil {
    do {
        let ms = try await client.testToolCall()
        print(String(format: "tool calling works on %@ with %@ (%.0f ms)", client.provider.baseURL, client.model, ms))
        exit(0)
    } catch {
        print("tool calling failed on \(client.provider.baseURL) with \(client.model): \(error.localizedDescription)")
        exit(1)
    }
}

// --agent-smoke "command": one agent run with simulated tools on a Mail screen, trace printed.
if let command = options["agent-smoke"] {
    let screen = ScreenContext(app: "Mail", window: "Re: budget review", textFormat: "rich",
                               selection: "we need it by Friday",
                               fieldText: "Hi team,\nthe budget review is urgent and we need it by Friday.\nThanks")
    let loop = AgentLoop(provider: client, registry: ToolRegistry(SimulatedTool.basic()), limits: AgentLimits(config.agent),
                         confirm: { _ in true })
    let run = await loop.run(screen, command: command)
    for entry in run.trace {
        print(String(format: "  %d %@ %@ → %@ %@", entry.step, entry.tool, entry.arguments, entry.ok ? "ok" : "FAIL", entry.result))
    }
    print(String(format: "%@ · %d calls · model %.0f ms · total %.0f ms · %d+%d tokens", String(describing: run.outcome),
                 run.modelCalls, run.modelMs, run.totalMs, run.promptTokens, run.completionTokens))
    exit(0)
}

let engine: EvalEngine
switch options["engine"] ?? "legacy" {
case "legacy": engine = LegacyEngine(provider: client)
case "agent": engine = AgentEngine(provider: client, limits: AgentLimits(config.agent))
default:
    FileHandle.standardError.write(Data("unknown engine \(options["engine"]!)\n".utf8))
    exit(2)
}

let repeats = max(1, Int(options["repeat"] ?? "1") ?? 1)
let cases = corpus.cases.filter { c in
    guard let filter = options["filter"] else { return true }
    return c.id.contains(filter) || c.category == filter || c.group == filter || c.lang == filter
}

// Loads the model so the first case does not pay for it.
_ = try? await client.complete(system: "Reply only: ok", user: "ok", temperature: 0)

var runs: [EvalRun] = []
for round in 1...repeats {
    for (index, c) in cases.enumerated() {
        let screen = corpus.screens[c.screen]!
        let result = await engine.run(c, screen: screen)
        let passed = result.actions.map { Scorer.passes($0, c, screen: screen) } ?? false
        runs.append(EvalRun(id: c.id, group: c.group, category: c.category, lang: c.lang, command: c.command,
                            passed: passed, latencyMs: result.latencyMs, actions: result.actions,
                            note: result.note, raw: result.raw))
        let mark = passed ? "ok  " : "FAIL"
        print(String(format: "[%d/%d %@] %@ %5.0f ms  %@", index + 1, cases.count, "\(round)", mark,
                     result.latencyMs, c.id))
    }
}

let report = EvalReport(date: ISO8601DateFormatter().string(from: Date()), engine: engine.name,
                        model: client.model, baseURL: client.provider.baseURL, corpusVersion: corpus.version,
                        repeats: repeats, runs: runs)
print("\n" + report.text())
try save(report)
