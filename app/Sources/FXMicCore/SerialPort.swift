import Darwin
import Foundation

public enum SerialError: Error {
    case open(String, Int32)
    case io(Int32)
}

/// Minimal blocking POSIX serial port (USB CDC: baud rate is ignored by the device).
public final class SerialPort {
    public let path: String
    private var fd: Int32 = -1

    public init(path: String) {
        self.path = path
    }

    public static func findDevicePort() -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let prefix = String(DeviceProtocol.portGlob.dropFirst("/dev/".count))
        return names.filter { $0.hasPrefix(prefix) }.sorted().first.map { "/dev/" + $0 }
    }

    public func open() throws {
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.open(path, errno) }
        // Exclusive access: the agent cannot share the REPL with another program.
        _ = ioctl(fd, TIOCEXCL)
        var tio = termios()
        tcgetattr(fd, &tio)
        cfmakeraw(&tio)
        cfsetspeed(&tio, speed_t(B115200))
        tio.c_cflag |= tcflag_t(CLOCAL | CREAD)
        // Blocking reads that return after 100 ms without data.
        withUnsafeMutableBytes(of: &tio.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 1
        }
        tcsetattr(fd, TCSANOW, &tio)
        _ = fcntl(fd, F_SETFL, 0)
    }

    public var isOpen: Bool { fd >= 0 }

    public func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    /// Returns available bytes (possibly empty after the 100 ms timeout).
    public func read(max: Int = 4096) throws -> Data {
        var buf = [UInt8](repeating: 0, count: max)
        let n = Darwin.read(fd, &buf, max)
        if n < 0 {
            if errno == EAGAIN || errno == EINTR { return Data() }
            throw SerialError.io(errno)
        }
        return Data(buf[0..<n])
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw SerialError.io(errno)
                }
                offset += n
            }
        }
    }

    public func write(_ string: String) throws { try write(Data(string.utf8)) }
}
