import AppKit
import FXMicCore
import os

/// Spotify and Apple Music through their AppleScript dictionaries (One-Pager 005). Only touched on
/// `MediaController.queue`. An Apple event to an app that is not running would launch it, so the
/// running check comes first.
final class AppleScriptPlayer: MediaPlayer {
    let id: String
    let bundleID: String
    private let log = Logger(subsystem: "com.fxmicbridge", category: "media")
    private lazy var stateScript = compile("""
        tell application id "\(bundleID)"
            if player state is playing then return "playing"
            if player state is paused then return "paused"
            return "stopped"
        end tell
        """)
    private lazy var pauseScript = compile("tell application id \"\(bundleID)\" to pause")
    private lazy var playScript = compile("tell application id \"\(bundleID)\" to play")

    init(id: String, bundleID: String) { self.id = id; self.bundleID = bundleID }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    func state() -> MediaState {
        guard isRunning else { return .notRunning }
        switch run(stateScript)?.stringValue {
        case "playing": return .playing
        case "paused": return .paused
        default: return .stopped
        }
    }

    func pause() { guard isRunning else { return }; _ = run(pauseScript) }
    func play() { guard isRunning else { return }; _ = run(playScript) }

    private func compile(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private func run(_ script: NSAppleScript?) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error { log.error("\(self.id, privacy: .public): \(String(describing: error[NSAppleScript.errorNumber] ?? "?"), privacy: .public)") }
        return error == nil ? result : nil
    }

    enum Permission { case allowed, denied, undetermined, notRunning }

    /// Whether the app may send Apple events to the player. With `ask` the system dialog can appear.
    func permission(ask: Bool) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .undetermined }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch Int(status) {
        case Int(noErr): return .allowed
        case errAEEventNotPermitted: return .denied
        case Int(procNotFound): return .notRunning
        default: return .undetermined
        }
    }
}

/// Pauses the music while the handle is held and resumes it afterwards.
@MainActor
final class MediaController {
    static let players: [AppleScriptPlayer] = [
        AppleScriptPlayer(id: MediaPlayerID.spotify, bundleID: "com.spotify.client"),
        AppleScriptPlayer(id: MediaPlayerID.music, bundleID: "com.apple.Music"),
    ]

    private let queue = DispatchQueue(label: "com.fxmicbridge.media", qos: .userInitiated)
    private let pauser = MediaPauser(players: MediaController.players)
    private var config = AppConfig.PauseMedia()
    private var pending: DispatchWorkItem?
    private var holding = false

    func configure(_ new: AppConfig.PauseMedia) {
        config = new
        if !new.enabled { holdEnded() }
    }

    /// The handle went down and a take started.
    func holdStarted() {
        guard config.enabled, !holding else { return }
        holding = true
        let apps = config.apps
        let work = DispatchWorkItem { [pauser] in pauser.pause(enabled: apps) }
        pending = work
        queue.asyncAfter(deadline: .now() + config.holdMs / 1000, execute: work)
    }

    /// The take ended, for whatever reason (release, cancel, error, quit).
    func holdEnded() {
        guard holding else { return }
        holding = false
        pending?.cancel()
        pending = nil
        queue.async { [pauser] in pauser.resume() }
    }

    /// Compiles the scripts off the main thread so the first press does not pay for it.
    func warmUp() {
        guard config.enabled else { return }
        queue.async { for player in Self.players { _ = player.state() } }
    }
}
