import Foundation
import Testing
@testable import FXMicCore

@Suite struct JackDecoderTests {
    private let rate = 48_000.0

    /// The firmware's message: three 60 ms symbols back to back (3 ms fades), `amp` per tone.
    private func message(_ name: String, amp: Float = 0.1) -> [Float] {
        var out: [Float] = []
        let n = Int(rate * 0.06), fade = Int(rate * 0.003)
        for s in JackCodebook.messages[name]! {
            let (a, b) = JackCodebook.symbols[s]
            for k in 0..<n {
                let env = Float(min(1.0, Double(k) / Double(fade), Double(n - 1 - k) / Double(fade)))
                let t = Double(k) / rate
                out.append(amp * env * Float(sin(2 * .pi * a * t) + sin(2 * .pi * b * t)))
            }
        }
        return out
    }

    private func silence(_ seconds: Double, noise: Float = 0, seed: UInt64 = 1) -> [Float] {
        var g = SeededGenerator(seed: seed)
        return (0..<Int(rate * seconds)).map { _ in noise * Float.random(in: -1...1, using: &g) }
    }

    private func decode(_ samples: [Float], chunk: Int = 1024) -> [JackEvent] {
        var d = JackDecoder(sampleRate: rate)
        var out: [JackEvent] = []
        var i = 0
        while i < samples.count {
            out += d.feed(Array(samples[i..<min(i + chunk, samples.count)]))
            i += chunk
        }
        return out
    }

    @Test func everyMessageDecodes() {
        for name in JackCodebook.messages.keys.sorted() {
            let events = decode(silence(0.3) + message(name) + silence(0.3))
            #expect(events.map(\.message) == [JackMessage(name: name)!])
        }
    }

    @Test func onsetIsWhereTheCodeStarts() {
        let lead = Int(rate * 0.5)
        let events = decode(silence(0.5) + message("handleDown") + silence(0.3))
        #expect(events.count == 1)
        #expect(abs(Double(events[0].onsetSample - lead) / rate) < 0.03)
    }

    @Test func twoMessagesBackToBack() {
        let stream = silence(0.2) + message("tap.orange") + silence(0.1) + message("longPress.white") + silence(0.3)
        #expect(decode(stream).map(\.message) == [.gesture(.tap(.orange)), .gesture(.longPress(.white))])
    }

    @Test func quietAndNoisyChannel() {
        let quiet = message("shake", amp: 0.012)   // about -39 dBFS per tone
        #expect(decode(silence(0.3, noise: 0.002) + quiet + silence(0.3, noise: 0.002)).map(\.message) == [.gesture(.shake)])
        let noisy = zip(message("chordGrey"), silence(0.18, noise: 0.01, seed: 7)).map { $0 + $1 }
        #expect(decode(silence(0.2) + noisy + silence(0.2)).map(\.message) == [.gesture(.chordGrey)])
    }

    @Test func chunkSizeDoesNotMatter() {
        let stream = silence(0.2) + message("doubleTap.grey") + silence(0.3)
        for chunk in [100, 480, 777, 4800] {
            #expect(decode(stream, chunk: chunk).map(\.message) == [.gesture(.doubleTap(.grey))], "chunk \(chunk)")
        }
    }

    @Test func voiceAndMusicAreNotCodes() {
        // Harmonic voice-like signal (150 Hz and its harmonics up to 4 kHz) plus broadband noise.
        var g = SeededGenerator(seed: 3)
        let voice: [Float] = (0..<Int(rate * 5)).map { n in
            let t = Double(n) / rate
            var v = 0.0
            for h in 1...26 { v += sin(2 * .pi * 150 * Double(h) * t) / Double(h) }
            return Float(0.2 * v) + 0.01 * Float.random(in: -1...1, using: &g)
        }
        #expect(decode(voice).isEmpty)
        // Hiss with energy at 12-19 kHz: no symbol has two clean tones.
        let hiss = (0..<Int(rate * 5)).map { _ in 0.2 * Float.random(in: -1...1, using: &g) }
        #expect(decode(hiss).isEmpty)
    }

    @Test func singleToneIsNotASymbol() {
        let tone = (0..<Int(rate * 0.18)).map { Float(0.2 * sin(2 * .pi * 13_000 * Double($0) / rate)) }
        #expect(decode(silence(0.2) + tone + silence(0.2)).isEmpty)
    }

    @Test func truncatedMessagesAreRejectedAndBackToBackOnesBothDecode() {
        let two = Array(message("handleUp").prefix(Int(rate * 0.12)))
        #expect(decode(silence(0.2) + two + silence(0.3)).isEmpty)
        // No gap at all between two codes: each is delivered as soon as its third symbol is stable.
        let two2 = message("handleUp") + message("handleDown")
        #expect(decode(silence(0.2) + two2 + silence(0.3)).map(\.message) == [.gesture(.pttUp), .gesture(.pttDown)])
    }

    @Test func codebookIsConsistent() {
        for (name, symbols) in JackCodebook.messages {
            #expect(symbols.count == 3)
            #expect(symbols[0] != symbols[1])
            #expect(symbols[1] != symbols[2])
            #expect(JackMessage(name: name) != nil)
        }
        #expect(Set(JackCodebook.messages.values).count == JackCodebook.messages.count)
    }
}

@Suite struct TransportConfigTests {
    @Test func transportDefaultsToAutoAndDecodes() throws {
        #expect(AppConfig().device.transport == .auto)
        let jack = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"device":{"transport":"jack"}}"#.utf8))
        #expect(jack.device.transport == .jack)
        let bad = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"device":{"transport":"wifi"}}"#.utf8))
        #expect(bad.device.transport == .auto)
    }

    @Test func messagesMapToGestures() {
        #expect(JackMessage(name: "handleDown") == .gesture(.pttDown))
        #expect(JackMessage(name: "veryLongPress.orange") == .gesture(.veryLongPress(.orange)))
        #expect(JackMessage(name: "heartbeat") == .heartbeat)
        #expect(JackMessage(name: "tap.purple") == nil)
        #expect(JackMessage(name: "page.1") == .page(0))
        #expect(JackMessage(name: "page.4") == .page(3))
        #expect(JackMessage(name: "page.0") == nil)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
