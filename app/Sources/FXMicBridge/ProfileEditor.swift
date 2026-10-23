import AppKit
import FXMicCore
import SwiftUI
import UniformTypeIdentifiers

/// Profiles tab: pick a profile at the top, then edit it one part at a time (TDD §3.9 item 5).
struct ProfilesTab: View {
    @ObservedObject var model: SettingsModel
    @State private var selection: String?
    @State private var notice: String?

    private var current: Profile? { model.draft.profiles.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(Theme.rule).frame(height: 1)
            if let index = model.draft.profiles.firstIndex(where: { $0.id == selection }) {
                ProfileDetail(model: model, profile: $model.draft.profiles[index])
                    .id(model.draft.profiles[index].id)
            } else {
                Text(L.t("Select a profile")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = model.draft.profiles.first?.id } }
    }

    /// The profile in use for the app in front is chosen by the app; here you choose which one to edit.
    private var bar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Kicker(text: L.t("Editing profile"), color: Theme.ink)
                Picker("", selection: $selection) {
                    ForEach(model.draft.profiles, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
                Button { add() } label: { Image(systemName: "plus") }.help(L.t("New profile"))
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    .help(L.t("Duplicate")).disabled(selection == nil)
                Button { remove() } label: { Image(systemName: "minus") }
                    .help(L.t("Delete")).disabled(selection == nil || model.draft.profiles.count < 2)
                Spacer()
                Menu {
                    Button(L.t("Import profiles…")) { notice = model.importProfiles() }
                    Button(L.t("Export profiles…")) { model.exportProfiles() }
                    Divider()
                    Button(L.t("Restore default profiles")) {
                        model.draft.profiles = Profile.defaults
                        selection = model.draft.profiles.first?.id
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.borderless)
            if let current {
                Text(current.apps.isEmpty
                     ? L.t("Used for every app that has no profile of its own.")
                     : L.f("Used in: %@", current.apps.map(AppLabel.name(for:)).joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func uniqueID(_ base: String) -> String {
        var id = base
        var n = 2
        while model.draft.profiles.contains(where: { $0.id == id }) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    private func add() {
        let profile = Profile(id: uniqueID("profile"), name: L.t("New profile"))
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

/// One profile, edited a part at a time so every page stays short and readable.
private struct ProfileDetail: View {
    @ObservedObject var model: SettingsModel
    @Binding var profile: Profile
    @State private var part: Part = .profile

    enum Part: String, CaseIterable, Identifiable {
        case profile, skills, voice, buttons
        var id: String { rawValue }
        var title: String {
            switch self {
            case .profile: return L.t("Profile")
            case .skills: return L.t("White: skills")
            case .voice: return L.t("Voice command")
            case .buttons: return L.t("Buttons")
            }
        }
        /// What the page is for, in plain words.
        var intro: String {
            switch self {
            case .profile:
                return L.t("A profile holds the settings for one or more apps. The one for the app in front is used; a profile with no apps covers all the others.")
            case .skills:
                return L.t("White button: tap = next skill or command, double tap = previous, long press = none. The 4 white LEDs show the number in binary. The list follows the channel, so it is the one of the channel's app.")
            case .voice:
                return L.t("Hold the handle, press grey once and say what to do, in any language: write, edit the selected text, switch channel, run a skill or an intent. Here you tell the model about this app.")
            case .buttons:
                return L.t("What each gesture does in this profile. Orange switches channels, white walks through the skills, grey runs and interrupts.")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $part) {
                    ForEach(Part.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(part.intro)
                    .font(.callout).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
                switch part {
                case .profile: profilePart
                case .skills: SlotsSection(slots: $profile.slots)
                case .voice: VoiceCommandSection(hints: $profile.interaction.commandHints, intents: $profile.intents)
                case .buttons: buttonsPart
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var profilePart: some View {
        Section {
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
        } header: { Text(L.t("Profile")) }

        Section {
            if profile.apps.isEmpty {
                Text(L.t("No apps: this profile is used for every app not assigned to another one.")).foregroundStyle(.secondary)
            }
            ForEach(profile.apps, id: \.self) { bundleID in
                HStack {
                    AppLabel(bundleID: bundleID)
                    Spacer(minLength: 8)
                    Button { profile.apps.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button(L.t("Add app…")) { addApp() }
        } header: { Text(L.t("Apps")) }
    }

    /// Every gesture, grouped by button, with short labels.
    @ViewBuilder private var buttonsPart: some View {
        Section(L.t("Orange · channels")) {
            ActionRow(label: L.t("tap"), action: $profile.orange.tap)
            ActionRow(label: L.t("double tap"), action: $profile.orange.doubleTap)
            ActionRow(label: L.t("long press"), action: $profile.orange.longPress)
            ActionRow(label: L.t("hold 3 s"), action: $profile.orange.veryLongPress)
        }
        Section(L.t("White · skills and commands")) {
            ActionRow(label: L.t("tap"), action: $profile.white.tap)
            ActionRow(label: L.t("double tap"), action: $profile.white.doubleTap)
            ActionRow(label: L.t("long press"), action: $profile.white.longPress)
        }
        Section(L.t("Grey")) {
            ActionRow(label: L.t("tap"), action: $profile.grey.tap)
            ActionRow(label: L.t("double tap"), action: $profile.grey.doubleTap)
            ActionRow(label: L.t("long press"), action: $profile.grey.longPress)
            ActionRow(label: L.t("while talking"), action: $profile.chord)
        }
        Section(L.t("Handle and shake")) {
            ActionRow(label: L.t("Handle · double click"), action: $profile.handle.doubleClick)
            ActionRow(label: L.t("Short shake"), action: $profile.shake.short)
            ActionRow(label: L.t("Long shake (2 s)"), action: $profile.shake.hold)
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

/// Grey pressed while talking: the dictation is a voice command (One-Pager 004 §6). What the
/// model should know about the app, and the intents: actions with a name ("interrupt",
/// "newSession") that the profile turns into keys.
private struct VoiceCommandSection: View {
    @Binding var hints: String
    @Binding var intents: [String: Action]
    @State private var newName = ""

    private var names: [String] { intents.keys.sorted() }

    private var newNameIsValid: Bool {
        newName.range(of: "^[A-Za-z][A-Za-z0-9]{0,29}$", options: .regularExpression) != nil && intents[newName] == nil
    }

    var body: some View {
        Section {
            HintField(hint: L.t("e.g. the field accepts Markdown; Return sends"), text: $hints, axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text(L.t("Notes for the model about this app"))
        }

        Section {
            ForEach(names, id: \.self) { name in
                HStack(alignment: .top, spacing: 8) {
                    ActionRow(label: name, action: Binding(get: { intents[name] ?? .none }, set: { intents[name] = $0 }))
                    // "interrupt" is the one the grey long press uses: it stays.
                    Button { intents[name] = nil } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).disabled(name == "interrupt")
                }
            }
            HStack {
                HintField(hint: L.t("New intent name, e.g. newSession"), text: $newName)
                Button(L.t("Add intent")) {
                    intents[newName] = .key(["return"])
                    newName = ""
                }
                .disabled(!newNameIsValid)
            }
        } header: {
            Text(L.t("Intents"))
        } footer: {
            Text(L.t("An intent is a named action, like \"stop\" or \"new session\". Say it in a voice command and this profile turns it into the keys you choose here. interrupt is also the long press on grey."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// White button: up to 15 skills and commands, shown in binary on the white LEDs.
private struct SlotsSection: View {
    @Binding var slots: [Slot]

    var body: some View {
        Section {
            if slots.isEmpty {
                Text(L.t("No skills or commands yet.")).foregroundStyle(.secondary)
            }
            ForEach(slots.indices, id: \.self) { i in row(i) }
            if slots.count < Slot.maxCount {
                Button(L.t("Add skill or command")) { slots.append(.run(L.t("New slot"), .key(["return"]))) }
            }
        } header: {
            Text(L.f("Skills and commands — %d/%d", slots.count, Slot.maxCount))
        } footer: {
            Text(L.t("Command: grey runs it on the spot (keys or text, e.g. /compact). Skill / template and LLM rewrite apply to the next thing you dictate; after use the selection goes back to \"no slot\". The names are also what you say in a voice command."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Line 1: number, LEDs, name, type, order. Line 2, full width: what it does.
    private func row(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(format: "%02d", i + 1)).font(Theme.mono(11, semibold: true)).foregroundStyle(Theme.muted)
                BinaryLEDs(number: i + 1)
                HintField(hint: L.t("Name"), text: $slots[i].name)
                Picker("", selection: $slots[i].kind) {
                    Text(L.t("Command")).tag(SlotKind.run)
                    Text(L.t("Skill / template")).tag(SlotKind.template)
                    Text(L.t("LLM rewrite")).tag(SlotKind.llm)
                }
                .labelsHidden().frame(width: 150)
                Button { move(i, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                Button { move(i, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(i == slots.count - 1)
                Button { slots.remove(at: i) } label: { Image(systemName: "minus.circle") }
            }
            .buttonStyle(.borderless)
            switch slots[i].kind {
            case .run:
                ActionRow(label: "", action: $slots[i].action)
            case .template:
                HintField(hint: L.t("Text with {{text}} where the dictation goes, e.g. a skill prompt"),
                          text: $slots[i].template, axis: .vertical)
                    .lineLimit(1...4).font(.callout)
            case .llm:
                HintField(hint: L.t("What the LLM should do with the dictation, e.g. rewrite as an email"),
                          text: $slots[i].template, axis: .vertical)
                    .lineLimit(1...4).font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    private func move(_ i: Int, by delta: Int) {
        let j = i + delta
        guard slots.indices.contains(j) else { return }
        slots.swapAt(i, j)
    }
}

/// The 4 white LEDs as they will look for slot `number` (top LED = 1), on the mic's dark
/// LED strip.
private struct BinaryLEDs: View {
    let number: Int
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { bit in
                LEDDot(on: number >> bit & 1 == 1, red: false, size: 5)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(Capsule().fill(Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x38 / 255)))
        .help(L.f("White LEDs for slot %d", number))
    }
}

/// App name and icon for a bundle identifier.
struct AppLabel: View {
    let bundleID: String

    /// "Claude", "Terminal"… for a bundle identifier; the identifier itself if the app is not installed.
    static func name(for bundleID: String) -> String {
        if let name = SessionLocator.displayName(bundleID: bundleID) { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                Text(Self.name(for: bundleID)).lineLimit(1)
            } else {
                Image(systemName: "app.dashed")
                Text(bundleID).lineLimit(1)
            }
            Text(bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Picker for an `Action` plus its parameter.
struct ActionRow: View {
    let label: String
    @Binding var action: Action

    enum Kind: String, CaseIterable, Identifiable {
        case none, key, text, undo, reinsertRaw, reinsertProcessed, cancel, editSelection
        case nextChannel, previousChannel, bindChannel, clearChannels, interrupt
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
            case .editSelection: return L.t("Voice command")
            case .nextChannel: return L.t("Next channel")
            case .previousChannel: return L.t("Previous channel")
            case .bindChannel: return L.t("Bind window to channel")
            case .clearChannels: return L.t("Clear all channels")
            case .interrupt: return L.t("Interrupt (Esc)")
            case .cycleMode: return L.t("Next mode (old)")
            case .resetMode: return L.t("Default mode (old)")
            case .nextSlot: return L.t("Next slot")
            case .previousSlot: return L.t("Previous slot")
            case .clearSlot: return L.t("No slot")
            case .runSlot: return L.t("Run slot (or Return)")
            }
        }
    }

    /// Short human description ("Next mode", "Keys: cmd+a delete", "Text: /clear⏎").
    static func describe(_ action: Action) -> String {
        switch action {
        case .key(let keys): return KeyLabel.describe(keys)
        case .text(let text): return text.replacingOccurrences(of: "\n", with: " ⏎")
        default: return kind(of: action).title
        }
    }

    static func kind(of action: Action) -> Kind {
        switch action {
        case .none: return .none
        case .key: return .key
        case .text: return .text
        case .undoLastInsertion: return .undo
        case .reinsertLast(let raw): return raw ? .reinsertRaw : .reinsertProcessed
        case .cancel: return .cancel
        case .editSelection: return .editSelection
        case .nextChannel: return .nextChannel
        case .previousChannel: return .previousChannel
        case .bindChannel: return .bindChannel
        case .clearChannels: return .clearChannels
        // Other intent names can only be set in config.json.
        case .intent: return .interrupt
        case .cycleMode: return .cycleMode
        case .resetMode: return .resetMode
        case .nextSlot: return .nextSlot
        case .previousSlot: return .previousSlot
        case .clearSlot: return .clearSlot
        case .runSlot: return .runSlot
        }
    }

    private var kind: Binding<Kind> {
        Binding {
            Self.kind(of: action)
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
            case .nextChannel: action = .nextChannel
            case .previousChannel: action = .previousChannel
            case .bindChannel: action = .bindChannel
            case .clearChannels: action = .clearChannels
            case .interrupt: action = .intent("interrupt")
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
        if label.isEmpty {
            // Inside a slot there is room: the type and its keys or text share one line.
            HStack(spacing: 8) {
                picker
                parameterField
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                    Spacer(minLength: 8)
                    picker
                }
                // The keys or the text go on their own line: the page is narrow.
                parameterField
            }
        }
    }

    // The old interaction-mode actions are only listed for a profile that still has one.
    private var picker: some View {
        Picker("", selection: kind) {
            ForEach(Kind.allCases.filter { ![.cycleMode, .resetMode].contains($0) || $0 == Self.kind(of: action) }) {
                Text($0.title).tag($0)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder private var parameterField: some View {
        switch action {
        case .key:
            HintField(hint: L.t("e.g. cmd+a delete"), text: parameter)
                .foregroundStyle(invalidKeys ? .red : .primary)
                .help(L.t("Combinations separated by spaces. Modifiers: cmd, shift, opt, ctrl. Keys: letters, digits, return, tab, space, delete, escape, arrows."))
        case .text:
            HintField(hint: L.t("e.g. /clear\\n"), text: parameter).help(L.t("trailing \\n = also press Return"))
        default:
            EmptyView()
        }
    }
}

/// A text field with its hint inside the field. In a grouped Form a titled field puts the title
/// on the left and the typed text on the right, which squeezes long texts.
struct HintField: View {
    let hint: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        TextField("", text: $text, prompt: Text(hint), axis: axis)
            .labelsHidden()
            .multilineTextAlignment(.leading)
    }
}
