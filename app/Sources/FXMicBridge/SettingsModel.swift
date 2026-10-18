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
        // At most 15 slots, at least one interaction mode, and at least one profile.
        for i in draft.profiles.indices {
            draft.profiles[i].slots = Array(draft.profiles[i].slots.prefix(Slot.maxCount))
            if draft.profiles[i].interaction.enabled.isEmpty { draft.profiles[i].interaction.enabled = [.dictation] }
            if !draft.profiles[i].interaction.enabled.contains(draft.profiles[i].interaction.defaultMode) {
                draft.profiles[i].interaction.defaultMode = draft.profiles[i].interaction.enabled[0]
            }
        }
        if draft.profiles.isEmpty { draft.profiles = Profile.defaults }
        saved = draft
        onApply?(draft)
    }

    func revert() { draft = saved }

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

    /// Runs one profile Mode/Style on a sample sentence with the draft LLM settings.
    func preview(mode: PromptPreset, style: PromptPreset?, sample: String) async -> String {
        let messages = PromptComposer.messages(
            base: draft.llm.baseSystemPrompt, mode: mode, style: style,
            context: .init(appName: "Preview", language: draft.speech.language,
                           date: Date().formatted(date: .numeric, time: .omitted)),
            transcript: sample, selection: nil)
        do {
            return try await LLMClient(settings: draft.llm).complete(system: messages.system, user: messages.user)
        } catch {
            return L.f("Error: %@", error.localizedDescription)
        }
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

