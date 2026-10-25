import FXMicCore
import SwiftUI

/// Settings › Voice command (TDD voice command agent §3.6): how it works, the limits, every tool
/// with its switch and risk, the user's own tools, a dry-run test, and the place MCP servers will
/// take.
struct VoiceCommandTab: View {
    @ObservedObject var model: SettingsModel
    @State private var sample = "make the word urgent bold"
    @State private var output = ""
    @State private var running = false
    @State private var shortcuts: [String] = []

    private var agent: Binding<AppConfig.Agent> { $model.draft.agent }

    var body: some View {
        Form {
            engineSection
            limitsSection
            ForEach(ToolCatalog.groups, id: \.title) { group in
                Section(L.t(group.title)) {
                    ForEach(ToolCatalog.entries.filter { group.tools.contains($0.name) }) { entry in
                        ToolRow(entry: entry, agent: agent)
                    }
                }
            }
            myToolsSection
            testSection
            Section {
                Button(L.t("Add a server…")) {}.disabled(true)
            } header: {
                Text(L.t("MCP servers"))
            } footer: {
                Text(L.t("Coming later: the tools of MCP servers will be listed here, with the same switches and confirmations."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { shortcuts = await LiveUserRunner.shortcutNames() }
    }

    // MARK: - Engine and limits

    private var engineSection: some View {
        Section {
            Text(L.t("Hold the handle, press grey once and speak: the agent turns the sentence into actions, step by step, and can check its work. Risky actions wait for a yes on the mic: grey = yes, a shake = no."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var limitsSection: some View {
        Section(L.t("Limits")) {
            Stepper(value: agent.maxSteps, in: 1...30) { Text(L.f("Up to %d steps", model.draft.agent.maxSteps)) }
            Stepper(value: agent.timeBudgetMs, in: 5000...120000, step: 5000) {
                Text(L.f("Up to %d s per command", Int(model.draft.agent.timeBudgetMs / 1000)))
            }
            Stepper(value: agent.confirmTimeoutMs, in: 3000...30000, step: 1000) {
                Text(L.f("Confirmation: %d s to press grey", Int(model.draft.agent.confirmTimeoutMs / 1000)))
            }
        }
    }

    // MARK: - My tools

    private var myToolsSection: some View {
        Section {
            ForEach($model.draft.agent.userTools) { $tool in
                UserToolEditor(tool: $tool, shortcuts: shortcuts) {
                    model.draft.agent.userTools.removeAll { $0.id == tool.id }
                }
            }
            HStack {
                Button(L.t("Add a macro")) {
                    model.draft.agent.userTools.append(UserTool(kind: .macro, name: "", description: "", steps: [.key(["cmd+f"])]))
                }
                Button(L.t("Add a shortcut")) {
                    model.draft.agent.userTools.append(UserTool(kind: .shortcut, name: "", description: ""))
                }
            }
        } header: {
            Text(L.t("My tools"))
        } footer: {
            Text(L.t("The agent sees each tool as user_ plus its name, and uses it when your description fits the command. Write the description in English, like every prompt. A macro presses keys and types text; {{text}} takes what the agent passes in. A shortcut runs in the Shortcuts app and asks on the mic first unless you lower its risk."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Test

    private var testSection: some View {
        Section {
            HintField(hint: L.t("What you would say, e.g. go to the first channel"), text: $sample, axis: .vertical)
                .lineLimit(1...3)
            Button(running ? L.t("Running…") : L.t("Test as a voice command")) {
                running = true
                Task {
                    output = await model.testCommand(sample)
                    running = false
                }
            }.disabled(running)
            if !output.isEmpty {
                Text(output).font(.callout.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
            }
        } header: {
            Text(L.t("Test a voice command"))
        } footer: {
            Text(L.t("Uses the channels, skills, intents and tools of the profile in use, with these settings before you save them. With the agent, only reading tools really run; the others are simulated, and every step is shown."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One built-in tool: on/off, and its risk when it can change something.
private struct ToolRow: View {
    let entry: ToolCatalog.Entry
    @Binding var agent: AppConfig.Agent

    private var enabled: Binding<Bool> {
        Binding(
            get: { entry.optIn ? agent.enabledTools.contains(entry.name) : !agent.disabledTools.contains(entry.name) },
            set: { on in
                if entry.optIn {
                    agent.enabledTools.removeAll { $0 == entry.name }
                    if on { agent.enabledTools.append(entry.name) }
                } else {
                    agent.disabledTools.removeAll { $0 == entry.name }
                    if !on { agent.disabledTools.append(entry.name) }
                }
            })
    }

    private var risk: Binding<Risk> {
        Binding(get: { agent.riskOverrides[entry.name] ?? entry.risk },
                set: { agent.riskOverrides[entry.name] = $0 == entry.risk ? nil : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(entry.name, isOn: enabled).font(.callout.monospaced())
                Spacer(minLength: 8)
                if entry.risk != .read {
                    Picker("", selection: risk) {
                        Text(L.t("Runs at once")).tag(Risk.safe)
                        Text(L.t("Asks on the mic")).tag(Risk.risky)
                    }
                    .labelsHidden().fixedSize()
                } else {
                    Text(L.t("Only reads")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(entry.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

/// A macro or a shortcut the agent can call.
private struct UserToolEditor: View {
    @Binding var tool: UserTool
    let shortcuts: [String]
    let onDelete: () -> Void

    private var parameter: Binding<String> {
        Binding(get: { tool.parameter ?? "" }, set: { tool.parameter = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tool.kind == .macro ? L.t("Macro") : L.t("Shortcut")).font(.caption.weight(.semibold))
                Text(tool.toolName).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            HintField(hint: L.t("Name, e.g. sign email"), text: $tool.name)
            HintField(hint: L.t("When to use it, in English, e.g. Types my email signature"), text: $tool.description, axis: .vertical)
                .lineLimit(1...3)
            HintField(hint: L.t("Optional: what the agent passes in, e.g. Reminder text"), text: parameter)
            switch tool.kind {
            case .macro: stepsEditor
            case .shortcut: shortcutEditor
            }
            Picker(L.t("Risk"), selection: $tool.risk) {
                Text(L.t("Runs at once")).tag(Risk.safe)
                Text(L.t("Asks on the mic")).tag(Risk.risky)
            }
            if let problem = tool.problem {
                Text(L.t(problem)).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var stepsEditor: some View {
        ForEach(tool.steps.indices, id: \.self) { index in
            HStack {
                Picker("", selection: Binding(
                    get: { if case .text = tool.steps[index] { return 1 } else { return 0 } },
                    set: { tool.steps[index] = $0 == 1 ? .text("") : .key([]) })) {
                    Text(L.t("Keys…")).tag(0)
                    Text(L.t("Text…")).tag(1)
                }
                .labelsHidden().fixedSize()
                HintField(hint: stepHint(index), text: Binding(
                    get: {
                        switch tool.steps[index] {
                        case .key(let keys): return keys.joined(separator: " ")
                        case .text(let text): return text.replacingOccurrences(of: "\n", with: "\\n")
                        default: return ""
                        }
                    },
                    set: { value in
                        if case .text = tool.steps[index] {
                            tool.steps[index] = .text(value.replacingOccurrences(of: "\\n", with: "\n"))
                        } else {
                            tool.steps[index] = .key(value.split(separator: " ").map(String.init))
                        }
                    }))
                Button { tool.steps.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
        }
        Button(L.t("Add a step")) { tool.steps.append(.text("")) }
    }

    private func stepHint(_ index: Int) -> String {
        if case .text = tool.steps[index] { return L.t("e.g. Best regards,\\nGabriele or {{text}}") }
        return L.t("e.g. cmd+f")
    }

    @ViewBuilder private var shortcutEditor: some View {
        if shortcuts.isEmpty {
            HintField(hint: L.t("The shortcut's name in the Shortcuts app"), text: $tool.shortcut)
        } else {
            Picker(L.t("Shortcut"), selection: $tool.shortcut) {
                Text(L.t("Choose…")).tag("")
                ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                if !tool.shortcut.isEmpty, !shortcuts.contains(tool.shortcut) { Text(tool.shortcut).tag(tool.shortcut) }
            }
        }
        Toggle(L.t("Send the shortcut's text output back to the agent"), isOn: $tool.returnsOutput)
    }
}
