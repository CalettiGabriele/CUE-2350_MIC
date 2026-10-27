import Foundation
import os

public enum DeviceStatus: Equatable, Sendable {
    case searching
    case connecting
    case connected(firmware: String)
    /// Unknown firmware: events are read but factory button actions are left untouched.
    case readOnly(firmware: String)
    case busy
    case stopped
}

public protocol DeviceServiceDelegate: AnyObject {
    func device(_ service: DeviceService, didChange status: DeviceStatus)
    func device(_ service: DeviceService, didReceive line: DeviceLine, at timeMs: Double)
}

/// Owns the serial link and the RAM-only agent (TDD §3.1). Runs on its own thread and calls
/// the delegate on the main queue. Nothing is ever written to the device flash or disk.
public final class DeviceService {
    public weak var delegate: DeviceServiceDelegate?
    public var pollInterval: TimeInterval = 0.1
    /// The app's LED pages, handed to the FXMic firmware when the mic is given back.
    public var restoreSync: (channels: Int, position: Int, slot: Int)?

    private let log = Logger(subsystem: "com.fxmicbridge", category: "device")
    private let lock = NSLock()
    private var running = false
    private var outbox: [String] = []
    private var thread: Thread?
    private var port: SerialPort?

    public init() {}

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        running = true
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "FXMic.DeviceService"
        thread = t
        t.start()
    }

    /// Restores the factory callback/LEDs/preset and closes the port. Blocks up to ~2 s.
    public func stop() {
        lock.lock()
        running = false
        lock.unlock()
        // The run loop notices `running == false`, restores and exits.
        let deadline = Date().addingTimeInterval(3)
        while thread?.isFinished == false, Date() < deadline { usleep(20_000) }
    }

    /// Queues a command for the device. Only allow-listed command builders should be used.
    public func send(_ command: String) {
        lock.lock(); defer { lock.unlock() }
        // Nobody drains the queue while the serial line is not in use (jack mode).
        if running { outbox.append(command) }
    }

    public func setLEDs(mode: Int, style: Int) {
        send(DeviceProtocol.ledsCommand(mode: mode, style: style))
    }

    // MARK: - Thread

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    private func report(_ status: DeviceStatus) {
        log.info("status \(String(describing: status), privacy: .public)")
        DispatchQueue.main.async { self.delegate?.device(self, didChange: status) }
    }

    private func runLoop() {
        report(.searching)
        while isRunning {
            guard let path = SerialPort.findDevicePort() else {
                usleep(500_000)
                continue
            }
            let serial = SerialPort(path: path)
            do {
                try serial.open()
            } catch SerialError.open(_, let code) where code == EBUSY {
                report(.busy)
                sleep(2)
                continue
            } catch {
                usleep(500_000)
                continue
            }
            port = serial
            report(.connecting)
            do {
                try session(serial)
            } catch {
                log.info("disconnected: \(String(describing: error), privacy: .public)")
            }
            serial.close()
            port = nil
            if isRunning { report(.searching) }
        }
        report(.stopped)
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    /// Reads until `token` appears or the timeout elapses. Returns everything read.
    private func readUntil(_ serial: SerialPort, _ token: String, timeout: TimeInterval) throws -> String {
        var text = ""
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            text += String(decoding: try serial.read(), as: UTF8.self)
            if text.contains(token) { break }
        }
        return text
    }

    private func session(_ serial: SerialPort) throws {
        // Handshake: ask the firmware version explicitly (the boot banner is printed only once).
        try serial.write("\r")
        _ = try readUntil(serial, ">>> ", timeout: 2)
        try serial.write("import sys;print('MICROPYTHON', sys.implementation._machine)\r")
        let hello = try readUntil(serial, "\r\n>>> ", timeout: 2)
        var firmware = "unknown"
        for line in hello.components(separatedBy: "\r\n") {
            if case .banner(let fw)? = DeviceLineParser.parse(line) { firmware = fw }
        }
        let supported = DeviceProtocol.supportedFirmware.contains(firmware)

        // Install the agent with paste mode (idempotent: redefines `_tap`).
        try serial.write(Data([0x05]))
        usleep(100_000)
        try serial.write(DeviceProtocol.agentScript.replacingOccurrences(of: "\n", with: "\r"))
        try serial.write(Data([0x04]))
        let installed = try readUntil(serial, "AGENT_OK\r\n", timeout: 3)
        guard installed.contains("AGENT_OK\r\n") else {
            log.error("agent install failed: \(installed.suffix(200), privacy: .public)")
            throw SerialError.io(EIO)
        }
        if !supported { try serial.write(DeviceProtocol.passthroughCommand(true) + "\r") }
        report(supported ? .connected(firmware: firmware) : .readOnly(firmware: firmware))

        var lines = LineAccumulator()
        var pollSentAt: Double?
        var nextPoll = now()
        while isRunning {
            lock.lock()
            let commands = outbox
            outbox.removeAll()
            lock.unlock()
            for command in commands { try serial.write(command + "\r") }

            let t = now()
            if pollSentAt == nil, t >= nextPoll {
                try serial.write(DeviceProtocol.pollCommand + "\r")
                pollSentAt = t
                nextPoll = t + pollInterval * 1000
            } else if let sent = pollSentAt, t - sent > 1000 {
                pollSentAt = nil   // lost poll; try again
            }

            for line in lines.append(try serial.read()) {
                guard let parsed = DeviceLineParser.parse(line) else { continue }
                if case .poll = parsed { pollSentAt = nil }
                let at = now()
                DispatchQueue.main.async { self.delegate?.device(self, didReceive: parsed, at: at) }
            }
        }
        // Stopping: restore the factory behaviour before releasing the port.
        try serial.write(DeviceProtocol.restoreCommand(sync: restoreSync) + "\r")
        let restored = try readUntil(serial, "AGENT_OFF\r\n", timeout: 2)
        log.info("restore \(restored.contains("AGENT_OFF") ? "OK" : "not confirmed", privacy: .public)")
    }
}
