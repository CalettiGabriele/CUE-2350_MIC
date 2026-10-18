import Combine
import FXMicCore
import SwiftUI

/// First-run guide (TDD §3.9) as the opening page of the unofficial chapter: the title types
/// on, five numbered steps ((8.1)…(8.5)) fill a segmented bar, and the drawn mic mirrors the
/// real one (it runs the LED "boot" pass when it connects).
struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    var onFinish: () -> Void
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let typing = Timer.publish(every: 0.045, on: .main, in: .common).autoconnect()
    @State private var typed = 0

    private static let title = "((8)) talking to your agent"

    private var steps: [StepInfo] {
        [
            StepInfo(title: L.t("Microphone"), done: model.microphoneGranted,
                     detail: L.t("Needed to record your voice while you hold the handle."),
                     actionTitle: L.t("Allow"), action: { model.onRequestMicrophone?() }),
            StepInfo(title: L.t("Accessibility"), done: model.accessibilityGranted,
                     detail: L.t("Needed to write the text where the cursor is and to send keys (Return, new line…)."),
                     actionTitle: L.t("Open System Settings"), action: {
                         TextInjector.isTrusted(prompt: true)
                         NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                     }),
            StepInfo(title: L.t("Transcription model"), done: model.whisperReady,
                     detail: L.t("Whisper runs locally.") + " " + model.whisperStatus, actionTitle: nil, action: {}),
            StepInfo(title: "EP-2350 FX MIC", done: model.deviceConnected,
                     detail: model.deviceConnected ? model.deviceStatus
                        : L.t("Connect the mic with a USB-C data cable and switch it on by pressing the handle. Without the mic you can dictate by holding right Option."),
                     actionTitle: model.deviceConnected ? nil : L.t("Reconnect"), action: { model.onReconnectDevice?() }),
            StepInfo(title: L.t("Local LLM (optional)"), done: model.llmReady,
                     detail: L.f("The \"Enhanced\" and \"Command\" modes need an OpenAI-compatible server, e.g. Ollama with %@.", model.draft.llm.model) + " " + model.llmStatus,
                     actionTitle: L.t("Check"), action: { model.onRefreshLLM?() }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            progress
            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 10) {
                    MicDrawing(mask: model.ledMask, pressed: model.pressedControls)
                        .frame(width: 150)
                    Kicker(text: model.deviceConnected ? L.t("Connected") : L.t("Not connected"),
                           color: model.deviceConnected ? Theme.accent : Theme.muted)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        Step(number: "8.\(i + 1)", info: steps[i])
                    }
                }
            }
            usage
            footer
        }
        .padding(28)
        .frame(width: 760)
        .background(Theme.ground)
        .tint(Theme.accent)
        .onAppear {
            model.refreshPermissions()
            if Theme.reduceMotion { typed = Self.title.count }
        }
        .onReceive(poll) { _ in model.refreshPermissions() }
        .onReceive(typing) { _ in if typed < Self.title.count { typed += 1 } }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Kicker(text: "EP–2350 FX–MIC · " + L.t("User guide · unofficial chapter"))
                HStack(spacing: 0) {
                    Text(String(Self.title.prefix(typed)))
                        .font(Theme.display(40))
                        .tracking(-40 * 0.03)
                        .foregroundStyle(Theme.ink)
                    Rectangle().fill(Theme.accent).frame(width: 4, height: 36)
                        .opacity(typed < Self.title.count || Int(Date().timeIntervalSince1970 * 2) % 2 == 0 ? 1 : 0.3)
                }
                .lineLimit(1)
                Text(L.t("Dictate with the EP-2350 FX MIC: hold the handle, talk, release."))
                    .font(.callout).foregroundStyle(Theme.muted)
            }
            Spacer()
            Picker("", selection: Binding(get: { model.saved.ui.language }, set: { model.setLanguage($0) })) {
                ForEach(L.Language.allCases, id: \.self) { Text($0.nativeName).tag($0) }
            }
            .labelsHidden().frame(width: 140)
        }
    }

    /// Five segments, one per step, filled orange when done.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { i in
                Rectangle().fill(steps[i].done ? Theme.accent : Theme.rule).frame(height: 4)
            }
        }
        .animation(Theme.paperAnimation, value: steps.map(\.done))
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RuleStub()
                Kicker(text: L.t("How to use it"), color: Theme.ink)
            }
            .padding(.bottom, 2)
            bullet(L.t("• Handle: hold and talk · double click = new line"))
            bullet(L.t("• Orange: interaction mode (red LEDs) · White: slots (white LEDs) · Grey: run slot or Return"))
            bullet(L.t("• Shake to cancel · shake hard for 2 s to clear everything"))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("/").font(Theme.mono(12, semibold: true)).foregroundStyle(Theme.accent)
            Text(text.hasPrefix("• ") ? String(text.dropFirst(2)) : text)
                .font(.callout).foregroundStyle(Theme.ink)
        }
    }

    private var footer: some View {
        HStack {
            Text("UNOFFICIAL · NOT AFFILIATED WITH TEENAGE ENGINEERING")
                .font(Theme.mono(9)).tracking(Theme.monoTracking(9)).foregroundStyle(Theme.muted)
            Spacer()
            Button(L.t("Start")) { onFinish() }
                .buttonStyle(FlatButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1).offset(y: -8) }
    }
}

private struct StepInfo {
    let title: String
    let done: Bool
    let detail: String
    let actionTitle: String?
    let action: () -> Void
}

private struct Step: View {
    let number: String
    let info: StepInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Theme.chapter(number))
                .font(Theme.mono(10, semibold: true))
                .foregroundStyle(info.done ? Theme.accent : Theme.muted)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(info.title.lowercased()).font(Theme.display(17, .extrabold)).foregroundStyle(Theme.ink)
                    if info.done { Kicker(text: "✓ " + L.t("Done"), color: Theme.accent) }
                }
                Text(info.detail).font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !info.done, let title = info.actionTitle {
                Button(title, action: info.action).buttonStyle(FlatButtonStyle())
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }
}
