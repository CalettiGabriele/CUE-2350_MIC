import AppKit
import FXMicCore
import SwiftUI

/// Channels chapter: the destinations of the orange button, one red LED each (One-Pager 004 §4).
/// Windows and agent sessions are bound from the mic (long press on orange); here they can be
/// renamed, reordered and removed, and whole apps can be added.
struct ChannelsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmClear = false

    private var channels: [Channel] { model.draft.channels }

    var body: some View {
        Form {
            Section {
                if channels.isEmpty {
                    Text(L.t("No channels yet. Long-press orange on the window you are working in, or add an app below."))
                        .foregroundStyle(.secondary)
                }
                ForEach(channels.indices, id: \.self) { i in row(i) }
                if channels.count < Channel.maxCount {
                    Menu(L.t("Add an app…")) {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app) }
                        }
                        Divider()
                        Button(L.t("Choose from disk…")) { chooseFromDisk() }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                if !channels.isEmpty {
                    Button(L.t("Clear all channels…"), role: .destructive) { confirmClear = true }
                        .confirmationDialog(L.t("Clear all channels?"), isPresented: $confirmClear) {
                            Button(L.t("Clear all"), role: .destructive) { model.draft.channels.removeAll() }
                        } message: {
                            Text(L.t("They are removed when you press Save. Windows and sessions are not touched."))
                        }
                }
            } header: {
                Text(L.f("Channels (orange, red LEDs) — %d/%d", channels.count, Channel.maxCount))
            } footer: {
                Text(L.t("Talking goes where you are: on the window of a channel it is that channel, anywhere else it is free and the voice goes where your cursor is, with no jump. Orange: tap = go to the next channel, double tap = previous, long press = add the window in front as a channel (the next free one; with four taken it replaces the one you are on), hold 3 s = clear all channels."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text(L.t("A session of Claude or Codex is bound from the mic: open it, then long-press orange. Here you can only add a whole app. Other agent apps with several sessions in one window can be added under sessionAdapters in config.json."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L.t("Show config.json in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
                }
            } header: {
                Text(L.t("Sessions"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ i: Int) -> some View {
        HStack(spacing: 10) {
            RedLEDs(position: i)
            VStack(alignment: .leading, spacing: 3) {
                HintField(hint: L.t("Name"), text: $model.draft.channels[i].name)
                HStack(spacing: 6) {
                    AppLabel(bundleID: channels[i].bundleID)
                    Text(detail(channels[i])).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { move(i, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
            Button { move(i, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(i == channels.count - 1)
            Button { model.draft.channels.remove(at: i) } label: { Image(systemName: "minus.circle") }
                .help(L.t("Unbind this channel"))
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    /// What the channel points to, besides the app.
    private func detail(_ channel: Channel) -> String {
        if let session = channel.session {
            return L.t("session") + " " + String(session.prefix(13))
        }
        if let link = channel.link {
            return (link.contains("/project/") ? L.t("project") : L.t("chat")) + " " + String(link.suffix(8))
        }
        if let document = channel.document, let name = URL(string: document)?.lastPathComponent, !name.isEmpty {
            return name
        }
        if let title = channel.title { return "“\(title)”" }
        return L.t("whole app")
    }

    private func move(_ i: Int, by delta: Int) {
        let j = i + delta
        guard model.draft.channels.indices.contains(j) else { return }
        model.draft.channels.swapAt(i, j)
    }

    // MARK: Adding apps

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        add(bundleID: id, name: SessionLocator.displayName(bundleID: id) ?? app.localizedName ?? id)
    }

    private func add(bundleID: String, name: String) {
        let channel = Channel(name: name, bundleID: bundleID)
        // A whole app that is already a channel is not added twice.
        guard model.draft.channels.count < Channel.maxCount,
              !model.draft.channels.contains(where: { $0.sameTarget(as: channel) }) else { return }
        model.draft.channels.append(channel)
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        add(bundleID: id, name: SessionLocator.displayName(bundleID: id) ?? name)
    }
}

/// The 4 red LEDs as they look when channel `position` (0 = top) is selected, on the mic's dark
/// LED strip.
private struct RedLEDs: View {
    let position: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { led in
                LEDDot(on: led == position, red: true, size: 5)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(Capsule().fill(Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x38 / 255)))
        .help(L.f("Red LED %d", position + 1))
    }
}
