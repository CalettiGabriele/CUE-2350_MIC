import Foundation
import Testing
@testable import FXMicCore

@Suite struct DeviceLineParserTests {
    @Test func buttonEventsMapToControls() {
        #expect(DeviceLineParser.parse("E 1 2") == .control(.orange, active: true))
        #expect(DeviceLineParser.parse("E 2 2") == .control(.orange, active: false))
        #expect(DeviceLineParser.parse("E 1 1") == .control(.white, active: true))
        #expect(DeviceLineParser.parse("E 1 0") == .control(.grey, active: true))
    }

    @Test func handlePolarityIsInverted() {
        #expect(DeviceLineParser.parse("E 2 4") == .control(.handle, active: true))
        #expect(DeviceLineParser.parse("E 1 4") == .control(.handle, active: false))
    }

    @Test func eventOnPromptLineIsStillParsed() {
        // Regression from spike M0-c: callback output shared a line with the REPL prompt.
        #expect(DeviceLineParser.parse(">>> E 1 1") == .control(.white, active: true))
    }

    @Test func pollLine() {
        #expect(DeviceLineParser.parse("Q 0.52 0.031 [2400, 544, 16448]")
                == .poll(handle: 0.52, shaker: 0.031, acc: [2400, 544, 16448]))
        #expect(DeviceLineParser.parse("Q 0.0 4.92754e-05 [-10208, -17504, -3248]")
                == .poll(handle: 0, shaker: 4.92754e-05, acc: [-10208, -17504, -3248]))
    }

    @Test func bannerAndMarkers() {
        #expect(DeviceLineParser.parse("MICROPYTHON 1.25; EP-2350 1.0.9") == .banner(firmware: "1.0.9"))
        #expect(DeviceLineParser.parse("AGENT_OK") == .agentOK)
        #expect(DeviceLineParser.parse("AGENT_OFF") == .agentOff)
        #expect(DeviceLineParser.parse("E 4 1") == .diskEjected)
        #expect(DeviceLineParser.parse(">>> _q()") == nil)
    }

    @Test func lineAccumulatorSplitsOnCRLF() {
        var acc = LineAccumulator()
        #expect(acc.append(Data("E 1 2\r\nQ 0".utf8)) == ["E 1 2"])
        #expect(acc.append(Data(".1 0.0 [1, 2, 3]\r\n>>> ".utf8)) == ["Q 0.1 0.0 [1, 2, 3]"])
        #expect(acc.pending == ">>> ")
    }

    @Test func ledsCommandIsClamped() {
        #expect(DeviceProtocol.ledsCommand(mode: -5, style: 9) == "ui.leds(-1,3)")
    }
}

@Suite struct GestureRecognizerTests {
    @Test func singleTapResolvesAfterDoubleTapWindow() {
        var g = GestureRecognizer()
        #expect(g.handle(.orange, active: true, at: 0).isEmpty)
        #expect(g.handle(.orange, active: false, at: 100).isEmpty)
        #expect(g.tick(at: 300).isEmpty)
        #expect(g.tick(at: 401) == [.tap(.orange)])
        #expect(g.tick(at: 900).isEmpty)
    }

    @Test func doubleTap() {
        var g = GestureRecognizer()
        _ = g.handle(.grey, active: true, at: 0)
        _ = g.handle(.grey, active: false, at: 80)
        _ = g.handle(.grey, active: true, at: 200)
        #expect(g.handle(.grey, active: false, at: 280) == [.doubleTap(.grey)])
        #expect(g.tick(at: 1000).isEmpty)
    }

    @Test func longPressFiresWhileHeldAndSuppressesTap() {
        var g = GestureRecognizer()
        _ = g.handle(.white, active: true, at: 0)
        #expect(g.tick(at: 599).isEmpty)
        #expect(g.tick(at: 600) == [.longPress(.white)])
        #expect(g.handle(.white, active: false, at: 1200).isEmpty)
        #expect(g.tick(at: 2000).isEmpty)
    }

    @Test func handleProducesPushToTalk() {
        var g = GestureRecognizer()
        #expect(g.handle(.handle, active: true, at: 0) == [.pttDown])
        #expect(g.handle(.handle, active: true, at: 10).isEmpty)
        #expect(g.handle(.handle, active: false, at: 900) == [.pttUp])
    }

    @Test func greyDuringPushToTalkIsChord() {
        var g = GestureRecognizer()
        _ = g.handle(.handle, active: true, at: 0)
        #expect(g.handle(.grey, active: true, at: 100) == [.chordGrey])
        #expect(g.tick(at: 1000).isEmpty)            // no long press for a chord
        #expect(g.handle(.grey, active: false, at: 1100).isEmpty)
    }

    @Test func modeButtonsIgnoredWhileTalking() {
        var g = GestureRecognizer()
        _ = g.handle(.handle, active: true, at: 0)
        _ = g.handle(.orange, active: true, at: 100)
        _ = g.handle(.orange, active: false, at: 200)
        #expect(g.tick(at: 1000).isEmpty)
    }

    @Test func handleDoubleClickAfterTwoShortPresses() {
        var g = GestureRecognizer()
        #expect(g.handle(.handle, active: true, at: 0) == [.pttDown])
        #expect(g.handle(.handle, active: false, at: 150) == [.pttUp])
        #expect(g.handle(.handle, active: true, at: 400) == [.pttDown])
        #expect(g.handle(.handle, active: false, at: 550) == [.pttUp, .handleDoubleClick])
        // A third quick click starts a new pair rather than firing again.
        _ = g.handle(.handle, active: true, at: 700)
        #expect(g.handle(.handle, active: false, at: 800) == [.pttUp])
    }

    @Test func handleDoubleClickNeedsShortPressesAndSmallGap() {
        var g = GestureRecognizer()
        _ = g.handle(.handle, active: true, at: 0)
        _ = g.handle(.handle, active: false, at: 150)
        _ = g.handle(.handle, active: true, at: 700)                 // gap 550 ms > 400
        #expect(g.handle(.handle, active: false, at: 800) == [.pttUp])
        _ = g.handle(.handle, active: true, at: 1000)
        #expect(g.handle(.handle, active: false, at: 2500) == [.pttUp])  // dictation, not a click
    }

    @Test func sustainedStrongShakeFiresOnceAfterTwoSeconds() {
        var g = GestureRecognizer()
        var fired: [Gesture] = []
        var t = 0.0
        while t <= 2500 {
            // A dip below the threshold shorter than the tolerance does not reset the hold.
            let value = (t == 1000) ? 0.2 : 0.8
            fired += g.poll(shaker: value, at: t).filter { $0 == .shakeHold }
            t += 100
        }
        #expect(fired == [.shakeHold])
    }

    @Test func shortStrongShakeDoesNotClear() {
        var g = GestureRecognizer()
        var gestures: [Gesture] = []
        for t in stride(from: 0.0, through: 1500, by: 100) { gestures += g.poll(shaker: 0.8, at: t) }
        for t in stride(from: 1600.0, through: 2600, by: 100) { gestures += g.poll(shaker: 0.0, at: t) }
        for t in stride(from: 2700.0, through: 3800, by: 100) { gestures += g.poll(shaker: 0.8, at: t) }
        #expect(!gestures.contains(.shakeHold))
    }

    @Test func shakeNeedsConsecutiveReadingsAndCooldown() {
        var g = GestureRecognizer()
        #expect(g.poll(shaker: 0.7, at: 0).isEmpty)
        #expect(g.poll(shaker: 0.8, at: 100) == [.shake])
        #expect(g.poll(shaker: 0.8, at: 200).isEmpty)
        #expect(g.poll(shaker: 0.8, at: 300).isEmpty)   // cooldown
        #expect(g.poll(shaker: 0.3, at: 400).isEmpty)
        #expect(g.poll(shaker: 0.9, at: 1200).isEmpty)
        #expect(g.poll(shaker: 0.9, at: 1300) == [.shake])
    }
}

@Suite struct DictationStateMachineTests {
    @Test func rawHappyPath() {
        var m = DictationStateMachine()
        #expect(m.send(.pttDown(at: 0)) == .startRecording)
        #expect(m.send(.pttUp(at: 2000)) == .stopRecordingAndTranscribe)
        #expect(m.send(.transcribed(text: "ciao", usesLLM: false)) == .inject)
        #expect(m.send(.injected) == .none)
        #expect(m.state == .idle)
    }

    @Test func tooShortIsDiscarded() {
        var m = DictationStateMachine()
        _ = m.send(.pttDown(at: 0))
        #expect(m.send(.pttUp(at: 100)) == .discardRecording(reason: "too short"))
        #expect(m.state == .idle)
    }

    @Test func busyWhileProcessing() {
        var m = DictationStateMachine()
        _ = m.send(.pttDown(at: 0))
        _ = m.send(.pttUp(at: 1000))
        #expect(m.send(.pttDown(at: 1100)) == .busy)
        #expect(m.state == .transcribing)
    }

    @Test func emptyTranscriptAndCancel() {
        var m = DictationStateMachine()
        _ = m.send(.pttDown(at: 0))
        _ = m.send(.pttUp(at: 1000))
        #expect(m.send(.transcribed(text: "  ", usesLLM: false)) == .discardRecording(reason: "no speech"))
        _ = m.send(.pttDown(at: 2000))
        #expect(m.send(.cancel) == .discardRecording(reason: "cancelled"))
        #expect(m.state == .idle)
    }

    @Test func llmPath() {
        var m = DictationStateMachine()
        _ = m.send(.pttDown(at: 0))
        _ = m.send(.pttUp(at: 1000))
        #expect(m.send(.transcribed(text: "ciao", usesLLM: true)) == .runPostProcessing)
        #expect(m.send(.postProcessed) == .inject)
    }
}
