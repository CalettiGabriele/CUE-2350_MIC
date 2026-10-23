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
        saved = draft
        onApply?(draft)
    }

    func revert() { draft = saved }

    /// Runs a sentence as a voice command with the draft LLM settings, on the profile in use, and
    /// says what would be done (nothing is executed).
    func testCommand(_ sample: String) async -> String {
        let profile = draft.profiles.first { $0.id == activeProfileID } ?? draft.profiles.first
        let context = PromptComposer.CommandContext(
            appName: profile?.name ?? "Test", language: draft.speech.language, channels: draft.channels.map(\.name),
            slots: profile?.slots.map(\.name) ?? [],
            intents: profile?.intents.filter { $0.value != .none }.keys.sorted() ?? [],
            hints: profile?.interaction.commandHints ?? "")
        let messages = PromptComposer.commandMessages(context: context, transcript: sample)
        do {
            let response = try await LLMClient(settings: draft.llm).complete(system: messages.system, user: messages.user,
                                                                            temperature: 0)
            switch CommandParser.parse(response) {
            case .success(let steps) where steps.isEmpty: return L.t("No action: nothing would be done.")
            case .success(let steps): return steps.map(\.summary).joined(separator: "\n")
            case .failure(.forbidden(let key)): return L.f("Blocked: %@", key)
            case .failure: return L.t("Not understood:") + " " + response.prefix(200)
            }
        } catch {
            return L.f("Error: %@", error.localizedDescription)
        }
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

