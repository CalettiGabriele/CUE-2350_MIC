import AppKit
import FXMicCore
import Foundation
import os

/// What a dictation needs from the profile, frozen at push-to-talk time (TDD §3.5,
/// One-Pager 001: interaction mode and slot are the ones active at `pttDown`).
struct DictationContext {
    var profile: Profile
    var mode: InteractionMode
    /// Selected white slot, only if it applies to a dictation (template or llm).
    var slot: Slot?
    var appName: String
    var bundleID: String?
    /// Grey was pressed while talking: the dictation is a voice command, not text to write.
    var editSelection = false
    var selection: String?
    /// Names of the bound channels, for the voice command and for Whisper's vocabulary.
    var channels: [String] = []
    /// The channel whose window is in front (nil = free), and the front app's process.
    var channel: String?
    var pid: pid_t?
    /// Read when grey is pressed, for the agent's first call.
    var window: String?
    var fieldText: String?
}

/// Orchestrates record → transcribe → (LLM) → inject (TDD §3.5).
@MainActor
final class DictationController {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case processing
        case message(String)
        /// Something was written or run: a message, plus the orange "done" flash.
        case done(String)
        /// An error: same as a message, plus the LED error blink.
        case failure(String)
        /// The voice command agent at work: the step being run.
        case working(String)
    }

    var onPhase: ((Phase) -> Void)?
    /// A take started (true) or ended for any reason (false): the music pauses and resumes.
    var onHold: ((Bool) -> Void)?
    /// RMS level in dBFS while recording (called on the main queue).
    var onLevel: ((Float) -> Void)?
    /// Provides profile/mode/slot and the frontmost app at push-to-talk time.
    var contextProvider: (() -> DictationContext)?
    /// A template/llm slot was applied to a dictation: the app clears the selection.
    var onSlotConsumed: (() -> Void)?
    /// Runs the voice-command steps that need the app (channel, slot, intent); nil = not handled.
    var commandHandler: ((CommandStep) -> TextInjector.Outcome)?
    /// Asks the user before a risky agent action (RiskGate); nil = always no.
    var confirmAction: (@MainActor (PendingAction) async -> Bool)?
    var config: AppConfig {
        didSet {
            machine.minDurationMs = config.audio.minDurationMs
            recorder.inputDeviceUID = config.audio.inputDeviceUID
        }
    }
    /// Persistent history (TDD §3.9), newest first.
    let historyStore: HistoryStore
    var history: [HistoryEntry] { historyStore.entries }
    let transcriber = Transcriber()

    private let log = Logger(subsystem: "com.fxmicbridge", category: "dictation")
    let recorder = AudioRecorder()
    private var machine: DictationStateMachine
    private var job: Task<Void, Never>?
    private var context: DictationContext?
    private var lastInsertion: (bundleID: String?, date: Date)?

    init(config: AppConfig, historyStore: HistoryStore) {
        self.config = config
        self.historyStore = historyStore
        machine = DictationStateMachine(minDurationMs: config.audio.minDurationMs)
        recorder.inputDeviceUID = config.audio.inputDeviceUID
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.onLevel?(level) }
        }
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    var isRecording: Bool {
        if case .recording = machine.state { return true }
        return false
    }

    // MARK: - Push-to-talk

    func pttDown() {
        switch machine.send(.pttDown(at: now())) {
        case .startRecording:
            context = contextProvider?()
            do {
                try recorder.start()
                onHold?(true)
                onPhase?(.recording)
            } catch {
                _ = machine.send(.failed)
                onPhase?(.failure(L.t("Microphone not available")))
                log.error("recorder start failed: \(error.localizedDescription, privacy: .public)")
            }
        case .busy:
            NSSound.beep()
        default:
            break
        }
    }

    /// Grey pressed while talking: the dictation becomes a voice command (One-Pager 004 §6).
    func markEditSelection() {
        guard isRecording, context?.editSelection == false else { return }
        context?.editSelection = true
        onPhase?(.message(L.t("Voice command")))
        // The model is usually loaded already; this only makes sure it stays so.
        config.llm.client.warmUp()
        Task { [weak self] in
            let selection = await TextInjector.readSelection()
            self?.context?.selection = selection
            if selection == nil { self?.log.notice("edit selection: nothing selected") }
            guard let self else { return }
            let pid = self.context?.pid
            self.context?.window = ScreenSnapshot.windowTitle(pid: pid)
            self.context?.fieldText = ScreenSnapshot.fieldText()
        }
    }

    func pttUp() {
        guard isRecording else { return }
        let releasedAt = now()
        let effect = machine.send(.pttUp(at: releasedAt))
        let audio = recorder.stop()
        onHold?(false)
        switch effect {
        case .discardRecording(let reason):
            // Handle clicks (double-click = new line) are short takes: don't flash a message.
            onPhase?(reason == "too short" ? .idle : .message(L.f("Discarded: %@", L.t(reason))))
        case .stopRecordingAndTranscribe:
            transcribe(audio, releasedAt: releasedAt)
        default:
            onPhase?(.idle)
        }
    }

    func cancel() {
        let wasRecording = isRecording
        if case .discardRecording = machine.send(.cancel) {
            if wasRecording { _ = recorder.stop(); onHold?(false) }
            job?.cancel()
            onPhase?(.message(L.t("Cancelled")))
        }
    }

    // MARK: - Pipeline

    private func transcribe(_ audio: [Float], releasedAt: Double) {
        guard let context else { return }
        let level = AudioRecorder.rmsDBFS(audio)
        let peak = audio.reduce(0) { max($0, abs($1)) }
        log.notice("recorded \(Double(audio.count) / AudioRecorder.sampleRate, format: .fixed(precision: 1), privacy: .public)s, rms \(level, format: .fixed(precision: 1), privacy: .public) dBFS, peak \(peak, format: .fixed(precision: 3), privacy: .public) (threshold \(self.config.audio.silenceThresholdDBFS, format: .fixed(precision: 0), privacy: .public))")
        guard level >= config.audio.silenceThresholdDBFS else {
            _ = machine.send(.transcribed(text: "", usesLLM: false))
            // Exactly zero samples is not a quiet voice: the microphone is blocked or muted.
            onPhase?(.message(peak == 0 ? L.t("Microphone is silent: check its permission and input") : L.t("No speech")))
            return
        }
        onPhase?(.transcribing)
        let languageSetting = context.profile.language ?? config.speech.language
        let language = languageSetting == "auto" ? nil : languageSetting
        // Commands add command words, channel and slot names, which Whisper often mishears.
        let isCommand = context.editSelection || context.mode == .command
        let vocabulary = config.speech.vocabulary
            + (isCommand ? PromptComposer.commandVocabulary + context.channels + context.profile.slots.map(\.name) : [])
        let seconds = Double(audio.count) / AudioRecorder.sampleRate
        job = Task { [weak self, transcriber] in
            do {
                let raw = try await transcriber.transcribe(audio, language: language, vocabulary: vocabulary)
                guard !Task.isCancelled else { return }
                self?.log.notice("transcribed \(raw.count, privacy: .public) characters")
                await self?.postProcess(raw: raw, languageSetting: languageSetting, releasedAt: releasedAt, seconds: seconds)
            } catch {
                guard let self, !Task.isCancelled else { return }
                _ = self.machine.send(.failed)
                self.onPhase?(.failure(L.t("Transcription error")))
                self.log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func postProcess(raw: String, languageSetting: String, releasedAt: Double, seconds: Double) async {
        guard let context else { return }
        let llmContext = PromptComposer.Context(appName: context.appName, language: languageSetting,
                                                date: Date().formatted(date: .numeric, time: .omitted))
        if context.mode == .computerUse {
            if machine.send(.transcribed(text: raw, usesLLM: false)) == .inject { _ = machine.send(.injected) }
            record(raw: raw, processed: nil, context: context)
            onPhase?(.message(L.t("Computer Use is not available yet")))
            return
        }
        // A voice command executes; slots apply to the dictations that are written.
        let command = context.editSelection || context.mode == .command
        let slot = command ? nil : context.slot
        let usesLLM = command || context.mode == .enhanced || slot?.kind == .llm
        switch machine.send(.transcribed(text: raw, usesLLM: usesLLM)) {
        case .inject:
            write(raw: raw, processed: nil, slot: slot, context: context, releasedAt: releasedAt, seconds: seconds)
        case .runPostProcessing:
            onPhase?(.processing)
            if command {
                await runCommand(raw: raw, context: context, llmContext: llmContext, releasedAt: releasedAt)
                return
            }
            let instruction: String
            if let slot, slot.kind == .llm {
                instruction = slot.template
            } else {
                instruction = context.profile.interaction.enhancePrompt
            }
            let messages = PromptComposer.messages(
                base: config.llm.baseSystemPrompt, mode: PromptPreset(name: "", prompt: instruction), style: nil,
                context: llmContext, transcript: raw, selection: nil)
            var processed: String?
            do {
                processed = try await config.llm.client.complete(system: messages.system, user: messages.user,
                                                                 temperature: config.llm.temperature)
            } catch {
                if Task.isCancelled { return }
                log.error("llm failed: \(error.localizedDescription, privacy: .public)")
                onPhase?(.failure(L.t("LLM not available: raw text")))
            }
            guard !Task.isCancelled, machine.send(.postProcessed) == .inject else { return }
            write(raw: raw, processed: processed, slot: slot, context: context, releasedAt: releasedAt, seconds: seconds)
        default:
            onPhase?(.message(L.t("No speech")))
        }
    }

    /// The voice command (grey while talking) runs the agent.
    private func runCommand(raw: String, context: DictationContext, llmContext: PromptComposer.Context,
                            releasedAt: Double) async {
        await runAgent(raw: raw, context: context, language: llmContext.language, releasedAt: releasedAt)
    }

    /// The voice command agent (TDD voice command agent): the model calls tools until the command
    /// is done. Risky tools wait for a yes on the mic (RiskGate).
    private func runAgent(raw: String, context: DictationContext, language: String, releasedAt: Double) async {
        let profile = context.profile
        let screen = ScreenContext(
            app: context.appName, window: context.window, channel: context.channel, profile: profile.name,
            textFormat: profile.textFormat.rawValue, language: language, selection: context.selection,
            fieldText: context.fieldText, channels: context.channels,
            skills: profile.slots.filter { $0.kind == .run }.map(\.name),
            intents: profile.intents.filter { $0.value != .none }.keys.sorted(),
            appNotes: profile.interaction.commandHints)
        let handler = commandHandler
        let mac = LiveMac(handler: handler.map { h in { step in h(step) } },
                          strategy: profile.injection ?? config.injection.defaultStrategy,
                          restoreClipboardMs: config.injection.restoreClipboardMs)
        let tools = BuiltInTools.standard(mac, screen: screen)
            + BuiltInTools.interface(LiveUI(), allowOpenURL: config.agent.enabledTools.contains("open_url"))
            + BuiltInTools.user(config.agent.userTools, runner: LiveUserRunner())
        let registry = ToolRegistry(tools, disabled: Set(config.agent.disabledTools), riskOverrides: config.agent.riskOverrides)
        let maxSteps = config.agent.maxSteps
        let confirm = confirmAction
        let loop = AgentLoop(provider: config.llm.client, registry: registry, limits: AgentLimits(config.agent),
                             confirm: { pending in
                                 guard let confirm else { return false }
                                 return await confirm(pending)
                             },
                             progress: { [weak self] event in
                                 let text: String
                                 switch event {
                                 case .thinking(let step): text = step == 1 ? L.t("Voice command") : L.f("Voice command · %d/%d", step, maxSteps)
                                 case .running(_, let summary), .ran(_, let summary, _): text = summary
                                 case .confirming(let pending): text = pending.summary
                                 }
                                 Task { @MainActor in self?.onPhase?(.working(text)) }
                             })
        let run = await loop.run(screen, command: raw)
        guard !Task.isCancelled, run.outcome != .cancelled else { return }
        _ = machine.send(.postProcessed)
        _ = machine.send(.injected)
        let latency = now() - releasedAt
        log.notice("agent \(run.path, privacy: .public) → \(String(describing: run.outcome), privacy: .public) in \(latency, format: .fixed(precision: 0), privacy: .public) ms, \(run.modelCalls, privacy: .public) calls")
        if mac.changedSomething { lastInsertion = (context.bundleID, Date()) }
        switch run.outcome {
        case .done(let summary):
            record(raw: raw, processed: summary + " · " + run.path, context: context)
            onPhase?(.done(L.f("Command: %@", summary.isEmpty ? L.t("done") : summary)))
        case .cannot(let reason):
            record(raw: raw, processed: L.t("(no action)") + " · " + reason, context: context)
            onPhase?(.failure(reason.isEmpty ? L.t("Command not recognised") : reason))
        case .budget:
            record(raw: raw, processed: L.t("out of steps") + " · " + run.path, context: context)
            onPhase?(.failure(L.t("Voice command: out of steps")))
        case .failed(let error):
            log.error("agent failed: \(error, privacy: .public)")
            record(raw: raw, processed: nil, context: context)
            onPhase?(.failure(L.t("LLM not available: command not run")))
        case .cancelled:
            break
        }
    }

    private func write(raw: String, processed: String?, slot: Slot?, context: DictationContext,
                       releasedAt: Double, seconds: Double) {
        var text = processed ?? raw
        if let slot, slot.kind == .template { text = slot.fill(text) }
        if slot != nil { onSlotConsumed?() }
        // Trailing space so the next dictation does not stick to this one.
        let output = text.last?.isWhitespace == true ? text : text + " "
        let strategy = context.profile.injection ?? config.injection.defaultStrategy
        let outcome = TextInjector.insert(output, strategy: strategy, restoreAfterMs: config.injection.restoreClipboardMs)
        _ = machine.send(.injected)
        let latency = now() - releasedAt
        log.notice("dictation \(seconds, format: .fixed(precision: 1), privacy: .public)s audio, mode \(context.mode.label, privacy: .public), slot \(slot?.name ?? "-", privacy: .public) → \(String(describing: outcome), privacy: .public) in \(latency, format: .fixed(precision: 0), privacy: .public) ms")
        // Kept even when not written, so the text can be copied from the menu.
        record(raw: raw, processed: slot?.kind == .template ? text : processed, context: context)
        switch outcome {
        case .done:
            lastInsertion = (context.bundleID, Date())
            onPhase?(.done(L.f("Written (%.1f s)", latency / 1000)))
        case .secureInput: onPhase?(.failure(L.t("Protected field: text not written")))
        case .notTrusted: onPhase?(.failure(L.t("Accessibility permission needed")))
        case .failed: onPhase?(.failure(L.t("Writing failed")))
        }
    }

    private func record(raw: String, processed: String?, context: DictationContext) {
        let mode = context.slot.map { "\(L.t(context.mode.label)) + \($0.name)" } ?? L.t(context.mode.label)
        historyStore.append(HistoryEntry(app: context.appName, profile: context.profile.name,
                                         mode: mode, raw: raw, processed: processed))
    }

    // MARK: - Actions on the last dictation

    /// ⌘Z, only within 30 s and in the same app as the insertion (TDD §3.8).
    func undoLastInsertion(frontmostBundleID: String?) -> String {
        guard let last = lastInsertion, Date().timeIntervalSince(last.date) < 30,
              last.bundleID == frontmostBundleID else { return L.t("Nothing to undo") }
        lastInsertion = nil
        return TextInjector.send(["cmd+z"]) == .done ? L.t("Last insertion undone") : L.t("Undo failed")
    }

    func reinsertLast(raw: Bool, strategy: InjectionStrategy) -> String {
        guard let entry = history.first else { return L.t("No text to rewrite") }
        let text = raw ? entry.raw : entry.text
        let output = text.last?.isWhitespace == true ? text : text + " "
        let outcome = TextInjector.insert(output, strategy: strategy, restoreAfterMs: config.injection.restoreClipboardMs)
        return outcome == .done ? (raw ? L.t("Raw text rewritten") : L.t("Last text rewritten")) : L.t("Writing failed")
    }
}
