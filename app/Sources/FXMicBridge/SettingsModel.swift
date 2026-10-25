import AppKit
import AVFoundation
import FXMicCore
import SwiftUI

/// State shared by the Settings and onboarding windows (TDD §3.9). Edits happen on `draft`;
/// "Save" applies it to the running app and writes config.json.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: AppConfig
    @Published private(set) var saved: AppConfig

    // Live status pushed by the app.
    @Published var deviceStatus = "—"
    @Published var deviceConnected = false
    @Published var whisperStatus = "—"
    @Published var whisperReady = false
    @Published var llmReady = false
    @Published var llmStatus = "—"
    @Published var llmModels: [String] = []
    @Published var inputDevices: [AudioDevices.Device] = []
    @Published var history: [HistoryEntry] = []
    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false
    /// Live mirror of the mic: logical LED mask and the controls being pressed.
    @Published var ledMask: UInt8 = 0
    @Published var pressedControls: Set<DeviceControl> = []
    /// Profile in use for the frontmost app.
    @Published var activeProfileID: String?

    /// Wired by AppDelegate.
    var onApply: ((AppConfig) -> Void)?
    var onReconnectDevice: (() -> Void)?
    var onReleaseDevice: (() -> Void)?
    var onTestLEDs: (() -> Void)?
    var onDeleteHistory: ((UUID) -> Void)?
    var onClearHistory: (() -> Void)?
    var onRefreshLLM: (() -> Void)?
    var onRequestMicrophone: (() -> Void)?

    init(config: AppConfig) {
        draft = config
        saved = config
    }

    var hasChanges: Bool { draft != saved }

    func save() {
        // At most 15 slots, at most 4 channels, and at least one profile.
        for i in draft.profiles.indices {
            draft.profiles[i].slots = Array(draft.profiles[i].slots.prefix(Slot.maxCount))
        }
        draft.channels = Array(draft.channels.prefix(Channel.maxCount))
        if draft.profiles.isEmpty { draft.profiles = Profile.defaults }
        if draft.llm.providers.isEmpty { draft.llm.providers = [.ollama] }
        // Keys of the providers removed in this edit leave the Keychain with them.
        let kept = Set(draft.llm.providers.compactMap(\.apiKeyRef))
        for ref in saved.llm.providers.compactMap(\.apiKeyRef) where !kept.contains(ref) {
            KeychainStore.deleteKey(ref)
        }
        saved = draft
        onApply?(draft)
    }

    func revert() { draft = saved }

    // MARK: - Model (providers, key, test)

    func addProvider(_ preset: ProviderPreset) {
        let provider = LLMProvider.make(preset, existing: draft.llm.providers)
        draft.llm.providers.append(provider)
        draft.llm.activeProvider = provider.id
        if !preset.defaultModel.isEmpty { draft.llm.model = preset.defaultModel }
    }

    func removeActiveProvider() {
        guard draft.llm.providers.count > 1 else { return }
        draft.llm.providers.removeAll { $0.id == draft.llm.activeProvider }
        draft.llm.activeProvider = draft.llm.providers[0].id
    }

    var activeHasKey: Bool { KeychainStore.hasKey(draft.llm.active.apiKeyRef) }

    /// Stores the key at once (the Keychain is not part of the draft).
    func saveKey(_ key: String) -> Bool {
        var provider = draft.llm.active
        if provider.apiKeyRef == nil {
            provider.apiKeyRef = "fxmic.llm.\(provider.id)"
            draft.llm.active = provider
        }
        objectWillChange.send()
        return KeychainStore.setKey(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.apiKeyRef!)
    }

    func removeKey() {
        guard let ref = draft.llm.active.apiKeyRef else { return }
        objectWillChange.send()
        KeychainStore.deleteKey(ref)
    }

    /// Model ids offered by the provider being edited.
    func refreshModels() async {
        llmModels = await draft.llm.client.availableModels() ?? []
    }

    /// One tool call with the draft settings: server, key, model and tool calling together.
    func testToolCalling() async -> String {
        do {
            let ms = try await draft.llm.client.testToolCall()
            return L.f("Tool calling works (%.1f s).", ms / 1000)
        } catch {
            return L.f("Error: %@", error.localizedDescription)
        }
    }

    /// Runs a sentence as a voice command with the draft LLM settings, on the profile in use, and
    /// says what would be done (nothing is executed).
    func testCommand(_ sample: String) async -> String {
        let profile = draft.profiles.first { $0.id == activeProfileID } ?? draft.profiles.first
        guard let profile else { return L.t("No profile") }
        return await testAgent(sample, profile: profile)
    }

    /// The agent in a dry run: tools that change something are not run, the trace says what would be.
    private func testAgent(_ sample: String, profile: Profile) async -> String {
        let screen = ScreenContext(
            app: profile.name, profile: profile.name, textFormat: profile.textFormat.rawValue, language: draft.speech.language,
            channels: draft.channels.map(\.name), skills: profile.slots.filter { $0.kind == .run }.map(\.name),
            intents: profile.intents.filter { $0.value != .none }.keys.sorted(), appNotes: profile.interaction.commandHints)
        let mac = LiveMac(handler: nil, strategy: .paste, restoreClipboardMs: 0)
        let loop = AgentLoop(provider: draft.llm.client,
                             registry: ToolRegistry(BuiltInTools.standard(mac, screen: screen)
                                                    + BuiltInTools.interface(LiveUI(),
                                                                             allowOpenURL: draft.agent.enabledTools.contains("open_url"))
                                                    + BuiltInTools.user(draft.agent.userTools, runner: LiveUserRunner()),
                                                    disabled: Set(draft.agent.disabledTools),
                                                    riskOverrides: draft.agent.riskOverrides),
                             limits: AgentLimits(draft.agent), context: ToolContext(dryRun: true), confirm: { _ in true })
        let run = await loop.run(screen, command: sample)
        var lines = run.trace.map { "\($0.step). \($0.tool) \($0.arguments) → \($0.ok ? "" : "✗ ")\($0.result)" }
        let outcome: String
        switch run.outcome {
        case .done(let s): outcome = L.f("Done: %@", s)
        case .cannot(let s): outcome = L.f("Nothing done: %@", s)
        case .budget: outcome = L.t("Out of steps")
        case .cancelled: outcome = L.t("Cancelled")
        case .failed(let e): outcome = L.f("Error: %@", e)
        }
        lines.append(outcome + String(format: " · %d × %.1f s", run.modelCalls, run.totalMs / 1000))
        return lines.joined(separator: "\n")
    }

    /// Changes only the language and applies it at once (onboarding picker).
    func setLanguage(_ language: L.Language) {
        var updated = saved
        updated.ui.language = language
        draft.ui.language = language
        saved = updated
        onApply?(updated)
    }

    /// Called when the config changes outside the window (menu, reload).
    func externalUpdate(_ config: AppConfig) {
        let editing = hasChanges
        saved = config
        if !editing { draft = config }
    }

    func refreshDevices() { inputDevices = AudioDevices.inputs() }

    func refreshPermissions() {
        accessibilityGranted = TextInjector.isTrusted(prompt: false)
        microphoneGranted = AVCaptureDeviceAuthorization.isAuthorized
    }

    // MARK: - Profiles import/export

    func exportProfiles() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fxmic-profili.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(draft.profiles).write(to: url, options: .atomic)
    }

    /// Imported profiles replace those with the same id and are appended otherwise.
    func importProfiles() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }
        guard let profiles = try? JSONDecoder().decode([Profile].self, from: data), !profiles.isEmpty else {
            return L.t("Invalid file: a JSON list of profiles is needed")
        }
        for profile in profiles {
            if let i = draft.profiles.firstIndex(where: { $0.id == profile.id }) {
                draft.profiles[i] = profile
            } else {
                draft.profiles.append(profile)
            }
        }
        return L.f("Imported %d profiles (not saved yet)", profiles.count)
    }
}

/// Microphone authorization without prompting.
enum AVCaptureDeviceAuthorization {
    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

