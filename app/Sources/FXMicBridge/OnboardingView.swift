import Combine
import FXMicCore
import SwiftUI

/// First-run guide (TDD §3.9): permissions, Whisper model, FX-MIC and LLM, with live status.
struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    var onFinish: () -> Void
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "mic.circle.fill").font(.system(size: 40)).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(L.t("Welcome to FXMic Bridge")).font(.title2.bold())
                    Text(L.t("Dictate with the EP-2350 FX MIC: hold the handle, talk, release."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { model.saved.ui.language }, set: { model.setLanguage($0) })) {
                    ForEach(L.Language.allCases, id: \.self) { Text($0.nativeName).tag($0) }
                }
                .labelsHidden().frame(width: 140)
            }

            Step(number: 1, title: L.t("Microphone"), done: model.microphoneGranted,
                 detail: L.t("Needed to record your voice while you hold the handle."),
                 actionTitle: L.t("Allow"), action: { model.onRequestMicrophone?() })
            Step(number: 2, title: L.t("Accessibility"), done: model.accessibilityGranted,
                 detail: L.t("Needed to write the text where the cursor is and to send keys (Return, new line…)."),
                 actionTitle: L.t("Open System Settings"), action: {
                     TextInjector.isTrusted(prompt: true)
                     NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                 })
            Step(number: 3, title: L.t("Transcription model"), done: model.whisperReady,
                 detail: L.t("Whisper runs locally.") + " " + model.whisperStatus, actionTitle: nil, action: {})
            Step(number: 4, title: "EP-2350 FX MIC", done: model.deviceConnected,
                 detail: model.deviceConnected ? model.deviceStatus
                    : L.t("Connect the mic with a USB-C data cable and switch it on by pressing the handle. Without the mic you can dictate by holding right Option."),
                 actionTitle: model.deviceConnected ? nil : L.t("Reconnect"), action: { model.onReconnectDevice?() })
            Step(number: 5, title: L.t("Local LLM (optional)"), done: model.llmReady,
                 detail: L.f("The \"Enhanced\" and \"Command\" modes need an OpenAI-compatible server, e.g. Ollama with %@.", model.draft.llm.model) + " " + model.llmStatus,
                 actionTitle: L.t("Check"), action: { model.onRefreshLLM?() })

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("How to use it")).font(.headline)
                Text(L.t("• Handle: hold and talk · double click = new line"))
                Text(L.t("• Orange: interaction mode (red LEDs) · White: slots (white LEDs) · Grey: run slot or Return"))
                Text(L.t("• Shake to cancel · shake hard for 2 s to clear everything"))
            }
            .font(.callout).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L.t("Start")) { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear { model.refreshPermissions() }
        .onReceive(poll) { _ in model.refreshPermissions() }
    }
}

private struct Step: View {
    let number: Int
    let title: String
    let done: Bool
    let detail: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done, let actionTitle { Button(actionTitle, action: action) }
        }
    }
}
