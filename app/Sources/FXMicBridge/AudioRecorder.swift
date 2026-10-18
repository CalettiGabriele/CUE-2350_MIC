import AVFoundation
import os

/// Records the system default input, converted to 16 kHz mono Float32 for Whisper (TDD §3.6).
///
/// M1 drift from the TDD: the engine starts on push-to-talk instead of running continuously,
/// so there is no 300 ms pre-roll. Keeping the mic open all the time would keep macOS's
/// recording indicator on permanently; FX-MIC also enables its own mic only on handle press.
final class AudioRecorder {
    static let sampleRate = 16_000.0

    private let log = Logger(subsystem: "com.fxmicbridge", category: "audio")
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false)!

    /// Called on the audio thread with the RMS level (dBFS) of each buffer.
    var onLevel: ((Float) -> Void)?
    /// CoreAudio UID of the input; nil or unknown = system default input.
    var inputDeviceUID: String?

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let input = engine.inputNode
        if let uid = inputDeviceUID, var deviceID = AudioDevices.deviceID(forUID: uid), let unit = input.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { log.error("cannot select input \(uid, privacy: .public): \(status, privacy: .public)") }
        }
        let format = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: format, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        log.info("recording from \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")
    }

    /// Stops recording and returns the captured 16 kHz mono samples.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        onLevel?(Self.rmsDBFS(chunk))
    }

    static func rmsDBFS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -160 }
        let meanSquare = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        return 10 * log10(max(meanSquare, 1e-16))
    }
}
