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

    @Test func rightOptionEventsAreConsumedSoNoOtherAppSeesThem() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).intercept)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 500).intercept)
        // Left Option is not the handle: it passes through untouched.
        #expect(!mic.handle(keyCode: 58, isDown: true, at: 600).intercept)
    }

    @Test func rightCommandAloneDoesNothing() {
        var mic = KeyboardMic()
        let press = mic.handle(keyCode: 54, isDown: true, at: 0)
        #expect(press.gestures.isEmpty && !press.intercept)
        #expect(mic.tick(at: 1000).isEmpty)
        let release = mic.handle(keyCode: 54, isDown: false, at: 1100)
        #expect(release.gestures.isEmpty && !release.intercept)
        #expect(mic.tick(at: 5000).isEmpty)
        // Two quick taps are not a double tap either.
        _ = mic.handle(keyCode: 54, isDown: true, at: 6000)
        _ = mic.handle(keyCode: 54, isDown: false, at: 6050)
        _ = mic.handle(keyCode: 54, isDown: true, at: 6100)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 6150).gestures.isEmpty)
        #expect(mic.tick(at: 9000).isEmpty)
    }

    @Test func leftCommandNeverActs() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        #expect(mic.handle(keyCode: 55, isDown: true, at: 100).gestures.isEmpty)
        #expect(mic.handle(keyCode: 55, isDown: false, at: 1100).gestures.isEmpty)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 1200).gestures == [.pttUp])
    }

    @Test(arguments: [UInt16(0), 8, 9, 55, 56, 57, 58])
    func otherKeysPassThroughUntouched(keyCode: UInt16) {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        let press = mic.handle(keyCode: keyCode, isDown: true, at: 100)
        #expect(press.gestures.isEmpty && !press.intercept)
        let release = mic.handle(keyCode: keyCode, isDown: false, at: 150)
        #expect(release.gestures.isEmpty && !release.intercept)
    }

    // MARK: - Voice command: right ⌥ and right ⌘ held together

    @Test func holdingBothKeysStartsTheCommandAndReleasingEitherRunsIt() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).gestures == [.pttDown])
        #expect(mic.handle(keyCode: 54, isDown: true, at: 200).gestures == [.chordGrey])
        #expect(mic.tick(at: 1000).isEmpty)
        // Releasing Command first: the command runs, the later Option release adds nothing.
        #expect(mic.handle(keyCode: 54, isDown: false, at: 1100).gestures == [.pttUp])
        #expect(mic.handle(keyCode: 61, isDown: false, at: 1200).gestures.isEmpty)
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func releasingOptionFirstAlsoRunsTheCommand() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        #expect(mic.handle(keyCode: 54, isDown: true, at: 100).gestures == [.chordGrey])
        #expect(mic.handle(keyCode: 61, isDown: false, at: 800).gestures == [.pttUp])
        #expect(mic.handle(keyCode: 54, isDown: false, at: 900).gestures.isEmpty)
        #expect(mic.tick(at: 5000).isEmpty)
    }

    @Test func pressingCommandFirstThenOptionAlsoEntersTheCommand() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 54, isDown: true, at: 0).gestures.isEmpty)
        #expect(mic.handle(keyCode: 61, isDown: true, at: 100).gestures == [.pttDown, .chordGrey])
        #expect(mic.handle(keyCode: 54, isDown: false, at: 900).gestures == [.pttUp])
        #expect(mic.handle(keyCode: 61, isDown: false, at: 950).gestures.isEmpty)
    }

    @Test func releasingBothAtOnceRunsTheCommandOnce() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: true, at: 100)
        var gestures = mic.handle(keyCode: 54, isDown: false, at: 900).gestures
        gestures += mic.handle(keyCode: 61, isDown: false, at: 900).gestures
        #expect(gestures == [.pttUp])
    }

    @Test func commandWithoutATakeStartsNothingAndAnotherKeyDoesNotCancelTheCommand() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 61, isDown: true, at: 0)
        _ = mic.handle(keyCode: 54, isDown: true, at: 100)
        let shortcut = mic.handle(keyCode: 8, isDown: true, at: 200)
        #expect(shortcut.gestures.isEmpty && !shortcut.intercept)
        #expect(mic.handle(keyCode: 54, isDown: false, at: 300).gestures == [.pttUp])
    }

    @Test func aTakeWithoutCommandIsNotACommand() {
        var mic = KeyboardMic()
        #expect(mic.handle(keyCode: 61, isDown: true, at: 0).gestures == [.pttDown])
        #expect(mic.tick(at: 5000).isEmpty)
        #expect(mic.handle(keyCode: 61, isDown: false, at: 6000).gestures == [.pttUp])
    }

    @Test func eachTakeCanBeACommandAgain() {
        var mic = KeyboardMic()
        for start in [0.0, 10_000] {
            _ = mic.handle(keyCode: 61, isDown: true, at: start)
            #expect(mic.handle(keyCode: 54, isDown: true, at: start + 100).gestures == [.chordGrey])
            #expect(mic.handle(keyCode: 54, isDown: false, at: start + 900).gestures == [.pttUp])
            _ = mic.handle(keyCode: 61, isDown: false, at: start + 950)
        }
    }

    // MARK: - Arrows on right Command (orange, white, shake)

    private let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124, downArrow: UInt16 = 125, upArrow: UInt16 = 126

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
        // The take is a voice command: releasing Command runs it.
        #expect(mic.handle(keyCode: 54, isDown: false, at: 900).gestures == [.pttUp])
    }

    @Test func upArrowIsYesOnlyWhileAConfirmationWaits() {
        var mic = KeyboardMic()
        mic.confirmationPending = true
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        let press = mic.handle(keyCode: upArrow, isDown: true, at: 10)
        #expect(press.gestures == [.tap(.grey)] && press.intercept)
        let repeated = mic.handle(keyCode: upArrow, isDown: true, isRepeat: true, at: 60)
        #expect(repeated.gestures.isEmpty && repeated.intercept)
        mic.confirmationPending = false   // answered: the key-up is still swallowed
        let release = mic.handle(keyCode: upArrow, isDown: false, at: 100)
        #expect(release.gestures.isEmpty && release.intercept)
        #expect(mic.tick(at: 2000).isEmpty)
    }

    @Test func upArrowIsAnOrdinaryShortcutWithoutAConfirmation() {
        var mic = KeyboardMic()
        _ = mic.handle(keyCode: 54, isDown: true, at: 0)
        let press = mic.handle(keyCode: upArrow, isDown: true, at: 10)
        #expect(press.gestures.isEmpty && !press.intercept)
        #expect(!mic.handle(keyCode: upArrow, isDown: false, at: 50).intercept)
        #expect(mic.tick(at: 2000).isEmpty)
    }

    @Test func leftCommandUpArrowIsNeverYes() {
        var mic = KeyboardMic()
        mic.confirmationPending = true
        _ = mic.handle(keyCode: 55, isDown: true, at: 0)
        let press = mic.handle(keyCode: upArrow, isDown: true, at: 10)
        #expect(press.gestures.isEmpty && !press.intercept)
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
