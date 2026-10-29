import Testing
@testable import FXMicCore

@Suite struct HandleArbiterTests {
    @Test(arguments: [GestureSource.usb, .jack, .keyboard])
    func onlyOriginatingSourceCanReleaseTheHandle(owner: GestureSource) {
        var handle = HandleArbiter()
        let other: GestureSource = owner == .keyboard ? .usb : .keyboard
        #expect(handle.accept(.pttDown, from: owner) == true)
        #expect(handle.accept(.pttDown, from: other) == false)
        #expect(handle.accept(.pttUp, from: other) == false)
        #expect(handle.accept(.pttUp, from: owner) == true)
        #expect(handle.accept(.pttDown, from: other) == true)
        #expect(handle.accept(.pttUp, from: other) == true)
    }

    @Test func ignoredHandleCannotInsertANewLine() {
        var handle = HandleArbiter()
        _ = handle.accept(.pttDown, from: .usb)
        _ = handle.accept(.pttDown, from: .keyboard)
        #expect(handle.accept(.pttUp, from: .keyboard) == false)
        #expect(handle.accept(.handleDoubleClick, from: .keyboard) == false)
        #expect(handle.accept(.pttUp, from: .usb) == true)
        #expect(handle.accept(.pttDown, from: .usb) == true)
        #expect(handle.accept(.pttUp, from: .usb) == true)
        #expect(handle.accept(.handleDoubleClick, from: .usb) == true)
        #expect(handle.accept(.tap(.orange), from: .keyboard) == true)
    }

    @Test func bothClicksMustHaveOwnedTheHandle() {
        var handle = HandleArbiter()
        _ = handle.accept(.pttDown, from: .usb)
        _ = handle.accept(.pttDown, from: .keyboard)
        _ = handle.accept(.pttUp, from: .keyboard)
        _ = handle.accept(.pttUp, from: .usb)
        _ = handle.accept(.pttDown, from: .keyboard)
        _ = handle.accept(.pttUp, from: .keyboard)
        #expect(handle.accept(.handleDoubleClick, from: .keyboard) == false)
    }

    @Test(arguments: [GestureSource.usb, .jack])
    func disconnectOnlyCancelsTheOwningSource(source: GestureSource) {
        var handle = HandleArbiter()
        _ = handle.accept(.pttDown, from: .keyboard)
        #expect(handle.disconnect(source) == false)
        #expect(handle.accept(.pttUp, from: .keyboard) == true)
        _ = handle.accept(.pttDown, from: source)
        #expect(handle.disconnect(source) == true)
        #expect(handle.accept(.pttUp, from: source) == false)
        #expect(handle.accept(.pttDown, from: .keyboard) == true)
        #expect(handle.accept(.pttUp, from: .keyboard) == true)
        #expect(handle.accept(.handleDoubleClick, from: .keyboard) == false)
    }
}
