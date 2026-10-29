import AVFoundation
import FXMicCore
import os

/// Audio-thread state of the decoder: only `AudioRecorder.onRaw` touches it.
private final class JackFeed {
    private var decoder: JackDecoder?
    private var rate = 0.0

    func feed(_ chunk: [Float], rate: Double) -> [JackEvent] {
        if decoder == nil || rate != self.rate {
            decoder = JackDecoder(sampleRate: rate)
            self.rate = rate
        }
        return decoder!.feed(chunk)
    }
}

/// The jack-only connection (One-Pager 002): listens to the audio input, decodes the FXMic
/// firmware's acoustic codes and hands them over as gestures. The same stream is the voice:
/// a take starts where the "handle down" code started and ends where "handle up" started.
@MainActor
final class JackTransport {
    /// Handle events include their capture boundary in the continuous audio stream.
    var onGesture: ((Gesture, Int?) -> Void)?
    var onStop: (() -> Void)?
    /// The mic moved its red LEDs to this channel (0-based).
    var onPage: ((Int) -> Void)?
    /// The mic's signal appeared or went away.
    var onSignalChange: (() -> Void)?

    private let log = Logger(subsystem: "com.fxmicbridge", category: "jack")
    private let recorder: AudioRecorder
    private var feed = JackFeed()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var lastSignal: Date?
    private var hadSignal = false
    /// Handle clicks are timed on the audio clock (the codes' onsets), so queueing on the mic
    /// or decoding delays do not matter: the same recognizer as the USB-C path.
    private var handle = GestureRecognizer()
    private var activity: NSObjectProtocol?
    private(set) var isListening = false
    private(set) var failed = false

    /// A heartbeat comes every 5 s: two missed ones mean the mic is off or unplugged.
    var hasSignal: Bool { lastSignal.map { Date().timeIntervalSince($0) < 12 } ?? false }

    init(recorder: AudioRecorder) { self.recorder = recorder }

    func start() {
        guard !isListening else { return }
        feed = JackFeed()
        handle = GestureRecognizer()
        lastSignal = nil
        // A jack gesture must not wait for a napping app.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "FXMic jack listening")
        hadSignal = false
        let feed = self.feed
        recorder.onRaw = { [weak self] chunk, rate in
            let events = feed.feed(chunk, rate: rate)
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(events, rate: rate) } }
        }
        do {
            try recorder.startContinuous()
            isListening = true
            failed = false
        } catch {
            failed = true
            log.error("cannot listen: \(error.localizedDescription, privacy: .public)")
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSignal() }
        }
        // The input changed under us (plugged, unplugged, sample rate): listen again.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart(after: 0.5) }
        }
    }

    func stop() {
        onStop?()
        timer?.invalidate(); timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        recorder.stopContinuous()
        recorder.onRaw = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        isListening = false
        lastSignal = nil
        hadSignal = false
        handleHeld = false
    }

    /// After the input device changed.
    func restart(after delay: TimeInterval = 0) {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.start(); self?.onSignalChange?() }
        }
    }

    private func checkSignal() {
        let now = hasSignal
        if now != hadSignal { hadSignal = now; onSignalChange?() }
    }

    private func received(_ events: [JackEvent], rate: Double) {
        for event in events {
            lastSignal = Date()
            checkSignal()
            let ms = Double(event.onsetSample) / rate * 1000
            switch event.message {
            case .heartbeat:
                // The mic never plays a heartbeat while the handle is held: if we think it is held,
                // the release code was lost. Close the take here.
                if handleHeld { release(at: event.onsetSample, ms: ms) }
            case .page(let index):
                onPage?(index)
            case .gesture(.pttDown):
                guard !handleHeld else { continue }
                handleHeld = true
                forward(handle.handle(.handle, active: true, at: ms),
                        captureSample: event.onsetSample - Int(rate * 0.05))
            case .gesture(.pttUp):
                // The mic repeats the release code: the second one finds the handle already up.
                guard handleHeld else { continue }
                release(at: event.onsetSample, ms: ms)
            case .gesture(let gesture):
                log.debug("jack \(String(describing: gesture), privacy: .public)")
                onGesture?(gesture, nil)
            }
        }
    }

    private var handleHeld = false

    private func release(at sample: Int, ms: Double) {
        handleHeld = false
        forward(handle.handle(.handle, active: false, at: ms), captureSample: sample)
    }

    private func forward(_ gestures: [Gesture], captureSample: Int? = nil) {
        for gesture in gestures { onGesture?(gesture, captureSample) }
    }
}
