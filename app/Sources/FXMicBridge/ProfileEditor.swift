import AppKit
import FXMicCore
import SwiftUI
import UniformTypeIdentifiers

/// Profiles tab: list on the left, editor on the right (TDD §3.9 item 5).
struct ProfilesTab: View {
    @ObservedObject var model: SettingsModel
    @State private var selection: String?
    @State private var notice: String?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    ForEach(model.draft.profiles, id: \.id) { profile in
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text(profile.apps.isEmpty ? L.t("All other apps") : L.f("%d apps", profile.apps.count))
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(Optional(profile.id))
                    }
                }
                HStack(spacing: 4) {
                    Button { add() } label: { Image(systemName: "plus") }.help(L.t("New profile"))
                    Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }.help(L.t("Duplicate")).disabled(selection == nil)
                    Button { remove() } label: { Image(systemName: "minus") }.help(L.t("Delete"))
                        .disabled(selection == nil || model.draft.profiles.count < 2)
                    Spacer()
                    Menu {
                        Button(L.t("Import profiles…")) { notice = model.importProfiles() }
                        Button(L.t("Export profiles…")) { model.exportProfiles() }
                        Divider()
                        Button(L.t("Restore default profiles")) { model.draft.profiles = Profile.defaults; selection = model.draft.profiles.first?.id }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                .buttonStyle(.borderless)
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(minWidth: 180, maxWidth: 220)

            Group {
                if let index = model.draft.profiles.firstIndex(where: { $0.id == selection }) {
                    ProfileDetail(model: model, profile: $model.draft.profiles[index])
                        .id(model.draft.profiles[index].id)
                } else {
                    Text(L.t("Select a profile")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 480)
        }
        .onAppear { if selection == nil { selection = model.draft.profiles.first?.id } }
    }

    private func uniqueID(_ base: String) -> String {
        var id = base
        var n = 2
        while model.draft.profiles.contains(where: { $0.id == id }) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    private func add() {
        var profile = Profile(id: uniqueID("profile"), name: L.t("New profile"))
        model.draft.profiles.append(profile)
        selection = profile.id
    }

    private func duplicate() {
        guard let source = model.draft.profiles.first(where: { $0.id == selection }) else { return }
        var copy = source
        copy.id = uniqueID(source.id)
        copy.name = source.name + L.t(" (copy)")
        copy.apps = []
        model.draft.profiles.append(copy)
        selection = copy.id
    }

    private func remove() {
        model.draft.profiles.removeAll { $0.id == selection }
        selection = model.draft.profiles.first?.id
    }
}

private struct ProfileDetail: View {
    @ObservedObject var model: SettingsModel
    @Binding var profile: Profile
    @State private var sample = "hi mark see you tomorrow at three for the meeting about the project"
    @State private var previewOutput = ""
    @State private var previewing = false

    var body: some View {
        Form {
            Section(L.t("Profile")) {
                TextField(L.t("Name"), text: $profile.name)
                Picker(L.t("Language"), selection: $profile.language) {
                    Text(L.t("Same as Transcription")).tag(String?.none)
                    Text(L.t("Automatic")).tag(String?.some("auto"))
                    Text("Italiano").tag(String?.some("it"))
                    Text("English").tag(String?.some("en"))
                }
                Picker(L.t("Writing text"), selection: $profile.injection) {
                    Text(L.t("Same as general setting")).tag(InjectionStrategy?.none)
                    Text(L.t("Paste")).tag(InjectionStrategy?.some(.paste))
                    Text(L.t("Accessibility")).tag(InjectionStrategy?.some(.ax))
                    Text(L.t("Typing")).tag(InjectionStrategy?.some(.type))
                }
            }

            Section {
                if profile.apps.isEmpty {
                    Text(L.t("No apps: this profile is used for every app not assigned to another one.")).foregroundStyle(.secondary)
                }
                ForEach(profile.apps, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button { profile.apps.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button(L.t("Add app…")) { addApp() }
            } header: { Text(L.t("Apps")) }

            ModesSection(interaction: $profile.interaction)

            Section(L.t("Preview of \"Enhanced\"")) {
                TextField(L.t("Test sentence"), text: $sample, axis: .vertical).lineLimit(1...3)
                Button(previewing ? L.t("Running…") : L.t("Test")) { runPreview() }.disabled(previewing)
                if !previewOutput.isEmpty { Text(previewOutput).textSelection(.enabled).foregroundStyle(.secondary) }
            }

            SlotsSection(slots: $profile.slots)

            Section(L.t("Gestures")) {
                ActionRow(label: L.t("Orange · tap"), action: $profile.orange.tap)
                ActionRow(label: L.t("Orange · double tap"), action: $profile.orange.doubleTap)
                ActionRow(label: L.t("Orange · long press"), action: $profile.orange.longPress)
                ActionRow(label: L.t("White · tap"), action: $profile.white.tap)
                ActionRow(label: L.t("White · double tap"), action: $profile.white.doubleTap)
                ActionRow(label: L.t("White · long press"), action: $profile.white.longPress)
                ActionRow(label: L.t("Grey · tap"), action: $profile.grey.tap)
                ActionRow(label: L.t("Grey · double tap"), action: $profile.grey.doubleTap)
                ActionRow(label: L.t("Grey · long press"), action: $profile.grey.longPress)
                ActionRow(label: L.t("Grey while dictating"), action: $profile.chord)
                ActionRow(label: L.t("Handle · double click"), action: $profile.handle.doubleClick)
                ActionRow(label: L.t("Short shake"), action: $profile.shake.short)
                ActionRow(label: L.t("Long shake (2 s)"), action: $profile.shake.hold)
            }
        }
        .formStyle(.grouped)
    }

    private func runPreview() {
        previewing = true
        Task {
            previewOutput = await model.preview(mode: PromptPreset(name: "Enhanced", prompt: profile.interaction.enhancePrompt),
                                                style: nil, sample: sample)
            previewing = false
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !profile.apps.contains(id) {
                profile.apps.append(id)
            }
        }
    }
}

/// Orange button: which interaction modes the profile offers (One-Pager 001 §1).
private struct ModesSection: View {
    @Binding var interaction: InteractionSettings

    var body: some View {
        Section {
            ForEach(InteractionMode.allCases, id: \.self) { mode in
                Toggle(isOn: Binding(
                    get: { interaction.enabled.contains(mode) },
                    set: { on in
                        if on {
                            interaction.enabled = InteractionMode.allCases.filter { interaction.enabled.contains($0) || $0 == mode }
                        } else if interaction.enabled.count > 1 {
                            interaction.enabled.removeAll { $0 == mode }
                        }
                    })) {
                    HStack {
                        Text("LED \(mode.ledIndex + 1) · \(L.t(mode.label))")
                        if !mode.isAvailable { Text(L.t("not available yet")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Picker(L.t("Default mode"), selection: $interaction.defaultMode) {
                ForEach(interaction.enabled, id: \.self) { Text(L.t($0.label)).tag($0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Instruction for \"Enhanced\"")).font(.callout)
                TextField("", text: $interaction.enhancePrompt, axis: .vertical).lineLimit(2...5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("App notes for \"Command\"")).font(.callout)
                TextField(L.t("e.g. the field accepts Markdown; Return sends"), text: $interaction.commandHints, axis: .vertical)
                    .lineLimit(2...4)
            }
        } header: {
            Text(L.t("Interaction modes (orange, red LEDs)"))
        } footer: {
            Text(L.t("Tap: next mode · long press: back to the default. While recording the red LEDs run the KITT animation."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// White button: up to 15 slots shown in binary on the white LEDs (One-Pager 001 §2).
private struct SlotsSection: View {
    @Binding var slots: [Slot]

    var body: some View {
        Section {
            ForEach(slots.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(i + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
                        BinaryLEDs(number: i + 1)
                        TextField(L.t("Name"), text: $slots[i].name)
                        Picker("", selection: $slots[i].kind) {
                            Text(L.t("Run")).tag(SlotKind.run)
                            Text(L.t("Template")).tag(SlotKind.template)
                            Text("LLM").tag(SlotKind.llm)
                        }
                        .labelsHidden().frame(width: 110)
                        Button { move(i, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                        Button { move(i, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(i == slots.count - 1)
                        Button { slots.remove(at: i) } label: { Image(systemName: "minus.circle") }
                    }
                    .buttonStyle(.borderless)
                    switch slots[i].kind {
                    case .run:
                        ActionRow(label: L.t("Action (grey)"), action: $slots[i].action)
                    case .template:
                        TextField(L.t("Text with {{testo}} in place of the dictation"), text: $slots[i].template, axis: .vertical)
                            .lineLimit(1...4).font(.callout)
                    case .llm:
                        TextField(L.t("LLM instruction applied to the dictation"), text: $slots[i].template, axis: .vertical)
                            .lineLimit(1...4).font(.callout)
                    }
                }
                .padding(.vertical, 2)
            }
            if slots.count < Slot.maxCount {
                Button(L.t("Add slot")) { slots.append(.run(L.t("New slot"), .key(["return"]))) }
            }
        } header: {
            Text(L.f("Slots (white, white LEDs in binary) — %d/%d", slots.count, Slot.maxCount))
        } footer: {
            Text(L.t("White: tap = next slot, double tap = previous, long press = none. Run: grey launches it. Template and LLM: they apply to the next dictation. After use the selection goes back to \"no slot\"."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func move(_ i: Int, by delta: Int) {
        let j = i + delta
        guard slots.indices.contains(j) else { return }
        slots.swapAt(i, j)
    }
}

/// The 4 white LEDs as they will look for slot `number` (top LED = 1).
private struct BinaryLEDs: View {
    let number: Int
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { bit in
                Circle()
                    .fill(number >> bit & 1 == 1 ? Color.primary : Color.secondary.opacity(0.2))
                    .frame(width: 5, height: 5)
            }
        }
        .help(L.f("White LEDs for slot %d", number))
    }
}

/// App name and icon for a bundle identifier.
private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else {
                Image(systemName: "app.dashed")
                Text(bundleID)
            }
            Text(bundleID).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Picker for an `Action` plus its parameter.
private struct ActionRow: View {
    let label: String
    @Binding var action: Action

    enum Kind: String, CaseIterable, Identifiable {
        case none, key, text, undo, reinsertRaw, reinsertProcessed, cancel, editSelection
        case cycleMode, resetMode, nextSlot, previousSlot, clearSlot, runSlot
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return L.t("None")
            case .key: return L.t("Keys…")
            case .text: return L.t("Text…")
            case .undo: return L.t("Undo last insertion")
            case .reinsertRaw: return L.t("Rewrite last (raw)")
            case .reinsertProcessed: return L.t("Rewrite last (processed)")
            case .cancel: return L.t("Cancel dictation")
            case .editSelection: return L.t("Edit selection")
            case .cycleMode: return L.t("Next mode")
            case .resetMode: return L.t("Default mode")
            case .nextSlot: return L.t("Next slot")
            case .previousSlot: return L.t("Previous slot")
            case .clearSlot: return L.t("No slot")
            case .runSlot: return L.t("Run slot (or Return)")
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding {
            switch action {
            case .none: return .none
            case .key: return .key
            case .text: return .text
            case .undoLastInsertion: return .undo
            case .reinsertLast(let raw): return raw ? .reinsertRaw : .reinsertProcessed
            case .cancel: return .cancel
            case .editSelection: return .editSelection
            case .cycleMode: return .cycleMode
            case .resetMode: return .resetMode
            case .nextSlot: return .nextSlot
            case .previousSlot: return .previousSlot
            case .clearSlot: return .clearSlot
            case .runSlot: return .runSlot
            }
        } set: { kind in
            switch kind {
            case .none: action = .none
            case .key: action = .key(["return"])
            case .text: action = .text("")
            case .undo: action = .undoLastInsertion
            case .reinsertRaw: action = .reinsertLast(raw: true)
            case .reinsertProcessed: action = .reinsertLast(raw: false)
            case .cancel: action = .cancel
            case .editSelection: action = .editSelection
            case .cycleMode: action = .cycleMode
            case .resetMode: action = .resetMode
            case .nextSlot: action = .nextSlot
            case .previousSlot: action = .previousSlot
            case .clearSlot: action = .clearSlot
            case .runSlot: action = .runSlot
            }
        }
    }

    private var parameter: Binding<String> {
        Binding {
            switch action {
            case .key(let keys): return keys.joined(separator: " ")
            case .text(let text): return text.replacingOccurrences(of: "\n", with: "\\n")
            default: return ""
            }
        } set: { value in
            switch action {
            case .key: action = .key(value.split(separator: " ").map(String.init))
            case .text: action = .text(value.replacingOccurrences(of: "\\n", with: "\n"))
            default: break
            }
        }
    }

    private var invalidKeys: Bool {
        if case .key(let keys) = action { return keys.isEmpty || keys.contains { KeyCombo($0) == nil } }
        return false
    }

    var body: some View {
        HStack {
            Text(label).frame(width: 190, alignment: .leading)
            Picker("", selection: kind) {
                ForEach(Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 220)
            switch action {
            case .key:
                TextField(L.t("e.g. cmd+a delete"), text: parameter)
                    .foregroundStyle(invalidKeys ? .red : .primary)
                    .help(L.t("Combinations separated by spaces. Modifiers: cmd, shift, opt, ctrl. Keys: letters, digits, return, tab, space, delete, escape, arrows."))
            case .text:
                TextField(L.t("e.g. /clear\\n"), text: parameter).help(L.t("trailing \\n = also press Return"))
            default:
                Spacer()
            }
        }
    }
}
