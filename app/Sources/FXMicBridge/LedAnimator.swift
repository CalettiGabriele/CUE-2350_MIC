import FXMicCore
import Foundation

/// Drives the 8 LEDs in manual mode (One-Pager 001 §3): idle = mode + binary slot,
/// recording = red "KITT" sweep, processing = alternating reds, error = red blink.
/// Sends `_L(mask)` to the RAM agent only when the mask changes.
@MainActor
final class LedAnimator {
    enum State: Equatable { case idle, recording, processing, error }

    var send: ((String) -> Void)?
    /// Current idle mask and slot number, read on every frame.
    var idleMask: () -> UInt8 = { 0 }
    var slotNumber: () -> Int? = { nil }
    var map = Array(0..<8)
    var frameMs: Double = 120 {
        didSet { if timer != nil { restartTimer() } }
    }

    private(set) var state: State = .idle
    private var frame = 0
    private var timer: Timer?
    private var lastSent: UInt8?
    private var errorUntil: Date?

    func set(_ newState: State) {
        if newState == .error {
            errorUntil = Date().addingTimeInterval(0.8)
        }
        guard newState != state else { return }
        state = newState
        frame = 0
        if state == .idle {
            timer?.invalidate()
            timer = nil
            render()
        } else {
            restartTimer()
            render()
        }
    }

    /// Re-sends the idle state (mode/slot changed, device reconnected).
    func refresh(force: Bool = false) {
        if force { lastSent = nil }
        if state == .idle { render() }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frameMs / 1000, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        frame += 1
        if state == .error, let until = errorUntil, Date() > until {
            set(.idle)
            return
        }
        render()
    }

    private func render() {
        let logical: UInt8
        switch state {
        case .idle: logical = idleMask()
        case .recording: logical = LedPattern.kitt(frame: frame, slot: slotNumber())
        // Processing alternates more slowly than the sweep.
        case .processing: logical = LedPattern.processing(frame: frame / 2, slot: slotNumber())
        case .error: logical = LedPattern.error(frame: frame / 2)
        }
        let mask = LedPattern.physical(logical, map: map)
        guard mask != lastSent else { return }
        lastSent = mask
        send?(DeviceProtocol.ledMaskCommand(mask))
    }
}
