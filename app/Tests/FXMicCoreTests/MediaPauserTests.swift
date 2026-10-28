import Foundation
import Testing
@testable import FXMicCore

private final class FakePlayer: MediaPlayer {
    let id: String
    var current: MediaState
    var log: [String] = []
    init(_ id: String, _ state: MediaState) { self.id = id; current = state }
    func state() -> MediaState { current }
    func pause() { log.append("pause"); current = .paused }
    func play() { log.append("play"); current = .playing }
}

@Suite struct MediaPauserTests {
    @Test func pausesWhatPlaysAndResumesIt() {
        let a = FakePlayer("spotify", .playing)
        let pauser = MediaPauser(players: [a])
        pauser.pause(enabled: ["spotify"])
        #expect(a.log == ["pause"])
        pauser.resume()
        #expect(a.log == ["pause", "play"])
        #expect(pauser.pausedIDs.isEmpty)
    }

    @Test func neverTouchesWhatWasNotPlaying() {
        let paused = FakePlayer("spotify", .paused), stopped = FakePlayer("music", .stopped)
        let off = FakePlayer("other", .notRunning)
        let pauser = MediaPauser(players: [paused, stopped, off])
        pauser.pause(enabled: ["spotify", "music", "other"])
        pauser.resume()
        #expect(paused.log.isEmpty && stopped.log.isEmpty && off.log.isEmpty)
    }

    @Test func onlyEnabledPlayersArePaused() {
        let a = FakePlayer("spotify", .playing), b = FakePlayer("music", .playing)
        let pauser = MediaPauser(players: [a, b])
        pauser.pause(enabled: ["music"])
        #expect(a.log.isEmpty && b.log == ["pause"])
    }

    @Test func doesNotResumeWhatTheUserAlreadyResumedOrStopped() {
        let a = FakePlayer("spotify", .playing), b = FakePlayer("music", .playing)
        let pauser = MediaPauser(players: [a, b])
        pauser.pause(enabled: ["spotify", "music"])
        a.current = .playing      // the user pressed play meanwhile
        b.current = .stopped      // or closed the track
        pauser.resume()
        #expect(a.log == ["pause"] && b.log == ["pause"])
    }

    @Test func secondResumeAndSecondPauseAreHarmless() {
        let a = FakePlayer("spotify", .playing)
        let pauser = MediaPauser(players: [a])
        pauser.pause(enabled: ["spotify"])
        pauser.pause(enabled: ["spotify"])   // already ours: not paused twice
        pauser.resume()
        pauser.resume()
        #expect(a.log == ["pause", "play"])
    }

    @Test func configDefaultsAndLenientDecoding() throws {
        let d = AppConfig.PauseMedia()
        #expect(d.enabled == false && d.apps == ["spotify", "music"])
        let c = try JSONDecoder().decode(AppConfig.Audio.self, from: Data(#"{"pauseMedia":{"enabled":true,"holdMs":99999}}"#.utf8))
        #expect(c.pauseMedia.enabled && c.pauseMedia.holdMs == 1000 && c.pauseMedia.apps == d.apps)
        let old = try JSONDecoder().decode(AppConfig.Audio.self, from: Data(#"{"minDurationMs":400}"#.utf8))
        #expect(old.pauseMedia == d)
    }
}
