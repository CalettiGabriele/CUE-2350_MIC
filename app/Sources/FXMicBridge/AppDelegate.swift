import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import FXMicCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, DeviceServiceDelegate {
    private let log = Logger(subsystem: "com.fxmicbridge", category: "app")
    private var config: AppConfig
    private var configError: String?
    private var engine: ProfileEngine
    private let device = DeviceService()
    private var recognizer = GestureRecognizer()
    private let jack: JackTransport
    private let media = MediaController()
    private let dictation: DictationController
    private let historyStore: HistoryStore
    private let hud = HUD()
    private let settings: SettingsModel
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private static let onboardingKey = "onboardingCompleted"

    private var statusItem: NSStatusItem!
    private let phaseItem = NSMenuItem(title: L.t("Ready"), action: nil, keyEquivalent: "")
    private let deviceItem = NSMenuItem(title: L.t("Mic: searching…"), action: nil, keyEquivalent: "")
    private let modelItem = NSMenuItem(title: L.t("Model: not loaded"), action: nil, keyEquivalent: "")
    private let llmItem = NSMenuItem(title: L.t("LLM: checking…"), action: nil, keyEquivalent: "")
    private let profileItem = NSMenuItem(title: L.t("Profile"), action: nil, keyEquivalent: "")
    private let channelMenu = NSMenu()
    private let slotMenu = NSMenu()
    private let leds = LedAnimator()
    private let historyMenu = NSMenu()
    private let iconMenu = NSMenu()
    private var tickTimer: Timer?
    private var focusTimer: Timer?
    /// After orange takes you to a channel the window needs a moment to arrive: until then the
    /// channel you chose stands, and the window in front is not read.
    private var focusLockedUntil = Date.distantPast
    /// Channels removed by "clear all", kept so it can be undone.
    private var clearedChannels: [Channel] = []
    private var messageTimer: Timer?
    private var deviceStatus: DeviceStatus = .stopped
    private var currentPhase: DictationController.Phase = .idle
    private var hotkeyDown = false
    private var frontmost: NSRunningApplication?
    /// Confirmation of risky voice command actions on the mic.
    private let riskGate = RiskGate()
    private var lastWarmUp = Date.distantPast
    /// Windows the user dragged: they are no longer re-centred when their content resizes.
    private var windowsMovedByUser = Set<ObjectIdentifier>()

    override init() {
        let (config, error) = ConfigStore.load()
        self.config = config
        configError = error
        engine = ProfileEngine(config: config)
        historyStore = HistoryStore(fileURL: ConfigStore.directory.appendingPathComponent("history.jsonl"),
                                    retentionDays: config.history.retentionDays, enabled: config.history.enabled)
        historyStore.load()
        dictation = DictationController(config: config, historyStore: historyStore)
        jack = JackTransport(recorder: dictation.recorder)
        settings = SettingsModel(config: config)
        super.init()
    }

    /// A menu bar app has no main menu, so ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z do nothing in its text fields
    /// (the API key could not be pasted). An Edit menu restores them; it is never shown.
    private func installEditMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        main.addItem(item)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = edit
        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        L.language = config.ui.language
        installEditMenu()
        SessionLocator.custom = config.sessionAdapters
        SessionLocator.organizationLabels = config.organizationLabels
        Theme.registerFonts()
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--ax-dump"), flag + 1 < arguments.count {
            let bundleID = arguments[flag + 1]
            // Every `--ax-press <label>` in order, 0.3 s apart, then the tree 3 s later.
            var labels: [String] = []
            for (index, argument) in arguments.enumerated() where argument == "--ax-press" && index + 1 < arguments.count {
                labels.append(arguments[index + 1])
            }
            func step(_ rest: ArraySlice<String>) {
                guard let label = rest.first else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { AXDiagnostics.dumpTree(bundleID: bundleID) }
                    return
                }
                _ = AXDiagnostics.press(bundleID: bundleID, label: label)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { step(rest.dropFirst()) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { step(labels[...]) }
        }
        setupStatusItem()
        dictation.onPhase = { [weak self] phase in self?.show(phase) }
        dictation.onLevel = { [weak self] level in self?.hud.setLevel(level) }
        dictation.contextProvider = { [weak self] in self!.dictationContext() }
        dictation.commandHandler = { [weak self] step in self?.executeCommandStep(step) ?? .failed }
        dictation.confirmAction = { [weak self] pending in
            guard let self else { return false }
            return await self.riskGate.ask(pending, timeoutMs: self.config.agent.confirmTimeoutMs)
        }
        riskGate.onAsk = { [weak self] pending in
            guard let self else { return }
            self.leds.set(.confirm)
            // The island has one line: the action, then how to answer.
            self.hud.show(L.f("Confirm %@ · grey = yes · shake = no", pending.summary), glyph: .info)
            self.phaseItem.title = L.f("Confirm · %@", pending.summary)
        }
        riskGate.onEnd = { [weak self] yes in
            self?.leds.set(.processing)
            self?.hud.show(yes ? L.t("Confirmed") : L.t("Not done"))
        }
        dictation.onSlotConsumed = { [weak self] in
            guard let self else { return }
            self.engine.clearSlot()
            self.leds.refresh()
            self.rebuildProfileMenu()
        }
        leds.send = { [weak self] command in self?.device.send(command) }
        leds.onMask = { [weak self] mask in self?.mirrorLEDs(mask) }
        leds.idleMask = { [weak self] in self?.engine.idleLEDs ?? 0 }
        leds.slotNumber = { [weak self] in self?.engine.slotNumber }
        leds.map = config.device.ledMap
        leds.frameMs = config.device.ledAnimationMs
        wireSettings()

        let firstRun = !UserDefaults.standard.bool(forKey: Self.onboardingKey)
        if firstRun {
            showOnboarding()
        } else {
            requestMicrophone()
            // Prompts once; writing text and shortcuts need Accessibility.
            TextInjector.isTrusted(prompt: true)
        }
        loadModel()
        checkLLM()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(app) }
        }
        frontmostChanged(NSWorkspace.shared.frontmostApplication)

        device.delegate = self
        jack.onGesture = { [weak self] gesture in self?.handle([gesture]) }
        media.configure(config.audio.pauseMedia)
        media.warmUp()
        dictation.onHold = { [weak self] on in on ? self?.media.holdStarted() : self?.media.holdEnded() }
        jack.onSignalChange = { [weak self] in self?.jackStatusChanged() }
        applyTransport()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // A session can change inside an app without any app switch: look again now and then.
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.dictation.isRecording else { return }
                self.updateFocus()
            }
        }
        installHotkeyFallback()
        if let configError { show(.message(configError)) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restores the factory callback, LEDs and preset on the mic (ADR-001).
        device.restoreSync = (engine.channels.count, engine.channelPosition ?? -1, engine.slotNumber ?? 0)
        media.holdEnded()   // never leave the music paused
        device.stop()
        jack.stop()
    }

    // MARK: - Model and LLM

    private func requestMicrophone() {
        Task {
            if !(await AudioRecorder.requestPermission()) {
                self.show(.failure(L.t("Microphone permission denied")))
            }
            self.settings.refreshPermissions()
        }
    }

    private func loadModel() {
        modelItem.title = L.t("Whisper: downloading/loading…")
        settings.whisperStatus = L.t("Downloading and preparing the model…")
        settings.whisperReady = false
        let model = config.speech.model
        Task {
            await dictation.transcriber.load(model: model, folder: ConfigStore.modelsDirectory)
            switch await dictation.transcriber.state {
            case .ready(let name):
                let short = name.replacingOccurrences(of: "openai_whisper-", with: "")
                self.modelItem.title = "Whisper: \(short)"
                self.settings.whisperStatus = L.f("Ready: %@", short)
                self.settings.whisperReady = true
            case .failed(let error):
                self.modelItem.title = L.f("Whisper: error – %@", error)
                self.settings.whisperStatus = L.f("Error: %@", error)
                self.settings.whisperReady = false
            default: break
            }
        }
    }

    private func checkLLM() {
        let llm = config.llm
        llmItem.title = L.t("LLM: checking…")
        Task {
            let provider = llm.active
            let hasKey = KeychainStore.hasKey(provider.apiKeyRef)
            let models = await llm.client.availableModels()
            let warning = llm.isLocal ? "" : " ⚠︎ " + L.t("non-local endpoint")
            self.settings.llmModels = models ?? []
            if provider.preset.needsKey, !hasKey {
                self.llmItem.title = L.f("LLM: no API key for %@", provider.name)
                self.settings.llmStatus = L.t("No API key saved for this provider")
                self.settings.llmReady = false
            } else if let models {
                let installed = models.contains(llm.model) || models.contains(llm.model + ":latest")
                self.llmItem.title = installed
                    ? "LLM: \(llm.model)\(warning)"
                    : L.f("LLM: model %@ not installed", llm.model) + warning
                let missing = provider.preset == .ollama
                    ? L.f("The model %@ is not installed (ollama pull %@)", llm.model, llm.model)
                    : L.f("%@ does not list the model %@", provider.name, llm.model)
                self.settings.llmStatus = installed ? L.f("Ready: %@", llm.model) + warning : missing
                self.settings.llmReady = installed
                if installed, let context = await llm.client.ollamaContextLength(),
                   context < OpenAICompatibleClient.agentContextLength {
                    self.settings.llmStatus += " · " + L.f("context %d tokens: set at least %d in Ollama's settings for the voice command agent",
                                                           context, OpenAICompatibleClient.agentContextLength)
                }
            } else {
                self.llmItem.title = provider.preset == .ollama
                    ? L.t("LLM: server unreachable (ollama serve)") : L.f("LLM: %@ unreachable", provider.name)
                self.settings.llmStatus = provider.preset == .ollama
                    ? L.f("Server unreachable at %@ (start Ollama)", provider.baseURL)
                    : L.f("Cannot reach %@ at %@", provider.name, provider.baseURL)
                self.settings.llmReady = false
            }
        }
    }

    // MARK: - Profiles

    /// Switching app silently selects its profile: no HUD, no animation (LEDs and menu follow).
    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontmost = app
        if engine.activate(bundleID: app.bundleIdentifier) {
            selectionChanged(announce: false, title: engine.active.name)
        }
        updateFocus()
    }

    /// Where the voice goes now: the channel whose window is in front, or free. Nothing jumps:
    /// orange is what takes you to a channel (One-Pager 004 §4).
    private func updateFocus() {
        guard Date() >= focusLockedUntil else { return }
        let index = channelIndexInFront()
        guard index != engine.channelPosition else { return }
        engine.setFocus(index)
        leds.refresh()
        rebuildProfileMenu()
    }

    private func channelIndexInFront() -> Int? {
        guard !engine.channels.isEmpty, let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier else { return nil }
        // Our own window (Settings, a dialog) in front changes nothing.
        if id == Bundle.main.bundleIdentifier { return engine.channelPosition }
        guard engine.channels.contains(where: { $0.bundleID == id }),
              let window = ChannelNavigator.capture(app) else { return nil }
        return engine.channelIndex(forWindow: window)
    }

    /// "Recording · Enhanced · Summarize": phase, mode and the selected slot, if any.
    private func statusLine(_ phase: String) -> String {
        ([phase, channelName] + (engine.slot.map { [$0.name] } ?? [])).joined(separator: " · ")
    }

    private var modeName: String { L.t(engine.mode.label) }
    /// "Claude · progetto" on a channel; "Free · Mail" anywhere else (the voice goes where the cursor is).
    private var channelName: String { engine.channel?.name ?? L.f("Free · %@", frontmost?.localizedName ?? "?") }
    private var slotName: String { engine.slot?.name ?? L.t("No slot") }

    private var selectionDetail: String {
        "\(engine.active.name) · \(channelName) · \(slotName)"
    }

    /// "CHANNEL 2/3", or "FREE" when you are not on a channel.
    private var channelKicker: String {
        engine.channelPosition.map { L.f("Channel %d/%d", $0 + 1, engine.channels.count) } ?? L.t("Free")
    }

    /// LEDs, menu and HUD after a profile/mode/slot change.
    private func selectionChanged(announce: Bool, kicker: String = "", title: String) {
        leds.refresh()
        rebuildProfileMenu()
        if announce, !dictation.isRecording {
            hud.card(kicker: kicker, title: title)
        }
        // One warm-up per minute at most: Ollama keeps the model loaded for ~5 minutes.
        let needsLLM = engine.mode.usesLLM || engine.slot?.kind == .llm
        if needsLLM, Date().timeIntervalSince(lastWarmUp) > 60 {
            lastWarmUp = Date()
            config.llm.client.warmUp()
        }
    }

    private func dictationContext() -> DictationContext {
        let slot = engine.slot.flatMap { $0.kind == .run ? nil : $0 }
        return DictationContext(profile: engine.active, mode: engine.mode, slot: slot,
                                appName: frontmost?.localizedName ?? "?", bundleID: frontmost?.bundleIdentifier,
                                channels: engine.channels.map(\.name), channel: engine.channel?.name,
                                pid: frontmost?.processIdentifier)
    }

    // MARK: - Device

    nonisolated func device(_ service: DeviceService, didChange status: DeviceStatus) {
        MainActor.assumeIsolated {
            deviceStatus = status
            defer {
                if jack.isListening {
                    jackStatusChanged()   // the jack's state is the one to show
                } else {
                    settings.deviceStatus = deviceItem.title
                    if case .connected = status { settings.deviceConnected = true }
                    else if case .readOnly = status { settings.deviceConnected = true }
                    else { settings.deviceConnected = false }
                }
            }
            switch status {
            case .searching: deviceItem.title = L.t("Mic: not connected (right Option = talk)")
            case .connecting: deviceItem.title = L.t("Mic: connecting…")
            case .connected(let fw):
                deviceItem.title = L.f("Mic: connected (firmware %@)", fw)
                leds.refresh(force: true)
                if leds.state == .idle { leds.set(.boot) }
            case .readOnly(let fw): deviceItem.title = L.f("Mic: firmware %@ not verified (read-only)", fw)
            case .busy: deviceItem.title = L.t("Mic: port in use by another program")
            case .stopped: deviceItem.title = L.t("Mic: released")
            }
            updateJackUse()
            updateIcon()
        }
    }

    nonisolated func device(_ service: DeviceService, didReceive line: DeviceLine, at timeMs: Double) {
        MainActor.assumeIsolated {
            switch line {
            case .control(let control, let active):
                if active { settings.pressedControls.insert(control) } else { settings.pressedControls.remove(control) }
                handle(recognizer.handle(control, active: active, at: timeMs))
            case .poll(_, let shaker, _):
                handle(recognizer.poll(shaker: shaker, at: timeMs))
            case .deviceError(let text):
                log.error("device: \(text, privacy: .public)")
            default:
                break
            }
        }
    }

    // MARK: - Transport (One-Pager 002 §3.3)

    /// USB-C serial line: used unless the jack is forced. Jack: forced, or in automatic
    /// mode whenever the USB-C line is not connected.
    private func applyTransport() {
        if config.device.transport == .jack {
            DispatchQueue.global().async { [device] in device.stop() }
        } else {
            device.start()
        }
        _ = updateJackUse()
        jackStatusChanged()
    }

    /// Starts or stops listening to the jack. Returns true when that changed.
    @discardableResult
    private func updateJackUse() -> Bool {
        let usbUp: Bool
        switch deviceStatus {
        case .connected, .readOnly, .connecting: usbUp = true
        default: usbUp = false
        }
        let want: Bool
        switch config.device.transport {
        case .usb: want = false
        case .jack: want = true
        case .auto: want = !usbUp
        }
        guard want != jack.isListening else { return false }
        if want { jack.start() } else { jack.stop() }
        return true
    }

    private func jackStatusChanged() {
        guard jack.isListening else { return }
        let connected = jack.hasSignal
        deviceItem.title = jack.failed ? L.t("Mic: audio input not available")
            : connected ? L.t("Mic: connected through the jack")
            : L.t("Mic: jack, no signal (switch the mic on, check the input)")
        settings.deviceStatus = deviceItem.title
        settings.deviceConnected = connected
        updateIcon()
    }

    private func tick() {
        handle(recognizer.tick(at: ProcessInfo.processInfo.systemUptime * 1000))
    }

    private func handle(_ gestures: [FXMicCore.Gesture]) {
        for gesture in gestures {
            log.debug("gesture \(String(describing: gesture), privacy: .public)")
            // While the agent waits for a yes, grey answers yes, a shake answers no; nothing else runs.
            if riskGate.isWaiting {
                switch gesture {
                case .tap(.grey): riskGate.resolve(true)
                case .shake, .longPress(.grey): riskGate.resolve(false)
                default: break
                }
                continue
            }
            switch gesture {
            case .pttDown: pttDown()
            case .pttUp: dictation.pttUp()
            default:
                if let action = engine.action(for: gesture) { perform(action) }
            }
        }
    }

    // MARK: - Actions (TDD §3.3)

    private func perform(_ action: Action) {
        let strategy = engine.active.injection ?? config.injection.defaultStrategy
        switch action {
        case .none:
            break
        case .nextChannel:
            engine.nextChannel()
            channelChanged()
        case .previousChannel:
            engine.previousChannel()
            channelChanged()
        case .bindChannel:
            bind(NSWorkspace.shared.frontmostApplication)
        case .clearChannels:
            clearAllChannels()
        case .cycleMode:
            engine.cycleMode()
            selectionChanged(announce: true, kicker: L.t("Mode"), title: modeName)
        case .resetMode:
            engine.resetMode()
            selectionChanged(announce: true, kicker: L.t("Mode"), title: modeName)
        case .nextSlot:
            engine.nextSlot()
            announceSlot()
        case .previousSlot:
            engine.previousSlot()
            announceSlot()
        case .clearSlot:
            engine.clearSlot()
            announceSlot()
        case .runSlot:
            runSelectedSlot()
        case .intent(let name):
            runIntent(name)
        case .key(let combos):
            report(TextInjector.send(combos), done: KeyLabel.describe(combos))
        case .text(let text):
            // A trailing "\n" means "then press Return" (e.g. "/clear\n").
            let sendReturn = text.hasSuffix("\n")
            let body = sendReturn ? String(text.dropLast()) : text
            var outcome = body.isEmpty ? .done : TextInjector.insert(body, strategy: strategy, restoreAfterMs: config.injection.restoreClipboardMs)
            if outcome == .done, sendReturn {
                // Let the paste land before Return.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = TextInjector.send(["return"]) }
            }
            if body.isEmpty, sendReturn { outcome = TextInjector.send(["return"]) }
            report(outcome, done: L.f("Sent: %@", body))
        case .undoLastInsertion:
            hud.toast(dictation.undoLastInsertion(frontmostBundleID: frontmost?.bundleIdentifier))
        case .reinsertLast(let raw):
            hud.toast(dictation.reinsertLast(raw: raw, strategy: strategy))
        case .cancel:
            dictation.cancel()
        case .editSelection:
            if dictation.isRecording {
                dictation.markEditSelection()
            } else {
                hud.toast(L.t("Hold the handle and press grey while you talk"))
            }
        }
    }

    // MARK: - Channels (One-Pager 004 §4)

    /// Orange took you to a channel: bring its window forward, take its profile, show it.
    private func channelChanged() {
        guard let channel = engine.channel else {
            hud.card(kicker: L.t("Channels"), title: L.t("No channels yet: long-press orange on a window to add it"))
            return
        }
        focusLockedUntil = Date().addingTimeInterval(2)
        activateProfile(of: channel)
        ChannelNavigator.bringToFront(channel, learn: { [weak self] organization, label in
            self?.learnOrganization(organization, label: label)
        }, status: { [weak self] text in self?.hud.toast(text, duration: 2.5) })
        selectionChanged(announce: true, kicker: channelKicker, title: channel.name)
    }

    /// A switch ended in `organization` after pressing `label`: remember it for next time.
    private func learnOrganization(_ organization: String, label: String) {
        guard config.organizationLabels[organization] != label else { return }
        var updated = config
        updated.organizationLabels[organization] = label
        applyConfig(updated, save: true)
    }

    /// The profile follows the channel's app, also before macOS reports the app switch.
    private func activateProfile(of channel: Channel) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: channel.bundleID).first {
            frontmost = app
        }
        if engine.activate(bundleID: channel.bundleID) { rebuildProfileMenu() }
    }

    /// Long press on orange: the window you are working in becomes a channel. It takes the next
    /// free one; with all four taken it replaces the channel you are on.
    private func bind(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let channel = ChannelNavigator.capture(app) else {
            hud.toast(L.t("Bring the window to bind to the front first"))
            return
        }
        let outcome = engine.bind(channel)
        log.notice("bind \(channel.bundleID, privacy: .public) session=\(channel.session ?? "-", privacy: .public) link=\(channel.link ?? "-", privacy: .public) title=\(channel.title ?? "-", privacy: .public) → channel \(outcome.index + 1, privacy: .public)")
        if channel.session == nil, channel.link == nil, SessionLocator.adapter(for: channel.bundleID)?.webPattern != nil {
            log.notice("bind: no chat link; the web view says \(ChannelNavigator.debugWebURL(of: app), privacy: .public)")
        }
        applyConfig(engine.config, save: true)
        let title: String
        switch outcome.kind {
        case .added: title = L.f("Added as channel %d: %@", outcome.index + 1, channel.name)
        case .updated: title = L.f("Channel %d updated: %@", outcome.index + 1, channel.name)
        case .replaced: title = L.f("Channel %d replaced: %@", outcome.index + 1, channel.name)
        }
        hud.card(kicker: channelKicker, title: title)
    }

    /// Orange held for 3 s, or the menu: unbinds every channel. Windows and sessions are untouched.
    private func clearAllChannels() {
        let removed = engine.clearChannels()
        guard !removed.isEmpty else {
            hud.toast(L.t("No channels to clear"))
            return
        }
        clearedChannels = removed
        applyConfig(engine.config, save: true)
        hud.card(kicker: L.t("Channels"), title: L.t("All channels cleared"))
    }

    /// The voice goes where you are: on a channel's window it is that channel, anywhere else it is
    /// free and nothing jumps.
    private func pttDown() {
        updateFocus()
        dictation.pttDown()
    }

    private func announceSlot() {
        guard let slot = engine.slot, let number = engine.slotNumber else {
            selectionChanged(announce: true, kicker: L.t("Slot"), title: L.t("No slot"))
            return
        }
        let kind: String
        switch slot.kind {
        case .run: kind = L.t("grey to run")
        case .template: kind = L.t("applies to the next dictation")
        case .llm: kind = L.t("LLM on the next dictation")
        }
        leds.refresh()
        rebuildProfileMenu()
        hud.card(kicker: L.f("Slot %d", number) + " · " + kind, title: slot.name)
        if slot.kind == .llm, Date().timeIntervalSince(lastWarmUp) > 60 {
            lastWarmUp = Date()
            config.llm.client.warmUp()
        }
    }

    /// Grey: runs a "run" slot once and clears the selection; with no slot it presses Return.
    /// Does what the active profile says for an intent ("interrupt", "newSession"…).
    @discardableResult
    private func runIntent(_ name: String) -> Bool {
        guard let action = engine.active.intents[name], action != .none else {
            hud.toast(L.f("%@ is not available here", name))
            return false
        }
        // An intent that points to another intent would loop.
        if case .intent = action { return false }
        perform(action)
        return true
    }

    /// The voice-command steps that act on the app itself (One-Pager 004 §6.2).
    private func executeCommandStep(_ step: CommandStep) -> TextInjector.Outcome {
        switch step {
        case .switchChannel(let name):
            guard let index = NameMatcher.index(of: name, in: engine.channels.map(\.name)) else {
                hud.toast(L.f("No channel called %@", name))
                return .failed
            }
            engine.select(channel: index)
            channelChanged()
            return .done
        case .runSlot(let name):
            guard let index = NameMatcher.index(of: name, in: engine.active.slots.map(\.name)) else {
                hud.toast(L.f("No slot called %@", name))
                return .failed
            }
            engine.select(slot: index)
            runSelectedSlot()
            return .done
        case .intent(let name):
            return runIntent(name) ? .done : .failed
        }
    }

    private func runSelectedSlot() {
        guard let slot = engine.slot else {
            perform(.key(["return"]))
            return
        }
        switch slot.kind {
        case .run:
            engine.clearSlot()
            leds.refresh()
            rebuildProfileMenu()
            perform(slot.action)
        case .template, .llm:
            hud.toast(L.f("%@: hold the handle and dictate", slot.name))
        }
    }

    private func report(_ outcome: TextInjector.Outcome, done: String) {
        switch outcome {
        case .done: hud.toast(done, glyph: .done)
        case .secureInput: hud.toast(L.t("Protected field: no keys sent"))
        case .notTrusted:
            log.error("action not sent: Accessibility not granted")
            hud.toast(L.t("Accessibility permission needed"), duration: 2.5)
        case .failed: hud.toast(L.t("Action failed: check config.json"))
        }
    }

    // MARK: - Fallback push-to-talk (right Option held)

    private func installHotkeyFallback() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == 61 else { return }   // right Option
            let down = event.modifierFlags.contains(.option)
            guard down != self.hotkeyDown else { return }
            self.hotkeyDown = down
            down ? self.pttDown() : self.dictation.pttUp()
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated { handler(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }
    }

    // MARK: - Status item and menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
    }

    /// (Re)builds the menu in the current language (`ui.language`).
    private func buildMenu() {
        phaseItem.title = L.t("Ready")
        modelItem.title = settings.whisperReady ? modelItem.title : L.t("Whisper: downloading/loading…")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(phaseItem)
        menu.addItem(deviceItem)
        menu.addItem(modelItem)
        menu.addItem(llmItem)
        menu.addItem(.separator())
        menu.addItem(profileItem)
        let channelItem = NSMenuItem(title: L.t("Channel (orange)"), action: nil, keyEquivalent: "")
        channelItem.submenu = channelMenu
        menu.addItem(channelItem)
        let slotItem = NSMenuItem(title: L.t("Slot (white)"), action: nil, keyEquivalent: "")
        slotItem.submenu = slotMenu
        menu.addItem(slotItem)
        menu.addItem(.separator())
        let historyItem = NSMenuItem(title: L.t("Recent texts"), action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
        menu.addItem(.separator())
        let iconItem = NSMenuItem(title: L.t("Menu bar icon"), action: nil, keyEquivalent: "")
        iconItem.submenu = iconMenu
        menu.addItem(iconItem)
        menu.addItem(withTitle: L.t("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: L.t("Setup guide…"), action: #selector(openOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: L.t("Open config.json"), action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: L.t("Reload configuration"), action: #selector(reloadConfig), keyEquivalent: "r")
        menu.addItem(withTitle: L.t("Accessibility permission…"), action: #selector(openAccessibility), keyEquivalent: "")
        // Developer tool (One-Pager 004 §10.1), shown while ⌥ is held.
        let diagnostics = menu.addItem(withTitle: "Accessibility diagnostics (5 s)", action: #selector(runAXDiagnostics), keyEquivalent: "")
        diagnostics.keyEquivalentModifierMask = .option
        diagnostics.isAlternate = true
        menu.addItem(withTitle: L.t("Release device"), action: #selector(releaseDevice), keyEquivalent: "")
        menu.addItem(withTitle: L.t("Reconnect device"), action: #selector(reconnectDevice), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L.t("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
        updateIcon()
        rebuildProfileMenu()
        rebuildIconMenu()
        rebuildHistory()
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { refreshHistoryViews() }
    }

    private func rebuildProfileMenu() {
        profileItem.title = L.f("Profile: %@", engine.active.name)
        settings.activeProfileID = engine.active.id
        channelMenu.removeAllItems()
        if engine.channels.isEmpty {
            let none = NSMenuItem(title: L.t("No channels yet"), action: nil, keyEquivalent: "")
            channelMenu.addItem(none)
        }
        for (position, channel) in engine.channels.enumerated() {
            let item = NSMenuItem(title: "\(position + 1). \(channel.name)", action: #selector(selectChannel(_:)), keyEquivalent: "")
            item.tag = position
            item.state = position == engine.channelPosition ? .on : .off
            item.target = self
            channelMenu.addItem(item)
        }
        channelMenu.addItem(.separator())
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            channelMenu.addItem(item)
        }
        add(L.t("Add the window in front as a channel"), #selector(bindFromMenu))
        add(L.t("Unbind the current channel"), #selector(unbindChannel), enabled: engine.channel != nil)
        channelMenu.addItem(.separator())
        add(L.t("Clear all channels…"), #selector(clearFromMenu), enabled: !engine.channels.isEmpty)
        add(L.t("Restore the cleared channels"), #selector(restoreChannels),
            enabled: !clearedChannels.isEmpty && engine.channels.isEmpty)
        slotMenu.removeAllItems()
        let none = NSMenuItem(title: L.t("No slot"), action: #selector(selectSlot(_:)), keyEquivalent: "")
        none.tag = -1
        slotMenu.addItem(none)
        for (index, slot) in engine.active.slots.enumerated() {
            let kind = slot.kind == .run ? L.t("run") : (slot.kind == .template ? L.t("template") : "LLM")
            let item = NSMenuItem(title: "\(index + 1). \(slot.name) — \(kind)", action: #selector(selectSlot(_:)), keyEquivalent: "")
            item.tag = index
            slotMenu.addItem(item)
        }
        for item in slotMenu.items {
            item.target = self
            item.state = item.tag == (engine.slotIndex ?? -1) ? .on : .off
        }
    }

    @objc private func selectChannel(_ sender: NSMenuItem) {
        engine.select(channel: sender.tag)
        channelChanged()
    }

    /// From the menu the frontmost app is the menu bar's own, so the last real app is used.
    @objc private func bindFromMenu() { bind(frontmost) }

    @objc private func unbindChannel() {
        guard engine.unbindChannel() else { return }
        applyConfig(engine.config, save: true)
        hud.card(kicker: L.t("Channels"), title: L.t("Channel unbound"))
    }

    /// Asks first: from the menu this is one click away, unlike the 3 s hold on the mic.
    @objc private func clearFromMenu() {
        let alert = NSAlert()
        alert.messageText = L.t("Clear all channels?")
        alert.informativeText = L.t("The channels are unbound. The windows and sessions are not touched, and you can undo from this menu.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Clear all")).hasDestructiveAction = true
        alert.addButton(withTitle: L.t("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { clearAllChannels() }
    }

    @objc private func restoreChannels() {
        engine.restoreChannels(clearedChannels)
        clearedChannels = []
        applyConfig(engine.config, save: true)
        hud.card(kicker: L.t("Channels"), title: L.t("Channels restored"))
    }

    @objc private func selectSlot(_ sender: NSMenuItem) {
        engine.select(slot: sender.tag >= 0 ? sender.tag : nil)
        announceSlot()
    }

    private func show(_ phase: DictationController.Phase) {
        currentPhase = phase
        messageTimer?.invalidate()
        let detail = selectionDetail
        switch phase {
        case .idle:
            phaseItem.title = L.t("Ready")
            hud.hide()
            leds.set(.idle)
        case .recording:
            leds.set(.recording)
            phaseItem.title = "● " + L.t("Recording…")
            hud.show(statusLine(L.t("Recording")), detail: detail, showsMeter: true, glyph: .recording)
        case .transcribing:
            leds.set(.processing)
            phaseItem.title = L.t("Transcribing…")
            hud.show(statusLine(L.t("Transcribing")), detail: detail)
        case .processing:
            leds.set(.processing)
            phaseItem.title = L.f("Processing with %@…", config.llm.model)
            hud.show(statusLine(L.t("Processing")), detail: detail)
        case .working(let step):
            leds.set(.processing)
            phaseItem.title = step
            hud.show(statusLine(step), detail: detail)
        case .message(let text), .done(let text), .failure(let text):
            if case .failure = phase { leds.set(.error) } else { leds.set(.idle) }
            phaseItem.title = text
            let glyph: HUD.Glyph
            switch phase {
            case .done: glyph = .done
            case .failure: glyph = .info      // the LED mirror shows the error blink
            default: glyph = .none
            }
            hud.toast(text, duration: 0.9, glyph: glyph)
            messageTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch self.currentPhase {
                    case .message, .done, .failure: break
                    default: return
                    }
                    self.currentPhase = .idle
                    self.phaseItem.title = L.t("Ready")
                    self.updateIcon()
                }
            }
        }
        updateIcon()
    }

    // MARK: - Menu bar icon (ui.menuBarIcon)

    /// Fits an image to the menu bar (16 pt high, max 22 pt wide) as a template, so it follows
    /// light/dark menu bars. Colours are dropped: only the shape (alpha) is drawn.
    private static func menuBarImage(_ image: NSImage) -> NSImage {
        let height: CGFloat = 16
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: min(height * aspect, 22), height: min(height, 22 / max(aspect, 0.01)))
        image.isTemplate = true
        return image
    }

    private var cachedIdleIcon: (key: String, image: NSImage)?

    /// The icon chosen by the user, shown while the mic is connected and nothing is happening.
    private var idleIcon: NSImage {
        let key = config.ui.menuBarIcon + "|" + (config.ui.menuBarIconFile ?? "")
        if let cached = cachedIdleIcon, cached.key == key { return cached.image }
        var image: NSImage?
        switch config.ui.menuBarIcon {
        case "auto":
            image = Self.grilleIcon
        case "file":
            image = config.ui.menuBarIconFile.flatMap { NSImage(contentsOfFile: $0) }.map(Self.menuBarImage)
        default:
            image = MenuBarIconPreset(rawValue: config.ui.menuBarIcon)
                .flatMap { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: "CUE-2350 MIC") }
        }
        let result = image ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "CUE-2350 MIC")!
        result.isTemplate = true
        cachedIdleIcon = (key, result)
        return result
    }

    /// Default icon: the mic's dot grille (3×3) next to its LED column, drawn as a template.
    private static let grilleIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 13), xRadius: 2.5, yRadius: 2.5)
            body.lineWidth = 1.4
            body.stroke()
            for row in 0..<3 {
                for column in 0..<3 {
                    NSBezierPath(ovalIn: NSRect(x: 3.6 + CGFloat(column) * 3.4, y: 3.6 + CGFloat(row) * 3.4, width: 2.2, height: 2.2)).fill()
                }
            }
            NSBezierPath(roundedRect: NSRect(x: 13.2, y: 3.6, width: 1.6, height: 8.8), xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// The icon chosen by the user, tinted with the accent while recording or processing.
    /// Details are in the tooltip and in the menu.
    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.toolTip = "CUE-2350 MIC — \(phaseItem.title) · \(deviceItem.title)"
        let tint: NSColor?
        switch currentPhase {
        case .recording: tint = Theme.accentNS
        case .transcribing, .processing: tint = Theme.accentNS.withAlphaComponent(0.6)
        default: tint = nil
        }
        if button.image !== idleIcon { button.image = idleIcon }
        if button.contentTintColor != tint { button.contentTintColor = tint }
    }

    /// LED masks to the screen: HUD wing and the mic drawn in Settings/onboarding. With Reduce
    /// Motion the recording sweep is shown as all red LEDs on.
    private func mirrorLEDs(_ mask: UInt8) {
        var shown = mask
        if Theme.reduceMotion, leds.state == .recording || leds.state == .processing {
            shown = 0x0F | (mask & 0xF0)
        }
        hud.setLEDs(shown)
        settings.ledMask = shown
    }

    private func rebuildIconMenu() {
        iconMenu.removeAllItems()
        let current = config.ui.menuBarIcon
        func add(_ title: String, id: String, image: NSImage?, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: enabled ? #selector(selectIcon(_:)) : nil, keyEquivalent: "")
            item.representedObject = id
            item.image = image.map { img in
                let copy = img.copy() as! NSImage
                copy.isTemplate = true
                return copy
            }
            item.state = id == current ? .on : .off
            item.target = self
            iconMenu.addItem(item)
        }
        add(L.t("Grille (default)"), id: "auto", image: Self.grilleIcon)
        for preset in MenuBarIconPreset.allCases {
            add(L.t(preset.label), id: preset.rawValue,
                image: NSImage(systemSymbolName: preset.symbolName, accessibilityDescription: nil))
        }
        iconMenu.addItem(.separator())
        if let file = config.ui.menuBarIconFile {
            add(L.f("File: %@", (file as NSString).lastPathComponent), id: "file",
                image: NSImage(contentsOfFile: file).map(Self.menuBarImage))
        }
        let choose = NSMenuItem(title: L.t("Choose file… (SVG, PDF or PNG)"), action: #selector(chooseIconFile), keyEquivalent: "")
        choose.target = self
        iconMenu.addItem(choose)
    }

    @objc private func selectIcon(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setIcon(id, file: config.ui.menuBarIconFile)
    }

    @objc private func chooseIconFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg, .pdf, .png]
        panel.message = L.t("Choose the menu bar icon. It is drawn monochrome, like system icons.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard NSImage(contentsOf: url) != nil else {
            hud.toast(L.f("Unreadable file: %@", url.lastPathComponent), duration: 2)
            return
        }
        do {
            let copy = try ConfigStore.importIcon(from: url)
            cachedIdleIcon = nil
            setIcon("file", file: copy.path)
        } catch {
            hud.toast(L.f("Cannot copy the icon: %@", error.localizedDescription), duration: 2)
        }
    }

    private func setIcon(_ id: String, file: String?) {
        var updated = config
        updated.ui.menuBarIcon = id
        updated.ui.menuBarIconFile = file
        applyConfig(updated, save: true)
    }

    private func rebuildHistory() {
        historyMenu.removeAllItems()
        if dictation.history.isEmpty {
            historyMenu.addItem(NSMenuItem(title: L.t("No text"), action: nil, keyEquivalent: ""))
        }
        for entry in dictation.history {
            let text = entry.text.replacingOccurrences(of: "\n", with: " ")
            let title = text.count > 60 ? String(text.prefix(60)) + "…" : text
            let item = NSMenuItem(title: title, action: #selector(copyHistory(_:)), keyEquivalent: "")
            item.representedObject = entry.text
            item.target = self
            item.toolTip = entry.processed == nil ? L.t("Click to copy") : L.f("Raw: %@\n\nClick to copy the processed text", entry.raw)
            historyMenu.addItem(item)
        }
    }

    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    @objc private func reloadConfig() {
        let (config, error) = ConfigStore.load()
        applyConfig(config, save: false)
        hud.toast((error ?? L.t("Configuration reloaded")) + " · " + L.f("%d profiles", config.profiles.count), duration: 2)
    }

    /// Applies a new configuration to every component (Settings "Salva", reload, icon menu).
    private func applyConfig(_ newConfig: AppConfig, save: Bool) {
        let old = config
        config = newConfig
        SessionLocator.custom = newConfig.sessionAdapters
        SessionLocator.organizationLabels = newConfig.organizationLabels
        if old.ui.language != newConfig.ui.language {
            L.language = newConfig.ui.language
            relocalize()
        }
        if save { ConfigStore.save(newConfig) }
        engine.reload(newConfig)
        dictation.config = newConfig
        media.configure(newConfig.audio.pauseMedia)
        media.warmUp()
        if old.device.transport != newConfig.device.transport { applyTransport() }
        else if old.audio.inputDeviceUID != newConfig.audio.inputDeviceUID, jack.isListening { jack.restart() }
        leds.map = newConfig.device.ledMap
        leds.frameMs = newConfig.device.ledAnimationMs
        historyStore.enabled = newConfig.history.enabled
        historyStore.retentionDays = newConfig.history.retentionDays
        if old.history != newConfig.history {
            if newConfig.history.enabled { historyStore.load() } else { historyStore.clear() }
        }
        if old.speech.model != newConfig.speech.model { loadModel() }
        if old.llm != newConfig.llm { checkLLM() }
        cachedIdleIcon = nil
        rebuildIconMenu()
        updateIcon()
        selectionChanged(announce: false, title: "")
        settings.externalUpdate(newConfig)
        refreshHistoryViews()
    }

    /// Rebuilds every visible text after a language change.
    private func relocalize() {
        buildMenu()
        device(self.device, didChange: deviceStatus)   // re-titles the device line
        checkLLM()
        if let window = settingsWindow {
            window.title = L.t("CUE-2350 MIC Settings")
            window.contentViewController = NSHostingController(rootView: SettingsView(model: settings))
        }
        if let window = onboardingWindow {
            window.title = L.t("Set up CUE-2350 MIC")
            window.contentViewController = NSHostingController(rootView: onboardingView())
        }
    }

    private func refreshHistoryViews() {
        settings.history = historyStore.entries
        rebuildHistory()
    }

    // MARK: - Settings and onboarding windows

    private func wireSettings() {
        settings.onApply = { [weak self] config in self?.applyConfig(config, save: true) }
        settings.onReconnectDevice = { [weak self] in self?.reconnectDevice() }
        settings.onReleaseDevice = { [weak self] in self?.releaseDevice() }
        settings.onRefreshLLM = { [weak self] in self?.checkLLM() }
        settings.onRequestMicrophone = { [weak self] in self?.requestMicrophone() }
        settings.onDeleteHistory = { [weak self] id in
            self?.historyStore.delete(id: id)
            self?.refreshHistoryViews()
        }
        settings.onClearHistory = { [weak self] in
            self?.historyStore.clear()
            self?.refreshHistoryViews()
        }
        settings.onTestLEDs = { [weak self] in self?.testLEDs() }
        settings.history = historyStore.entries
        settings.refreshPermissions()
    }

    /// One LED at a time (logical order: red 1–4, white 1–4), then back to idle.
    /// Lets the user check `device.ledMap` by eye.
    private func testLEDs() {
        for i in 0..<8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) { [weak self] in
                guard let self else { return }
                self.device.send(DeviceProtocol.ledMaskCommand(LedPattern.physical(1 << UInt8(i), map: self.config.device.ledMap)))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) { [weak self] in self?.leds.refresh(force: true) }
    }

    private func makeWindow(title: String, content: NSViewController, resizable: Bool) -> NSWindow {
        let window = NSWindow(contentViewController: content)
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Opens in the Space (desktop) you are in, not in the one it was first created in.
        window.collectionBehavior.insert(.moveToActiveSpace)
        keepCentred(window)
        return window
    }

    /// The content of a window sets its height (a tab can be taller than the one before) and a
    /// resize keeps the bottom-left corner, so the window drifts off-centre. Re-centre after each
    /// content resize, unless the user has dragged the window somewhere else.
    private func keepCentred(_ window: NSWindow) {
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                // A drag has the mouse button down; our own repositioning does not.
                guard let self, let window, NSEvent.pressedMouseButtons & 1 != 0 else { return }
                self.windowsMovedByUser.insert(ObjectIdentifier(window))
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, window.isVisible, !window.inLiveResize,
                      !self.windowsMovedByUser.contains(ObjectIdentifier(window)) else { return }
                self.centre(window, on: window.screen ?? self.activeScreen())
            }
        }
    }

    private func centre(_ window: NSWindow, on screen: NSScreen?) {
        guard let area = screen?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: (area.midX - window.frame.width / 2).rounded(),
                                      y: (area.midY - window.frame.height / 2).rounded()))
    }

    /// The screen the user is working on: the one under the mouse pointer (same rule as the HUD).
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Shows `window` centred on the active screen and in the current Space. A window that is
    /// already open there is left where the user put it.
    private func present(_ window: NSWindow?) {
        guard let window else { return }
        let screen = activeScreen()
        let alreadyHere = window.isVisible && window.isOnActiveSpace && window.screen == screen
        if !alreadyHere {
            windowsMovedByUser.remove(ObjectIdentifier(window))
            centre(window, on: screen)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        settings.refreshPermissions()
        settings.refreshDevices()
        settings.history = historyStore.entries
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: L.t("CUE-2350 MIC Settings"),
                                        content: NSHostingController(rootView: SettingsView(model: settings)),
                                        resizable: true)
        }
        present(settingsWindow)
    }

    @objc private func openOnboarding() { showOnboarding() }

    private func onboardingView() -> OnboardingView {
        OnboardingView(model: settings) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
            self?.onboardingWindow?.close()
        }
    }

    private func showOnboarding() {
        settings.refreshPermissions()
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: L.t("Set up CUE-2350 MIC"),
                                          content: NSHostingController(rootView: onboardingView()), resizable: false)
        }
        present(onboardingWindow)
    }

    @objc private func openAccessibility() {
        TextInjector.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Leaves 5 s to bring the app under test to the front, then probes it.
    @objc private func runAXDiagnostics() {
        hud.toast("Diagnostics in 5 s: focus the app to test", duration: 2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.hud.toast(AXDiagnostics.probeFrontmost(), duration: 2.5)
        }
    }

    @objc private func releaseDevice() {
        let device = self.device
        DispatchQueue.global().async { device.stop() }
    }

    @objc private func reconnectDevice() {
        if config.device.transport == .jack { jack.restart(); return }
        let device = self.device
        DispatchQueue.global().async {
            device.stop()
            DispatchQueue.main.async { device.start() }
        }
    }
}

/// Human labels for shortcut toasts.
enum KeyLabel {
    static func describe(_ combos: [String]) -> String {
        switch combos.map({ $0.lowercased() }) {
        case ["return"], ["enter"]: return L.t("Return")
        case ["shift+return"]: return L.t("New line")
        case ["cmd+a", "delete"], ["ctrl+e", "ctrl+u"]: return L.t("Cleared all")
        case ["escape"], ["esc"]: return "Esc"
        default: return combos.joined(separator: " ")
        }
    }
}
