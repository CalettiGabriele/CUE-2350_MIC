import FXMicCore
import Foundation

/// Drives the 8 LEDs in manual mode (One-Pager 001 §3): idle = mode + binary slot,
/// recording = red "KITT" sweep, processing = alternating reds, error = red blink, boot = one
/// pass down all 8 LEDs when the mic connects.
/// Sends `_L(mask)` to the RAM agent only when the mask changes; `onMask` mirrors the logical
/// mask on screen (HUD, Settings).
@MainActor
final class LedAnimator {
    enum State: Equatable { case idle, recording, processing, error, boot, confirm }

    var send: ((String) -> Void)?
    /// Logical mask (bits 0–3 red, 4–7 white), called whenever it changes.
    var onMask: ((UInt8) -> Void)?
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
    private var lastLogical: UInt8?
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
        if force { lastSent = nil; lastLogical = nil }
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
        if state == .boot, frame >= LedPattern.bootFrames {
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
        case .boot: logical = LedPattern.boot(frame: frame)
        // Waiting for a yes on the mic: the red LEDs blink until it comes.
        case .confirm: logical = LedPattern.error(frame: frame / 3)
        }
        if logical != lastLogical {
            lastLogical = logical
            onMask?(logical)
        }
        let mask = LedPattern.physical(logical, map: map)
        guard mask != lastSent else { return }
        lastSent = mask
        send?(DeviceProtocol.ledMaskCommand(mask))
    }
}
