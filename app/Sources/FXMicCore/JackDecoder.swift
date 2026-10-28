import Foundation

/// What the FXMic firmware says over the jack (ADR-002).
public enum JackMessage: Equatable, Sendable {
    case heartbeat
    case gesture(Gesture)
    /// Orange took the mic's LEDs to this page (0-based): the Mac goes to that channel, whatever
    /// it was showing before.
    case page(Int)

    /// `name` is a key of `JackCodebook.messages`.
    public init?(name: String) {
        func button(_ s: Substring) -> MicButton? {
            switch s { case "grey": return .grey; case "white": return .white; case "orange": return .orange; default: return nil }
        }
        switch name {
        case "heartbeat": self = .heartbeat
        case "handleDown": self = .gesture(.pttDown)
        case "handleUp": self = .gesture(.pttUp)
        case "handleDoubleClick": self = .gesture(.handleDoubleClick)
        case "chordGrey": self = .gesture(.chordGrey)
        case "shake": self = .gesture(.shake)
        case "shakeHold": self = .gesture(.shakeHold)
        default:
            let parts = name.split(separator: ".")
            if parts.count == 2, parts[0] == "page", let n = Int(parts[1]), n >= 1 { self = .page(n - 1); return }
            guard parts.count == 2, let b = button(parts[1]) else { return nil }
            switch parts[0] {
            case "tap": self = .gesture(.tap(b))
            case "doubleTap": self = .gesture(.doubleTap(b))
            case "longPress": self = .gesture(.longPress(b))
            case "veryLongPress": self = .gesture(.veryLongPress(b))
            default: return nil
            }
        }
    }
}

public struct JackEvent: Equatable, Sendable {
    public let message: JackMessage
    /// Absolute index (in the fed stream) where the code starts, within about 10 ms.
    public let onsetSample: Int
}

/// Decodes the acoustic codes of the FXMic firmware from a continuous mono stream.
///
/// Every 10 ms a 20 ms window is analysed at the eight code frequencies (Goertzel, tones on
/// 1 kHz multiples are orthogonal at this length). A window names a symbol when both of its
/// tones are present and clearly above every other symbol. Three symbols in a row, with no
/// gap longer than ~50 ms, and a combination that is in the codebook, make a message.
public struct JackDecoder {
    public let sampleRate: Double
    /// Minimum amplitude (full scale = 1) of each tone of a symbol.
    public var threshold: Float
    /// Required ratio between the best symbol and the second best.
    public var separation: Float = 2.5

    private let window: Int
    private let hop: Int
    private let tones: [Double]
    private let coefficients: [Double]
    private let pairs: [(Int, Int)]            // symbol -> indexes in `tones`
    private let table: [[Int]: JackMessage]

    private var buffer: [Float] = []
    private var bufferStart = 0                // absolute index of buffer[0]
    private var nextStart = 0                  // absolute start of the next window

    private var curSymbol = -1
    private var curStart = 0
    private var curLength = 0
    private var runs: [(start: Int, symbol: Int)] = []
    private var silence = 0
    private let minRun = 2
    /// A message was delivered early and its last symbol is still sounding.
    private var delivered = false

    public init(sampleRate: Double, threshold: Float = 0.008) {
        self.sampleRate = sampleRate
        self.threshold = threshold
        window = Int(sampleRate * 0.02)
        hop = Int(sampleRate * 0.01)
        var all: [Double] = []
        var pairs: [(Int, Int)] = []
        for (a, b) in JackCodebook.symbols {
            for f in [a, b] where !all.contains(f) { all.append(f) }
            pairs.append((all.firstIndex(of: a)!, all.firstIndex(of: b)!))
        }
        tones = all
        self.pairs = pairs
        coefficients = all.map { 2 * cos(2 * Double.pi * $0 / sampleRate) }
        var t: [[Int]: JackMessage] = [:]
        for (name, symbols) in JackCodebook.messages {
            if let m = JackMessage(name: name) { t[symbols] = m }
        }
        table = t
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        bufferStart = 0; nextStart = 0
        curSymbol = -1; curLength = 0; runs.removeAll(); silence = 0; delivered = false
    }

    public mutating func feed(_ samples: [Float]) -> [JackEvent] {
        buffer.append(contentsOf: samples)
        var events: [JackEvent] = []
        while nextStart + window <= bufferStart + buffer.count {
            let offset = nextStart - bufferStart
            let label = symbol(in: offset)
            if let e = step(label, windowStart: nextStart) { events.append(e) }
            nextStart += hop
            // Keep the buffer short: nothing before the next window is needed.
            let drop = nextStart - bufferStart
            if drop > 48_000 {
                buffer.removeFirst(drop)
                bufferStart += drop
            }
        }
        return events
    }

    // MARK: - Analysis

    private func amplitudes(at offset: Int) -> [Float] {
        var out = [Float](repeating: 0, count: tones.count)
        buffer.withUnsafeBufferPointer { p in
            for (i, c) in coefficients.enumerated() {
                var s1 = 0.0, s2 = 0.0
                for n in 0..<window {
                    let s0 = Double(p[offset + n]) + c * s1 - s2
                    s2 = s1; s1 = s0
                }
                let power = s1 * s1 + s2 * s2 - c * s1 * s2
                out[i] = Float(max(power, 0).squareRoot() * 2 / Double(window))
            }
        }
        return out
    }

    private func symbol(in offset: Int) -> Int {
        let a = amplitudes(at: offset)
        var best = -1
        var bestScore: Float = 0, second: Float = 0
        for (k, pair) in pairs.enumerated() {
            let score = min(a[pair.0], a[pair.1])
            if score > bestScore { second = bestScore; bestScore = score; best = k }
            else if score > second { second = score }
        }
        guard best >= 0, bestScore >= threshold, bestScore >= separation * second else { return -1 }
        return best
    }

    private mutating func closeRun() {
        if curSymbol >= 0, curLength >= minRun { runs.append((curStart, curSymbol)) }
        curSymbol = -1; curLength = 0
    }

    private mutating func step(_ label: Int, windowStart: Int) -> JackEvent? {
        if label >= 0 {
            silence = 0
            if label == curSymbol {
                curLength += 1
                // The third symbol is stable and the three make a known message: deliver now,
                // without waiting for the silence after it.
                if !delivered, curLength == minRun, runs.count == 2,
                   let message = table[runs.map(\.symbol) + [label]] {
                    let event = JackEvent(message: message, onsetSample: runs[0].start + window / 2)
                    runs.removeAll()
                    delivered = true
                    return event
                }
                return nil
            }
            if delivered { delivered = false; curSymbol = -1; curLength = 0 } else { closeRun() }
            curSymbol = label; curStart = windowStart; curLength = 1
            return nil
        }
        silence += 1
        if delivered {
            if silence == 1 { delivered = false; curSymbol = -1; curLength = 0 }
            return nil
        }
        if silence == 1 { closeRun() }
        // A complete, valid message needs 2 quiet windows; anything else waits 5 and is dropped.
        guard !runs.isEmpty, silence >= (runs.count == 3 ? 2 : 5) else { return nil }
        defer { runs.removeAll() }
        guard runs.count == 3, let message = table[runs.map(\.symbol)] else { return nil }
        return JackEvent(message: message, onsetSample: runs[0].start + window / 2)
    }
}
