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
    }

    var onPhase: ((Phase) -> Void)?
    /// RMS level in dBFS while recording (called on the main queue).
    var onLevel: ((Float) -> Void)?
    /// Provides profile/mode/slot and the frontmost app at push-to-talk time.
    var contextProvider: (() -> DictationContext)?
    /// A template/llm slot was applied to a dictation: the app clears the selection.
    var onSlotConsumed: (() -> Void)?
    /// Runs the voice-command steps that need the app (channel, slot, intent); nil = not handled.
    var commandHandler: ((CommandStep) -> TextInjector.Outcome)?
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
    private let recorder = AudioRecorder()
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
        LLMClient(settings: config.llm).warmUp()
        Task { [weak self] in
            let selection = await TextInjector.readSelection()
            self?.context?.selection = selection
            if selection == nil { self?.log.notice("edit selection: nothing selected") }
        }
    }

    func pttUp() {
        guard isRecording else { return }
        let releasedAt = now()
        let effect = machine.send(.pttUp(at: releasedAt))
        let audio = recorder.stop()
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
            if wasRecording { _ = recorder.stop() }
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
                processed = try await LLMClient(settings: config.llm).complete(system: messages.system, user: messages.user)
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

    /// "Comando": the LLM turns the request into validated key/text steps (One-Pager 001 §1).
    private func runCommand(raw: String, context: DictationContext, llmContext: PromptComposer.Context,
                            releasedAt: Double) async {
        let intents = context.profile.intents.filter { $0.value != .none }.keys.sorted()
        let commandContext = PromptComposer.CommandContext(
            appName: context.appName, language: llmContext.language, channels: context.channels,
            slots: context.profile.slots.map(\.name), intents: intents, selection: context.selection,
            hints: context.profile.interaction.commandHints)
        let messages = PromptComposer.commandMessages(context: commandContext, transcript: raw)
        let response: String
        do {
            response = try await LLMClient(settings: config.llm).complete(system: messages.system, user: messages.user,
                                                                         temperature: 0)
        } catch {
            if Task.isCancelled { return }
            log.error("command llm failed: \(error.localizedDescription, privacy: .public)")
            _ = machine.send(.failed)
            record(raw: raw, processed: nil, context: context)
            onPhase?(.failure(L.t("LLM not available: command not run")))
            return
        }
        guard !Task.isCancelled, machine.send(.postProcessed) == .inject else { return }
        _ = machine.send(.injected)
        log.notice("command request \(raw, privacy: .public) → \(response.prefix(300), privacy: .public)")
        switch CommandParser.parse(response) {
        case .success(let steps) where steps.isEmpty:
            record(raw: raw, processed: L.t("(no action)"), context: context)
            onPhase?(.failure(L.t("Command not recognised")))
        case .success(let steps):
            var outcome = TextInjector.Outcome.done
            for step in steps where outcome == .done {
                switch step {
                // Typed, not pasted: several pastes in a row would race on the clipboard.
                case .text(let text): outcome = TextInjector.insert(text, strategy: .type, restoreAfterMs: 0)
                case .keys(let keys): outcome = TextInjector.send(keys)
                case .replaceSelection(let text):
                    // The selection is replaced by the paste; without one this would just type.
                    outcome = context.selection == nil ? .failed : TextInjector.insert(
                        text, strategy: context.profile.injection ?? config.injection.defaultStrategy,
                        restoreAfterMs: config.injection.restoreClipboardMs)
                case .switchChannel, .runSlot, .intent: outcome = commandHandler?(step) ?? .failed
                }
            }
            let summary = steps.map(\.summary).joined(separator: ", ")
            record(raw: raw, processed: summary, context: context)
            let latency = now() - releasedAt
            log.notice("command \(summary, privacy: .public) → \(String(describing: outcome), privacy: .public) in \(latency, format: .fixed(precision: 0), privacy: .public) ms")
            if outcome == .done { lastInsertion = (context.bundleID, Date()) }
            onPhase?(outcome == .done ? .done(L.f("Command: %@", summary)) : .failure(L.t("Command not run")))
        case .failure(.forbidden(let key)):
            record(raw: raw, processed: L.f("blocked: %@", key), context: context)
            onPhase?(.failure(L.f("Command blocked: %@", key)))
        case .failure:
            record(raw: raw, processed: L.t("invalid response"), context: context)
            onPhase?(.failure(L.t("Command not understood")))
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
