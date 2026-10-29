import Testing
@testable import FXMicCore

@Suite struct GestureRouterTests {
    @Test func ignoredJackHandleCannotTruncateKeyboardAudio() {
        var router = GestureRouter()
        #expect(router.route(.pttDown, from: .keyboard) == .startRecording(fromSample: nil))
        #expect(router.route(.pttDown, from: .jack, captureSample: 100) == nil)
        #expect(router.route(.pttUp, from: .jack, captureSample: 200) == nil)
        #expect(router.route(.pttUp, from: .keyboard) == .stopRecording(atSample: nil))
        #expect(router.route(.pttDown, from: .jack, captureSample: 500) == .startRecording(fromSample: 500))
        #expect(router.route(.pttUp, from: .jack, captureSample: 900) == .stopRecording(atSample: 900))
    }

    @Test func confirmationConsumesInputBeforeRecordingOrProfileActions() {
        var router = GestureRouter()
        #expect(router.route(.pttDown, from: .jack, captureSample: 100,
                             awaitingConfirmation: true) == nil)
        #expect(router.route(.handleDoubleClick, from: .keyboard,
                             awaitingConfirmation: true) == nil)
        #expect(router.route(.tap(.grey), from: .keyboard,
                             awaitingConfirmation: true) == .confirm(true))
        #expect(router.route(.longPress(.grey), from: .usb,
                             awaitingConfirmation: true) == .confirm(false))
        #expect(router.route(.shake, from: .jack,
                             awaitingConfirmation: true) == .confirm(false))
        #expect(router.route(.pttDown, from: .keyboard) == .startRecording(fromSample: nil))
        #expect(router.route(.pttUp, from: .jack, captureSample: 200) == nil)
        #expect(router.route(.pttUp, from: .keyboard) == .stopRecording(atSample: nil))
    }

    @Test func releaseDuringConfirmationDoesNotStrandHandleOwnership() {
        var router = GestureRouter()
        _ = router.route(.pttDown, from: .keyboard)
        #expect(router.route(.pttUp, from: .keyboard, awaitingConfirmation: true) == nil)
        #expect(router.route(.pttDown, from: .usb) == .startRecording(fromSample: nil))
        #expect(router.route(.pttUp, from: .usb) == .stopRecording(atSample: nil))
    }

    @Test(arguments: [GestureSource.usb, .jack, .keyboard])
    func onlyOriginatingSourceCanReleaseTheHandle(owner: GestureSource) {
        var router = GestureRouter()
        let other: GestureSource = owner == .keyboard ? .usb : .keyboard
        #expect(router.route(.pttDown, from: owner) == .startRecording(fromSample: nil))
        #expect(router.route(.pttDown, from: other) == nil)
        #expect(router.route(.pttUp, from: other) == nil)
        #expect(router.route(.pttUp, from: owner) == .stopRecording(atSample: nil))
        #expect(router.route(.pttDown, from: other) == .startRecording(fromSample: nil))
        #expect(router.route(.pttUp, from: other) == .stopRecording(atSample: nil))
    }

    @Test func ignoredHandleCannotInsertANewLine() {
        var router = GestureRouter()
        _ = router.route(.pttDown, from: .usb)
        _ = router.route(.pttDown, from: .keyboard)
        #expect(router.route(.pttUp, from: .keyboard) == nil)
        #expect(router.route(.handleDoubleClick, from: .keyboard) == nil)
        _ = router.route(.pttUp, from: .usb)
        _ = router.route(.pttDown, from: .usb)
        _ = router.route(.pttUp, from: .usb)
        #expect(router.route(.handleDoubleClick, from: .usb) == .perform(.handleDoubleClick))
        #expect(router.route(.tap(.orange), from: .keyboard) == .perform(.tap(.orange)))
    }

    @Test func bothClicksMustHaveOwnedTheHandle() {
        var router = GestureRouter()
        _ = router.route(.pttDown, from: .usb)
        _ = router.route(.pttDown, from: .keyboard)
        _ = router.route(.pttUp, from: .keyboard)
        _ = router.route(.pttUp, from: .usb)
        _ = router.route(.pttDown, from: .keyboard)
        _ = router.route(.pttUp, from: .keyboard)
        #expect(router.route(.handleDoubleClick, from: .keyboard) == nil)
    }

    @Test(arguments: [GestureSource.usb, .jack])
    func disconnectOnlyCancelsTheOwningSource(source: GestureSource) {
        var router = GestureRouter()
        _ = router.route(.pttDown, from: .keyboard)
        #expect(router.disconnect(source) == false)
        _ = router.route(.pttUp, from: .keyboard)
        _ = router.route(.pttDown, from: source)
        #expect(router.disconnect(source) == true)
        #expect(router.route(.pttUp, from: source) == nil)
        #expect(router.route(.pttDown, from: .keyboard) == .startRecording(fromSample: nil))
        #expect(router.route(.pttUp, from: .keyboard) == .stopRecording(atSample: nil))
        #expect(router.route(.handleDoubleClick, from: .keyboard) == nil)
    }
}
