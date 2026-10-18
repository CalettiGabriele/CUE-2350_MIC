import FXMicCore
import SwiftUI

/// Settings window (TDD §3.9): one tab per area, edits are applied with "Save".
/// All texts go through `L.t` (English keys, `ui.language`).
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var tab = "general"

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                GeneralTab(model: model).tabItem { Label(L.t("General"), systemImage: "gearshape") }.tag("general")
                DeviceTab(model: model).tabItem { Label(L.t("Device"), systemImage: "mic") }.tag("device")
                AudioTab(model: model).tabItem { Label(L.t("Audio"), systemImage: "waveform") }.tag("audio")
                SpeechTab(model: model).tabItem { Label(L.t("Transcription"), systemImage: "text.bubble") }.tag("speech")
                LLMTab(model: model).tabItem { Label(L.t("LLM"), systemImage: "sparkles") }.tag("llm")
                ProfilesTab(model: model).tabItem { Label(L.t("Profiles"), systemImage: "person.2") }.tag("profiles")
                HistoryTab(model: model).tabItem { Label(L.t("History"), systemImage: "clock") }.tag("history")
            }
            .padding(12)
            Divider()
            HStack {
                if model.hasChanges {
                    Label(L.t("Unsaved changes"), systemImage: "circle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
                Spacer()
                Button(L.t("Discard changes")) { model.revert() }.disabled(!model.hasChanges)
                Button(L.t("Save")) { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasChanges)
            }
            .padding(12)
        }
        .frame(minWidth: 780, minHeight: 600)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(L.t("Language")) {
                Picker(L.t("Menus, windows and messages"), selection: $model.draft.ui.language) {
                    ForEach(L.Language.allCases, id: \.self) { Text($0.nativeName).tag($0) }
                }
                Text(L.t("Applied when you save. Dictation and transcription language are set in the Transcription tab."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("Menu bar icon")) {
                Picker(L.t("Icon"), selection: $model.draft.ui.menuBarIcon) {
                    Text(L.t("Automatic")).tag("auto")
                    ForEach(MenuBarIconPreset.allCases, id: \.rawValue) { preset in
                        Label(L.t(preset.label), systemImage: preset.symbolName).tag(preset.rawValue)
                    }
                    if model.draft.ui.menuBarIconFile != nil { Text(L.t("Custom file")).tag("file") }
                }
                Text(L.t("For a custom SVG, PDF or PNG file use the menu › Menu bar icon › Choose file…."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("Writing text")) {
                Picker(L.t("Default strategy"), selection: $model.draft.injection.defaultStrategy) {
                    Text(L.t("Paste (recommended)")).tag(InjectionStrategy.paste)
                    Text(L.t("Accessibility")).tag(InjectionStrategy.ax)
                    Text(L.t("Typing")).tag(InjectionStrategy.type)
                }
                Stepper(value: $model.draft.injection.restoreClipboardMs, in: 100...2000, step: 50) {
                    Text(L.f("Restore clipboard after %d ms", Int(model.draft.injection.restoreClipboardMs)))
                }
            }
            Section(L.t("Permissions")) {
                PermissionRow(title: L.t("Microphone"), granted: model.microphoneGranted) {
                    model.onRequestMicrophone?()
                }
                PermissionRow(title: L.t("Accessibility (write text and keys)"), granted: model.accessibilityGranted) {
                    TextInjector.isTrusted(prompt: true)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            Section(L.t("Files")) {
                HStack {
                    Text(ConfigStore.fileURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button(L.t("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL]) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            if !granted { Button(L.t("Grant…"), action: action) }
        }
    }
}

// MARK: - Device

private struct DeviceTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("EP-2350 FX MIC") {
                LabeledContent(L.t("Status"), value: model.deviceStatus)
                HStack {
                    Button(L.t("Reconnect")) { model.onReconnectDevice?() }
                    Button(L.t("Release (restore the mic)")) { model.onReleaseDevice?() }
                    Button(L.t("Test LEDs")) { model.onTestLEDs?() }.disabled(!model.deviceConnected)
                }
                Text(L.t("The app controls the mic with an agent loaded in RAM only: quitting the app or switching the mic off restores the factory behaviour."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("Gestures")) {
                Text(L.t("The list of gestures and default actions is in docs/GESTURES.md. Actions are assigned per profile in the Profiles tab."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio

private struct AudioTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(L.t("Input")) {
                Picker(L.t("Microphone"), selection: $model.draft.audio.inputDeviceUID) {
                    Text(L.t("System default")).tag(String?.none)
                    ForEach(model.inputDevices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                Button(L.t("Refresh list")) { model.refreshDevices() }
                Text(L.t("To use the FX-MIC voice from the jack you need a USB audio interface with a line input: it will appear in this list."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("Recording")) {
                Stepper(value: $model.draft.audio.minDurationMs, in: 100...1500, step: 50) {
                    Text(L.f("Minimum duration %d ms", Int(model.draft.audio.minDurationMs)))
                }
                Stepper(value: $model.draft.audio.silenceThresholdDBFS, in: -80...(-20), step: 5) {
                    Text(L.f("Silence threshold %d dBFS", Int(model.draft.audio.silenceThresholdDBFS)))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshDevices() }
    }
}

// MARK: - Transcription

private struct SpeechTab: View {
    @ObservedObject var model: SettingsModel
    @State private var vocabulary = ""

    static let models: [(String, String)] = [
        ("openai_whisper-large-v3-v20240930_turbo_632MB", "Large v3 Turbo (632 MB, recommended)"),
        ("openai_whisper-large-v3-v20240930_626MB", "Large v3 (626 MB)"),
        ("openai_whisper-small", "Small (fast, less accurate)"),
        ("openai_whisper-base", "Base (very fast)"),
    ]
    static let languages: [(String, String)] = [
        ("auto", "Automatic"), ("en", "English"), ("it", "Italiano"), ("fr", "Français"), ("es", "Español"),
        ("pt", "Português"), ("de", "Deutsch"), ("zh", "中文"), ("ja", "日本語"), ("ru", "Русский"),
    ]

    var body: some View {
        Form {
            Section("Whisper") {
                LabeledContent(L.t("Status"), value: model.whisperStatus)
                Picker(L.t("Model"), selection: $model.draft.speech.model) {
                    ForEach(Self.models, id: \.0) { Text(L.t($0.1)).tag($0.0) }
                    if !Self.models.contains(where: { $0.0 == model.draft.speech.model }) {
                        Text(model.draft.speech.model).tag(model.draft.speech.model)
                    }
                }
                Text(L.t("A new model is downloaded and prepared when you save (a few minutes the first time)."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L.t("Dictation language"), selection: $model.draft.speech.language) {
                    ForEach(Self.languages, id: \.0) { Text($0.0 == "auto" ? L.t($0.1) : $0.1).tag($0.0) }
                }
            }
            Section(L.t("Vocabulary")) {
                TextField(L.t("Words separated by commas"), text: $vocabulary, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: vocabulary) { _, value in
                        model.draft.speech.vocabulary = value.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
                Text(L.t("Names and technical terms Whisper should recognise better."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { vocabulary = model.draft.speech.vocabulary.joined(separator: ", ") }
    }
}

// MARK: - LLM

private struct LLMTab: View {
    @ObservedObject var model: SettingsModel
    @State private var sample = "hi mark see you tomorrow at three for the meeting about the project"
    @State private var output = ""
    @State private var running = false

    var body: some View {
        Form {
            Section(L.t("Server")) {
                LabeledContent(L.t("Status"), value: model.llmStatus)
                TextField(L.t("OpenAI-compatible URL"), text: $model.draft.llm.baseURL)
                if !model.draft.llm.isLocal {
                    Label(L.t("Non-local endpoint: dictated texts would leave this Mac."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    if model.llmModels.isEmpty {
                        TextField(L.t("Model"), text: $model.draft.llm.model)
                    } else {
                        Picker(L.t("Model"), selection: $model.draft.llm.model) {
                            ForEach(model.llmModels, id: \.self) { Text($0).tag($0) }
                            if !model.llmModels.contains(model.draft.llm.model) {
                                Text(model.draft.llm.model).tag(model.draft.llm.model)
                            }
                        }
                    }
                    Button(L.t("Refresh")) { model.onRefreshLLM?() }
                }
                Toggle(L.t("Disable reasoning (much faster)"), isOn: $model.draft.llm.disableThinking)
                Stepper(value: $model.draft.llm.timeoutMs, in: 2000...60000, step: 1000) {
                    Text(L.f("Timeout %d s", Int(model.draft.llm.timeoutMs / 1000)))
                }
                HStack {
                    Text(L.t("Temperature"))
                    Slider(value: $model.draft.llm.temperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", model.draft.llm.temperature)).monospacedDigit()
                }
            }
            Section(L.t("Base instructions")) {
                TextEditor(text: $model.draft.llm.baseSystemPrompt)
                    .font(.callout).frame(minHeight: 70)
            }
            Section(L.t("Test")) {
                TextField(L.t("Test sentence"), text: $sample, axis: .vertical).lineLimit(1...3)
                Button(running ? L.t("Running…") : L.t("Test with the \"Enhanced\" instruction")) {
                    running = true
                    Task {
                        output = await model.preview(mode: PromptPreset(name: "Enhanced", prompt: InteractionSettings().enhancePrompt),
                                                     style: nil, sample: sample)
                        running = false
                    }
                }.disabled(running)
                if !output.isEmpty { Text(output).textSelection(.enabled).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

private struct HistoryTab: View {
    @ObservedObject var model: SettingsModel
    @State private var showRaw: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(L.t("Save history to disk"), isOn: $model.draft.history.enabled)
                Spacer()
                Stepper(value: $model.draft.history.retentionDays, in: 1...90) {
                    Text(L.f("Keep %d days", model.draft.history.retentionDays))
                }.disabled(!model.draft.history.enabled)
            }
            Text(L.t("History stays on this Mac only (file readable by your user only). Audio is never saved."))
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(model.history) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text("\(entry.app) · \(entry.profile) · \(entry.mode)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { copy(entry.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help(L.t("Copy"))
                            if entry.processed != nil {
                                Button { showRaw = showRaw == entry.id ? nil : entry.id } label: { Image(systemName: "text.badge.checkmark") }
                                    .buttonStyle(.borderless).help(L.t("Show the raw text"))
                            }
                            Button { model.onDeleteHistory?(entry.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(L.t("Delete"))
                        }
                        Text(entry.text).textSelection(.enabled)
                        if showRaw == entry.id { Text(L.f("Raw: %@", entry.raw)).font(.callout).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                Text(L.f("%d texts", model.history.count)).foregroundStyle(.secondary)
                Spacer()
                Button(L.t("Clear all"), role: .destructive) { model.onClearHistory?() }.disabled(model.history.isEmpty)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
