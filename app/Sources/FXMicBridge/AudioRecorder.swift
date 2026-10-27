import AVFoundation
import os

/// Records the system default input, converted to 16 kHz mono Float32 for Whisper (TDD §3.6).
///
/// M1 drift from the TDD: the engine starts on push-to-talk instead of running continuously,
/// so there is no 300 ms pre-roll. Keeping the mic open all the time would keep macOS's
/// recording indicator on permanently; FX-MIC also enables its own mic only on handle press.
///
/// Continuous mode (jack-only connection, One-Pager 002): the engine keeps running, every
/// buffer goes to `onRaw` (the code decoder) and the last seconds are kept at the native rate,
/// so a take can start where the mic's "handle down" code started, not when it was decoded.
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

    // MARK: Continuous mode
    /// Raw mono samples and their rate, on the audio thread.
    var onRaw: (([Float], Double) -> Void)?
    /// Where the next take starts / ends, as absolute indexes of the continuous stream (set by the
    /// code decoder just before `start()` / `stop()`); nil = now.
    var captureFrom: Int?
    var captureTo: Int?
    private(set) var isContinuous = false
    private var ring: [Float] = []
    private var ringStart = 0
    private var total = 0
    private var rate = 48_000.0
    private var taking = false
    private var takeFrom = 0

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func selectInput() {
        guard let uid = inputDeviceUID, var deviceID = AudioDevices.deviceID(forUID: uid),
              let unit = engine.inputNode.audioUnit else { return }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr { log.error("cannot select input \(uid, privacy: .public): \(status, privacy: .public)") }
    }

    /// Keeps the input open and listening (idempotent; call again after changing `inputDeviceUID`).
    func startContinuous() throws {
        stopContinuous()
        let input = engine.inputNode
        selectInput()
        let format = input.outputFormat(forBus: 0)
        lock.lock()
        ring.removeAll(keepingCapacity: true); ringStart = 0; total = 0; taking = false
        rate = format.sampleRate
        lock.unlock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.appendRaw(buffer)
        }
        engine.prepare()
        try engine.start()
        isContinuous = true
        log.info("listening on \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")
    }

    func stopContinuous() {
        guard isContinuous else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isContinuous = false
        lock.lock(); taking = false; ring.removeAll(); lock.unlock()
    }

    private func appendRaw(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        lock.lock()
        ring.append(contentsOf: chunk)
        total += chunk.count
        let keep = Int(rate * 30)
        if ring.count > keep + Int(rate) {
            let drop = ring.count - keep
            ring.removeFirst(drop); ringStart += drop
        }
        let recording = taking
        let sampleRate = rate
        lock.unlock()
        onRaw?(chunk, sampleRate)
        if recording { onLevel?(Self.rmsDBFS(chunk)) }
    }

    /// Converts a slice of the native-rate stream to Whisper's 16 kHz mono.
    private static func resample(_ x: [Float], from rate: Double) -> [Float] {
        if x.isEmpty || rate == sampleRate { return x }
        let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(x.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(x.count) * sampleRate / rate) + 64)
        else { return [] }
        x.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
        input.frameLength = AVAudioFrameCount(x.count)
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let out = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: out, count: Int(output.frameLength)))
    }

    func start() throws {
        if isContinuous {
            lock.lock()
            // Without a decoded code time, take a little of what came before the call.
            takeFrom = max(ringStart, captureFrom ?? total - Int(rate * 0.4))
            captureFrom = nil
            taking = true
            lock.unlock()
            return
        }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let input = engine.inputNode
        selectInput()
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
        if isContinuous {
            lock.lock()
            taking = false
            let end = min(total, captureTo ?? total)
            captureTo = nil
            let from = max(ringStart, takeFrom)
            let slice = end > from ? Array(ring[(from - ringStart)..<(end - ringStart)]) : []
            let sampleRate = rate
            lock.unlock()
            return Self.resample(slice, from: sampleRate)
        }
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
