import FXMicCore
import SwiftUI

/// Settings window (TDD §3.9), laid out as chapters of the guide: a numbered sidebar on paper,
/// one page per area with a chapter header; edits are applied with "Save".
/// All texts go through `L.t` (English keys, `ui.language`).
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var chapter: Chapter = .device

    enum Chapter: Int, CaseIterable, Identifiable {
        case device = 1, profiles, audio, speech, llm, history, general
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .device: return L.t("Device")
            case .profiles: return L.t("Profiles")
            case .audio: return L.t("Audio")
            case .speech: return L.t("Transcription")
            case .llm: return L.t("LLM")
            case .history: return L.t("History")
            case .general: return L.t("General")
            }
        }
        var kicker: String {
            switch self {
            case .device: return L.t("Buttons, LEDs and gestures, live")
            case .profiles: return L.t("Modes, slots and gestures per app")
            case .audio: return L.t("Input and recording")
            case .speech: return L.t("Whisper, on this Mac")
            case .llm: return L.t("Local model for Enhanced and Command")
            case .history: return L.t("Texts kept on this Mac")
            case .general: return L.t("Language, icon, permissions")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Theme.rule).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    ChapterHeader(number: "\(chapter.rawValue)", title: chapter.title, kicker: chapter.kicker)
                        .id(chapter)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            saveBar
        }
        .background(Theme.ground)
        .tint(Theme.accent)
        .frame(minWidth: 860, minHeight: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "CUE-2350 MIC", color: Theme.ink, size: 11)
                .padding(.bottom, 2)
            Kicker(text: L.t("User guide · chapter 8"))
                .padding(.bottom, 14)
            ForEach(Chapter.allCases) { item in
                Button { withAnimation(Theme.paperAnimation) { chapter = item } } label: {
                    HStack(spacing: 10) {
                        Rectangle().fill(chapter == item ? Theme.accent : Color.clear).frame(width: 3, height: 22)
                        Text(Theme.chapter("\(item.rawValue)"))
                            .font(Theme.mono(10, semibold: true))
                            .foregroundStyle(chapter == item ? Theme.accent : Theme.muted)
                            .frame(width: 30, alignment: .leading)
                        Text(item.title.lowercased())
                            .font(Theme.display(16, chapter == item ? .extrabold : .semibold))
                            .foregroundStyle(Theme.ink.opacity(chapter == item ? 1 : 0.75))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { bit in
                    LEDDot(on: model.ledMask & (1 << bit) != 0, red: bit < 4, size: 6)
                }
            }
            .padding(.bottom, 8)
            .help(L.t("The mic's LEDs, live"))
            Text("UNOFFICIAL · NOT AFFILIATED WITH TEENAGE ENGINEERING")
                .font(Theme.mono(8))
                .tracking(Theme.monoTracking(8))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var page: some View {
        switch chapter {
        case .device: DevicePage(model: model) { chapter = .profiles }
        case .profiles: ProfilesTab(model: model)
        case .audio: AudioTab(model: model)
        case .speech: SpeechTab(model: model)
        case .llm: LLMTab(model: model)
        case .history: HistoryTab(model: model).padding(.horizontal, 24).padding(.vertical, 12)
        case .general: GeneralTab(model: model)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(model.hasChanges ? Theme.accent : Theme.rule).frame(height: 1)
            HStack(spacing: 10) {
                if model.hasChanges {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Kicker(text: L.t("Unsaved changes"), color: Theme.ink)
                }
                Spacer()
                Button(L.t("Discard changes")) { model.revert() }
                    .buttonStyle(FlatButtonStyle())
                    .disabled(!model.hasChanges)
                Button(L.t("Save")) { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(FlatButtonStyle(prominent: true))
                    .disabled(!model.hasChanges)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .animation(.linear(duration: 0.12), value: model.hasChanges)
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
                    Text(L.t("Grille (default)")).tag("auto")
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
        .scrollContentBackground(.hidden)
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

/// The mic as the main page: live drawing (LEDs, pressed buttons) and, for each control,
/// what it does in the active profile. Click a part of the drawing to highlight its row.
private struct DevicePage: View {
    @ObservedObject var model: SettingsModel
    var openProfiles: () -> Void
    @State private var highlight: MicPart?

    private var profile: Profile? {
        model.saved.profiles.first { $0.id == model.activeProfileID } ?? model.saved.profiles.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 14) {
                MicDrawing(mask: model.ledMask, pressed: model.pressedControls, highlight: highlight) { part in
                    withAnimation(Theme.paperAnimation) { highlight = highlight == part ? nil : part }
                }
                .frame(width: 230)
                Kicker(text: model.deviceConnected ? L.t("Connected") : L.t("Not connected"),
                       color: model.deviceConnected ? Theme.accent : Theme.muted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusBlock
                    if let profile {
                        HStack {
                            Kicker(text: L.f("Profile in use: %@", profile.name), color: Theme.ink)
                            Spacer()
                            Button(L.t("Edit in Profiles")) { openProfiles() }.buttonStyle(FlatButtonStyle())
                        }
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                        controlRow(.orange, name: L.t("Orange"), rows: [
                            (L.t("tap"), profile.orange.tap), (L.t("double tap"), profile.orange.doubleTap),
                            (L.t("long press"), profile.orange.longPress)])
                        controlRow(.white, name: L.t("White"), rows: [
                            (L.t("tap"), profile.white.tap), (L.t("double tap"), profile.white.doubleTap),
                            (L.t("long press"), profile.white.longPress)])
                        controlRow(.grey, name: L.t("Grey"), rows: [
                            (L.t("tap"), profile.grey.tap), (L.t("double tap"), profile.grey.doubleTap),
                            (L.t("long press"), profile.grey.longPress), (L.t("while dictating"), profile.chord)])
                        controlRow(.handle, name: L.t("Handle"), rows: [
                            (L.t("hold"), nil), (L.t("double click"), profile.handle.doubleClick)])
                        controlRow(nil, name: L.t("Shake"), rows: [
                            (L.t("short"), profile.shake.short), (L.t("hold 2 s"), profile.shake.hold)])
                    }
                }
                .padding(.trailing, 24)
            }
        }
        .padding(.leading, 24)
        .padding(.top, 14)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.deviceStatus).font(.callout).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Button(L.t("Reconnect")) { model.onReconnectDevice?() }.buttonStyle(FlatButtonStyle())
                Button(L.t("Release (restore the mic)")) { model.onReleaseDevice?() }.buttonStyle(FlatButtonStyle())
                Button(L.t("Test LEDs")) { model.onTestLEDs?() }.buttonStyle(FlatButtonStyle()).disabled(!model.deviceConnected)
            }
            Text(L.t("The app controls the mic with an agent loaded in RAM only: quitting the app or switching the mic off restores the factory behaviour."))
                .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One control: name chip, then "gesture / action" lines; the highlighted one gets the
    /// orange bar (guide-style callout).
    private func controlRow(_ part: MicPart?, name: String, rows: [(String, Action?)]) -> some View {
        let active = part != nil && part == highlight
        let pressed = part.map { model.pressedControls.contains($0.control) } ?? false
        return HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(active || pressed ? Theme.accent : Color.clear).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(name.lowercased()).font(Theme.display(18, .extrabold)).foregroundStyle(Theme.ink)
                    if pressed { Kicker(text: L.t("Pressed"), color: Theme.accent) }
                }
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("/").font(Theme.mono(11, semibold: true)).foregroundStyle(Theme.accent)
                        Kicker(text: rows[i].0).frame(width: 120, alignment: .leading)
                        Text(rows[i].1.map(ActionRow.describe) ?? L.t("Dictate (push to talk)"))
                            .font(.callout).foregroundStyle(Theme.ink)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { if let part { withAnimation(Theme.paperAnimation) { highlight = highlight == part ? nil : part } } }
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
        .scrollContentBackground(.hidden)
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
        .scrollContentBackground(.hidden)
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
        .scrollContentBackground(.hidden)
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
