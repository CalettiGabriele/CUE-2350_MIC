import Foundation
import os

public struct AgentLimits: Sendable {
    public var maxSteps: Int
    public var timeBudgetMs: Double
    public var temperature: Double?
    /// Tool calls run from one model answer; the rest are answered with an error.
    public var maxCallsPerStep = 10

    public init(maxSteps: Int = 8, timeBudgetMs: Double = 30000, temperature: Double? = 0) {
        self.maxSteps = maxSteps
        self.timeBudgetMs = timeBudgetMs
        self.temperature = temperature
    }

    public init(_ settings: AppConfig.Agent) {
        self.init(maxSteps: settings.maxSteps, timeBudgetMs: settings.timeBudgetMs, temperature: settings.temperature)
    }
}

/// A risky call waiting for the user's yes (grey) or no (shake, timeout).
public struct PendingAction: Equatable, Sendable {
    public var tool: String
    public var arguments: JSONValue
    public var summary: String
}

/// Progress for the island: which step, what is running, what is being confirmed.
public enum AgentEvent: Equatable, Sendable {
    case thinking(step: Int)
    case running(step: Int, summary: String)
    case ran(step: Int, summary: String, ok: Bool)
    case confirming(PendingAction)
}

/// One tool call as it happened, for the history and Settings › Try a command.
public struct TraceEntry: Codable, Equatable, Sendable {
    public var step: Int
    public var tool: String
    public var arguments: String
    public var ok: Bool
    public var result: String
    public var ms: Double
}

public enum AgentOutcome: Equatable, Sendable {
    /// `finish` with status done: the summary goes on the island.
    case done(String)
    /// Nothing could be done, or the user declined: the reason goes on the island.
    case cannot(String)
    /// Out of steps or time.
    case budget
    case cancelled
    /// The provider failed (unreachable, HTTP error, timeout).
    case failed(String)
}

public struct AgentRun: Sendable {
    public var outcome: AgentOutcome
    public var trace: [TraceEntry]
    public var modelCalls: Int
    public var modelMs: Double
    public var totalMs: Double
    public var promptTokens: Int
    public var completionTokens: Int

    /// `read_ui → click → finish`, for the history.
    public var path: String { trace.map(\.tool).joined(separator: " → ") }
}

/// The voice command agent (TDD voice command agent §3.5): the model calls tools, sees what they
/// did and goes on until it calls `finish`, answers without tools, or runs out of budget.
public struct AgentLoop: Sendable {
    public var provider: ChatProvider
    public var registry: ToolRegistry
    public var limits: AgentLimits
    public var context: ToolContext
    /// Asked before every risky call; false = declined. The time spent here is not counted.
    public var confirm: @Sendable (PendingAction) async -> Bool
    public var progress: @Sendable (AgentEvent) -> Void
    /// Milliseconds; replaceable in tests.
    public var clock: @Sendable () -> Double = { Date().timeIntervalSinceReferenceDate * 1000 }

    private static let log = Logger(subsystem: "com.fxmicbridge", category: "agent")

    public init(provider: ChatProvider, registry: ToolRegistry, limits: AgentLimits, context: ToolContext = ToolContext(),
                confirm: @escaping @Sendable (PendingAction) async -> Bool,
                progress: @escaping @Sendable (AgentEvent) -> Void = { _ in }) {
        self.provider = provider
        self.registry = registry
        self.limits = limits
        self.context = context
        self.confirm = confirm
        self.progress = progress
    }

    public func run(_ screen: ScreenContext, command: String) async -> AgentRun {
        await run(system: AgentPrompt.system, user: AgentPrompt.user(screen, command: command))
    }

    public func run(system: String, user: String) async -> AgentRun {
        let start = clock()
        var paused = 0.0
        var messages: [ChatMessage] = [.system(system), .user(user)]
        let tools = registry.specs + [AgentPrompt.finish, AgentPrompt.keepGoing]
        var run = AgentRun(outcome: .budget, trace: [], modelCalls: 0, modelMs: 0, totalMs: 0, promptTokens: 0,
                           completionTokens: 0)
        func end(_ outcome: AgentOutcome) -> AgentRun {
            run.outcome = outcome
            run.totalMs = clock() - start
            Self.log.notice("agent \(String(describing: outcome), privacy: .public) after \(run.modelCalls, privacy: .public) calls, \(run.totalMs, format: .fixed(precision: 0), privacy: .public) ms: \(run.path, privacy: .public)")
            return run
        }
        func overBudget() -> Bool { clock() - start - paused > limits.timeBudgetMs }

        for step in 1...max(1, limits.maxSteps) {
            if Task.isCancelled { return end(.cancelled) }
            if step > 1, overBudget() { return end(.budget) }
            progress(.thinking(step: step))
            let callStart = clock()
            var response: ChatResponse?
            for attempt in 1...2 where response == nil {
                // At temperature 0 a retry would repeat the same malformed answer: vary it.
                let temperature = attempt == 1 ? limits.temperature : max(limits.temperature ?? 0, 0.6)
                do {
                    response = try await provider.send(messages, tools: tools, temperature: temperature, maxTokens: nil)
                } catch {
                    if Task.isCancelled { return end(.cancelled) }
                    let retry = attempt == 1 && (error as? RetryableError)?.isRetryable == true
                    Self.log.error("agent model call failed\(retry ? ", retrying" : "", privacy: .public): \(error.localizedDescription, privacy: .public)")
                    if !retry { return end(.failed(error.localizedDescription)) }
                }
            }
            guard let response else { return end(.failed("no answer")) }
            run.modelCalls += 1
            run.modelMs += clock() - callStart
            run.promptTokens += response.promptTokens ?? 0
            run.completionTokens += response.completionTokens ?? 0
            if Task.isCancelled { return end(.cancelled) }

            // An answer without tools ends the loop: done if something was already done.
            guard !response.toolCalls.isEmpty else {
                let acted = run.trace.contains { $0.ok && registry.tool(named: $0.tool).map { $0.risk > .read } == true }
                let text = String(response.text.prefix(80))
                return end(acted ? .done(text) : .cannot(text))
            }
            messages.append(response.message)

            var failed = false
            var acted = false
            var wantsResults = false
            var finishing: ToolCall?
            var summaries: [String] = []
            for (index, call) in response.toolCalls.enumerated() {
                if call.name == AgentPrompt.finish.name {
                    finishing = call
                    messages.append(.tool(callID: call.id, "ok"))
                    continue
                }
                if call.name == AgentPrompt.keepGoing.name {
                    wantsResults = true
                    messages.append(.tool(callID: call.id, "ok"))
                    continue
                }
                guard index < limits.maxCallsPerStep else {
                    messages.append(.tool(callID: call.id, "error: too many calls in one answer, not run"))
                    failed = true
                    continue
                }
                let result = await perform(call, step: step, paused: &paused, trace: &run.trace)
                messages.append(.tool(callID: call.id, result.ok ? result.content : "error: " + result.content))
                failed = failed || !result.ok
                let arguments = JSONValue(json: call.arguments) ?? .object([:])
                if result.ok, let tool = registry.tool(named: call.name), tool.risk > .read, !tool.prepares(for: arguments) {
                    acted = true
                    summaries.append(tool.summary(for: arguments))
                }
                if Task.isCancelled { return end(.cancelled) }
            }

            if let finishing {
                let arguments = JSONValue(json: finishing.arguments) ?? .object([:])
                let summary = String((arguments["summary"]?.stringValue ?? "").prefix(80))
                run.trace.append(TraceEntry(step: step, tool: finishing.name, arguments: finishing.arguments, ok: !failed,
                                            result: summary, ms: 0))
                // A failed action next to finish: let the model see it and fix it.
                if !failed {
                    return end(arguments["status"]?.stringValue == "cannot" ? .cannot(summary) : .done(summary))
                }
            }
            // Actions that all worked end the command, unless the model asked to see the results:
            // a one-action command costs one short call (TDD §3.5, implicit finish).
            if acted, !failed, !wantsResults {
                return end(.done(String(summaries.joined(separator: ", ").prefix(80))))
            }
            if overBudget() { return end(.budget) }
        }
        return end(.budget)
    }

    /// Validates, confirms and runs one call; returns what the model is told.
    private func perform(_ call: ToolCall, step: Int, paused: inout Double, trace: inout [TraceEntry]) async -> ToolResult {
        func record(_ result: ToolResult, ms: Double = 0) -> ToolResult {
            trace.append(TraceEntry(step: step, tool: call.name, arguments: call.arguments, ok: result.ok,
                                    result: String(result.content.prefix(300)), ms: ms))
            return result
        }
        guard let tool = registry.tool(named: call.name) else {
            return record(.failed("unknown tool \(call.name)"))
        }
        let text = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arguments = text.isEmpty ? .object([:]) : JSONValue(json: text) else {
            return record(.failed("arguments are not valid JSON"))
        }
        if let problem = SchemaValidator.validate(arguments, against: tool.spec.inputSchema) {
            return record(.failed("invalid arguments: \(problem)"))
        }
        let risk = registry.risk(of: tool, arguments: arguments)
        let summary = tool.summary(for: arguments)
        if context.dryRun, risk > .read {
            progress(.ran(step: step, summary: summary, ok: true))
            return record(.ok("ok (simulated)"))
        }
        if risk == .risky {
            let pending = PendingAction(tool: call.name, arguments: arguments, summary: summary)
            progress(.confirming(pending))
            let waitStart = clock()
            let approved = await confirm(pending)
            paused += clock() - waitStart
            guard approved else { return record(.failed("the user declined this action")) }
        }
        progress(.running(step: step, summary: summary))
        let toolStart = clock()
        let result = await tool.run(arguments, context: context)
        progress(.ran(step: step, summary: summary, ok: result.ok))
        return record(result, ms: clock() - toolStart)
    }
}
