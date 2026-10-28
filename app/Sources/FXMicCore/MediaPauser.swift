import Foundation

public enum MediaState: Equatable, Sendable { case playing, paused, stopped, notRunning }

public enum MediaPlayerID {
    public static let spotify = "spotify"
    public static let music = "music"
}

/// A music player the app can pause and resume (One-Pager 005).
public protocol MediaPlayer: AnyObject {
    var id: String { get }
    func state() -> MediaState
    func pause()
    func play()
}

/// Pauses what is playing and resumes only what it paused. Not thread safe: use one serial queue.
public final class MediaPauser: @unchecked Sendable {
    private let players: [MediaPlayer]
    private var paused: [MediaPlayer] = []

    public init(players: [MediaPlayer]) { self.players = players }

    /// Players this pauser owns that it paused and has not resumed.
    public var pausedIDs: [String] { paused.map(\.id) }

    /// Pauses every listed player that is playing. A player already paused is left alone.
    public func pause(enabled: [String]) {
        for player in players where enabled.contains(player.id) && !paused.contains(where: { $0 === player }) {
            guard player.state() == .playing else { continue }
            player.pause()
            paused.append(player)
        }
    }

    /// Resumes the players we paused, unless someone else already did or started something else.
    public func resume() {
        let list = paused
        paused.removeAll()
        for player in list where player.state() == .paused { player.play() }
    }
}
