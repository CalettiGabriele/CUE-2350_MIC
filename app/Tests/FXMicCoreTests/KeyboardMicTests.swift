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
}
