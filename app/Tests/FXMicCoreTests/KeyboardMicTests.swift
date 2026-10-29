import Testing
@testable import FXMicCore

@Suite struct KeyboardMicTests {
    @Test func doubleClickEndsTheShortTakeBeforeNewLine() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).gestures == [.pttDown])
        #expect(mic.handle(keyCode: 61, isDown: false, at: 100).gestures == [.pttUp])
        #expect(mic.handle(keyCode: 61, isDown: true, at: 250).gestures == [.pttDown])
        let release = mic.handle(keyCode: 61, isDown: false, at: 350)
        #expect(release.gestures == [.pttUp, .handleDoubleClick])
        #expect(!release.intercept)
    }

    @Test func repeatCannotStartAHandlePress() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, isRepeat: true, at: 0).gestures.isEmpty)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 100).gestures.isEmpty)
        #expect(mic.handle(keyCode: 58, isDown: true, at: 200).gestures.isEmpty)
    }

    @Test func customClickTimingAndDuplicatePresses() {
        var settings = GestureSettings()
        settings.handleClickMaxMs = 50
        settings.handleDoubleClickGapMs = 80
        var mic = KeyboardMic(settings: settings)
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).gestures == [.pttDown])
        #expect(mic.handle(keyCode: 61, isDown: true, at: 10).gestures.isEmpty)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 40).gestures == [.pttUp])
        _ = mic.handle(keyCode: 61, isDown: true, at: 120)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 160).gestures == [.pttUp, .handleDoubleClick])
        _ = mic.handle(keyCode: 61, isDown: true, at: 200)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 300).gestures == [.pttUp])
    }

    @Test func rightCommandTapUsesTheGreyDoubleTapWindow() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 54, isDown: true, at: 0).gestures.isEmpty)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 100).gestures.isEmpty)
        #expect(mic.tick(at: 400).isEmpty)
        #expect(mic.tick(at: 401) == [.tap(.grey)])
        #expect(mic.tick(at: 1000).isEmpty)
    }

    @Test(arguments: [UInt16(0), 8, 9, 55, 56, 58, 61])
    func anotherKeyCancelsEvenAfterTheLongPressThreshold(keyCode: UInt16) {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        #expect(mic.tick(at: 650).isEmpty)
        let shortcut = mic.handle(keyCode: keyCode, isDown: true, at: 700)
        #expect(!shortcut.intercept)
        #expect(!mic.handle(keyCode: keyCode, isDown: false, at: 750).intercept)
        let release = mic.handle(keyCode: 54, isDown: false, at: 800)
        #expect(release.gestures.isEmpty)
        #expect(!release.intercept)
        #expect(mic.tick(at: 5000).isEmpty)
        _ = mic.handle(keyCode: 54, isDown: true, at: 5100)
        _ = mic.handle(keyCode: 54, isDown: false, at: 5200)
        #expect(mic.tick(at: 5501) == [.tap(.grey)])
    }

    @Test func rightCommandDoubleTapDoesNotAlsoSendReturn() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: false, at: 100)
        _ = mic.handle(keyCode: 54, isDown: true, at: 200)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 300).gestures == [.doubleTap(.grey)])
        #expect(mic.tick(at: 1000).isEmpty)
    }

    @Test(arguments: [(450.0, [Gesture.tap(.grey)]), (451.0, []),
                      (599.0, []), (600.0, [.longPress(.grey)])])
    func commandDurationUsesMicThresholds(duration: Double, expected: [Gesture]) {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        #expect(mic.tick(at: duration).isEmpty)
        var gestures = mic.handle(keyCode: 54, isDown: false, at: duration).gestures
        gestures += mic.tick(at: duration + 301)
        #expect(gestures == expected)
    }

    @Test func duplicateCommandEventsDoNotRestartOrCancelALongPress() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: true, at: 200)
        _ = mic.handle(keyCode: 54, isDown: true, isRepeat: true, at: 300)
        #expect(mic.tick(at: 650).isEmpty)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 700).gestures == [.longPress(.grey)])
        #expect(mic.handle(keyCode: 54, isDown: false, at: 710).gestures.isEmpty)
    }

    @Test func commandChordCommitsBeforeTheHandleStops() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).gestures == [.pttDown])
        #expect(mic.handle(keyCode: 54, isDown: true, at: 200).gestures.isEmpty)
        #expect(mic.tick(at: 1000).isEmpty)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 1100).gestures == [.chordGrey])
        #expect(mic.handle(keyCode: 61, isDown: false, at: 1200).gestures == [.pttUp])
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func releasingTheHandleFirstCancelsTheCandidateChord() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: true, at: 100)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 800).gestures == [.pttUp])
        #expect(mic.handle(keyCode: 54, isDown: false, at: 900).gestures.isEmpty)
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func leftCommandNeverActsAsGrey() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 55, isDown: true, at: 0).gestures.isEmpty)
        #expect(mic.tick(at: 1000).isEmpty)
        #expect(mic.handle(keyCode: 55, isDown: false, at: 1100).gestures.isEmpty)
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func anotherKeyCancelsAChordWithoutStoppingDictation() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: true, at: 100)
        #expect(mic.tick(at: 800).isEmpty)
        let shortcut = mic.handle(keyCode: 8, isDown: true, at: 900)
        #expect(shortcut.gestures.isEmpty)
        #expect(!shortcut.intercept)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 1000).gestures.isEmpty)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 1100).gestures == [.pttUp])
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func customGreyTimingAppliesToTheKeyboard() {
        var settings = GestureSettings()
        settings.tapMaxMs = 50
        settings.doubleTapMs = 80
        settings.longPressMs = 100
        var mic = KeyboardMic(settings: settings)
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: false, at: 40)
        #expect(mic.tick(at: 120).isEmpty)
        #expect(mic.tick(at: 121) == [.tap(.grey)])
        _ = mic.handle(keyCode: 54, isDown: true, at: 200)
        #expect(mic.tick(at: 300).isEmpty)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 300).gestures == [.longPress(.grey)])
    }
}
