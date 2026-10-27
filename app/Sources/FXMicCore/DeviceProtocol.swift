import Foundation

/// Wire protocol between the app and the RAM-only agent on the EP-2350 (TDD §3.1, ADR-001).
public enum DeviceProtocol {
    public static let vendorID = 0x2367
    public static let productID = 0x0620
    public static let portGlob = "/dev/cu.usbmodemEP"
    public static let supportedFirmware: Set<String> = ["1.0.9"]

    /// Installed with MicroPython paste mode (Ctrl-E … Ctrl-D). Events are printed with a
    /// leading newline because they can arrive while the REPL shows the `>>> ` prompt.
    public static let agentScript = """
    import time
    _fx = None
    try:
        import fxmic as _fx
        _fx.pause()
    except Exception:
        _fx = None
    try:
        _pc = python_callback
    except NameError:
        _pc = None
    _pt = False
    _lq = time.ticks_ms()
    def _tap(m):
        t = m >> 16
        v = m & 0xFFFF
        if t == 3 and _fx and time.ticks_diff(time.ticks_ms(), _lq) > 3000:
            _fx.resume()
            return
        if t in (1, 2):
            print('\\nE', t, v)
            if not _pt and v in (0, 1, 2):
                return
        elif t == 4:
            print('\\nE', t, v)
        if _pc:
            _pc(m)
    def _q():
        global _lq
        _lq = time.ticks_ms()
        print('Q', round(ui.handle(), 3), round(ui.shaker(), 3), ui.acc())
    def _L(m):
        for i in range(8):
            ui.led_level(i, 1.0 if (m >> i) & 1 else 0)
    ui.callback(_tap)
    ui.led_control(0)
    fx.load_preset(-1)
    print('AGENT_OK')
    """

    public static let pollCommand = "_q()"
    /// With the FXMic firmware installed the mic goes back to it (it plays the acoustic codes),
    /// otherwise to the factory logic. The agent also hands back by itself after 3 s without a poll.
    public static let restoreCommand =
        "_fx.resume() if _fx else (ui.callback(python_callback),ui.led_control(1),ui.leds(fx_pos,sam_pos),fx.load_preset(fx_pos));print('AGENT_OFF')"

    /// Only these command shapes may be sent to the device (TDD §4, allow-list).
    public static func ledsCommand(mode: Int, style: Int) -> String {
        "ui.leds(\(max(-1, min(3, mode))),\(max(0, min(3, style))))"
    }

    /// Manual LED mode (One-Pager 001): bit i of `mask` lights `ui.led_level` index i.
    public static func ledMaskCommand(_ mask: UInt8) -> String { "_L(\(mask))" }

    public static func passthroughCommand(_ on: Bool) -> String { on ? "_pt=True" : "_pt=False" }
}

public enum DeviceControl: Int, Sendable {
    case grey = 0, white = 1, orange = 2, handle = 4
}

/// One parsed line from the device.
public enum DeviceLine: Equatable, Sendable {
    case control(DeviceControl, active: Bool)
    case diskEjected
    case poll(handle: Double, shaker: Double, acc: [Int])
    case agentOK
    case agentOff
    case banner(firmware: String)
    case deviceError(String)
}

public enum DeviceLineParser {
    private static let eventRE = try! NSRegularExpression(pattern: #"(?:^|\s)E (\d+) (\d+)"#)
    private static let pollRE = try! NSRegularExpression(
        pattern: #"(?:^|\s)Q (-?[\d.]+(?:e-?\d+)?) (-?[\d.]+(?:e-?\d+)?) \[(-?\d+), (-?\d+), (-?\d+)\]"#)
    private static let bannerRE = try! NSRegularExpression(pattern: #"EP-2350 (\d+\.\d+\.\d+)"#)

    /// Parses a single line. Matches anywhere in the line: callback output can share a line
    /// with the REPL prompt (`>>> E 1 1`), found during spike M0-c.
    public static func parse(_ line: String) -> DeviceLine? {
        let range = NSRange(line.startIndex..., in: line)
        if let m = eventRE.firstMatch(in: line, range: range) {
            let type = Int(line[Range(m.range(at: 1), in: line)!])!
            let value = Int(line[Range(m.range(at: 2), in: line)!])!
            if type == 4 { return value == 1 ? .diskEjected : nil }
            guard type == 1 || type == 2, let control = DeviceControl(rawValue: value) else { return nil }
            // Type 1 = switch goes active. The handle switch has inverted polarity:
            // type 2 = handle pushed, type 1 = released (TEST_NOTES, run 01/03).
            let active = control == .handle ? type == 2 : type == 1
            return .control(control, active: active)
        }
        if let m = pollRE.firstMatch(in: line, range: range) {
            func str(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
            return .poll(handle: Double(str(1)) ?? 0, shaker: Double(str(2)) ?? 0,
                         acc: [Int(str(3)) ?? 0, Int(str(4)) ?? 0, Int(str(5)) ?? 0])
        }
        if line.contains("AGENT_OK") { return .agentOK }
        if line.contains("AGENT_OFF") { return .agentOff }
        if let m = bannerRE.firstMatch(in: line, range: range), line.contains("MICROPYTHON") {
            return .banner(firmware: String(line[Range(m.range(at: 1), in: line)!]))
        }
        if line.hasPrefix("Traceback") || line.contains("Error:") { return .deviceError(line) }
        return nil
    }
}

/// Splits a byte stream into `\r\n`-terminated lines.
public struct LineAccumulator {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        let separator = Data("\r\n".utf8)
        while let r = buffer.range(of: separator) {
            lines.append(String(decoding: buffer[buffer.startIndex..<r.lowerBound], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex..<r.upperBound)
        }
        return lines
    }

    /// Text received after the last line break (e.g. a `>>> ` prompt).
    public var pending: String { String(decoding: buffer, as: UTF8.self) }
}
