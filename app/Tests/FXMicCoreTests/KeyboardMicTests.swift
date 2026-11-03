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
        #expect(release.intercept)
    }

    @Test func rightOptionEventsAreConsumedSoNoOtherAppSeesThem() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).intercept)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 500).intercept)
        // Left Option is not the handle: it passes through untouched.
        #expect(!mic.handle(keyCode: 58, isDown: true, at: 600).intercept)
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

    @Test(arguments: [UInt16(0), 8, 9, 55, 56, 57, 58, 61])
    func anotherKeyCancelsEvenAfterTheLongPressThreshold(keyCode: UInt16) {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        #expect(mic.tick(at: 650).isEmpty)
        // Right Option is the handle and always consumed; every other key passes through.
        let consumed = keyCode == 61
        let shortcut = mic.handle(keyCode: keyCode, isDown: true, at: 700)
        #expect(shortcut.intercept == consumed)
        #expect(mic.handle(keyCode: keyCode, isDown: false, at: 750).intercept == consumed)
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

    // MARK: - Arrows on right Command (orange, white, shake)

    private let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124, downArrow: UInt16 = 125

    @Test func rightCommandLeftIsOrangeAndIntercepted() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        let press = mic.handle(keyCode: leftArrow, isDown: true, at: 10)
        #expect(press.gestures.isEmpty && press.intercept)
        let release = mic.handle(keyCode: leftArrow, isDown: false, at: 100)
        #expect(release.gestures.isEmpty && release.intercept)
        #expect(mic.tick(at: 400).isEmpty)
        #expect(mic.tick(at: 401) == [.tap(.orange)])
        #expect(mic.handle(keyCode: 54, isDown: false, at: 500).gestures.isEmpty)
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func rightCommandRightIsWhite() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: rightArrow, isDown: true, at: 10)
        _ = mic.handle(keyCode: rightArrow, isDown: false, at: 100)
        #expect(mic.tick(at: 401) == [.tap(.white)])
    }

    @Test(arguments: [(UInt16(123), MicButton.orange), (UInt16(124), MicButton.white)])
    func arrowDoubleTap(keyCode: UInt16, button: MicButton) {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: keyCode, isDown: true, at: 10)
        _ = mic.handle(keyCode: keyCode, isDown: false, at: 100)
        _ = mic.handle(keyCode: keyCode, isDown: true, at: 200)
        #expect(mic.handle(keyCode: keyCode, isDown: false, at: 300).gestures == [.doubleTap(button)])
        #expect(mic.tick(at: 2000).isEmpty)
    }

    @Test func orangeLongAndVeryLongPress() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: leftArrow, isDown: true, at: 0)
        #expect(mic.tick(at: 599).isEmpty)
        #expect(mic.tick(at: 600) == [.longPress(.orange)])
        #expect(mic.tick(at: 2999).isEmpty)
        #expect(mic.tick(at: 3000) == [.veryLongPress(.orange)])
        #expect(mic.handle(keyCode: leftArrow, isDown: false, at: 3100).gestures.isEmpty)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 3200).gestures.isEmpty)
        #expect(mic.tick(at: 9000).isEmpty)
    }

    @Test func whiteLongPress() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: rightArrow, isDown: true, at: 0)
        #expect(mic.tick(at: 600) == [.longPress(.white)])
    }

    @Test func leftCommandAndPlainArrowsAreNeverIntercepted() {
        var mic = KeyboardMic()
        for keyCode in [leftArrow, rightArrow, downArrow] {
            #expect(!mic.handle(keyCode: keyCode, isDown: true, at: 0).intercept)
            #expect(!mic.handle(keyCode: keyCode, isDown: false, at: 10).intercept)
        }
        _ = mic.handle(keyCode: 55, isDown: true, at: 100)
        for keyCode in [leftArrow, rightArrow, downArrow] {
            let press = mic.handle(keyCode: keyCode, isDown: true, at: 120)
            #expect(!press.intercept && press.gestures.isEmpty)
            #expect(!mic.handle(keyCode: keyCode, isDown: false, at: 130).intercept)
        }
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func arrowKeyUpAfterCommandReleaseIsStillIntercepted() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: leftArrow, isDown: true, at: 10)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 50).gestures.isEmpty)
        #expect(mic.handle(keyCode: leftArrow, isDown: false, at: 100).intercept)
        #expect(mic.tick(at: 401) == [.tap(.orange)])
        // Back to normal: a plain arrow passes through again.
        #expect(!mic.handle(keyCode: leftArrow, isDown: true, at: 600).intercept)
    }

    @Test func arrowAutoRepeatIsSwallowedWithoutGestures() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: leftArrow, isDown: true, at: 10)
        let repeated = mic.handle(keyCode: leftArrow, isDown: true, isRepeat: true, at: 60)
        #expect(repeated.gestures.isEmpty && repeated.intercept)
        let other = mic.handle(keyCode: rightArrow, isDown: true, at: 70)
        #expect(other.gestures.isEmpty && other.intercept)
        _ = mic.handle(keyCode: rightArrow, isDown: false, at: 80)
        _ = mic.handle(keyCode: leftArrow, isDown: false, at: 100)
        #expect(mic.tick(at: 401) == [.tap(.orange)])
    }

    @Test func arrowsWhileTalkingDoNotSelect() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: true, at: 100)
        let press = mic.handle(keyCode: leftArrow, isDown: true, at: 120)
        #expect(press.intercept)
        _ = mic.handle(keyCode: leftArrow, isDown: false, at: 200)
        #expect(mic.tick(at: 800).isEmpty)
        // The combination also cancelled the candidate chord.
        #expect(mic.handle(keyCode: 54, isDown: false, at: 900).gestures.isEmpty)
    }

    @Test func shortDownArrowIsAShakeOnRelease() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        let press = mic.handle(keyCode: downArrow, isDown: true, at: 10)
        #expect(press.gestures.isEmpty && press.intercept)
        #expect(mic.tick(at: 1500).isEmpty)
        let release = mic.handle(keyCode: downArrow, isDown: false, at: 1900)
        #expect(release.gestures == [.shake] && release.intercept)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 2000).gestures.isEmpty)
    }

    @Test func heldDownArrowIsAShakeHoldOnce() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: downArrow, isDown: true, at: 0)
        #expect(mic.tick(at: 1999).isEmpty)
        #expect(mic.tick(at: 2000) == [.shakeHold])
        #expect(mic.tick(at: 2500).isEmpty)
        #expect(mic.handle(keyCode: downArrow, isDown: true, isRepeat: true, at: 2600).gestures.isEmpty)
        #expect(mic.handle(keyCode: downArrow, isDown: false, at: 3000).gestures.isEmpty)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 3100).gestures.isEmpty)
        #expect(mic.tick(at: 9000).isEmpty)
    }

    @Test func shakeHoldUsesTheConfiguredThreshold() {
        var settings = GestureSettings()
        settings.shakeHoldMs = 500
        var mic = KeyboardMic(settings: settings)
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        _ = mic.handle(keyCode: downArrow, isDown: true, at: 0)
        #expect(mic.tick(at: 499).isEmpty)
        #expect(mic.tick(at: 500) == [.shakeHold])
    }
}
