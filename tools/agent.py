"""Spike M0-c: prototype of the RAM-only device agent (see docs/adr/adr-001).

Installs the agent from the TDD (section 3.1), polls `_q()` at 10 Hz, logs
events and stats, survives unplug/power-cycle by reconnecting and reinstalling,
and restores the factory callback on exit (Ctrl-C or duration elapsed).

usage: agent.py [DURATION_SECONDS] [LOGFILE]
"""
import glob
import re
import sys
import time

import serial

AGENT = """\
_pt = False
def _tap(m):
    t = m >> 16
    v = m & 0xFFFF
    if t in (1, 2):
        print('\\nE', t, v)
        if not _pt and v in (0, 1, 2):
            return
    elif t == 4:
        print('\\nE', t, v)
    python_callback(m)
def _q(): print('Q', round(ui.handle(), 3), round(ui.shaker(), 3), ui.acc())
ui.callback(_tap)
fx.load_preset(-1)
print('AGENT_OK')
"""
RESTORE = "ui.callback(python_callback);ui.leds(fx_pos,sam_pos);fx.load_preset(fx_pos);print('AGENT_OFF')"
POLL_S = 0.1
# Callback output can land on the same line as the REPL prompt (">>> E 1 2"), so match anywhere.
EVENT_RE = re.compile(r"(?:^|\s)E (\d+) (\d+)")
POLL_RE = re.compile(r"(?:^|\s)Q [-\d.]+ ")


class Stats:
    def __init__(self):
        self.polls = self.poll_misses = self.events = self.reconnects = self.installs = 0
        self.max_poll_ms = 0.0
        self.poll_ms_sum = 0.0


def find_port():
    ports = glob.glob("/dev/cu.usbmodemEP*")
    return ports[0] if ports else None


def read_lines_until(ser, token, timeout):
    buf = b""
    end = time.time() + timeout
    while time.time() < end:
        buf += ser.read(ser.in_waiting or 1)
        if token in buf:
            break
    return buf


def install(ser, log, stats):
    ser.write(b"\r")
    banner = read_lines_until(ser, b">>> ", 2)
    ser.write(b"\x05")
    time.sleep(0.1)
    ser.write(AGENT.encode().replace(b"\n", b"\r") + b"\x04")
    out = read_lines_until(ser, b"AGENT_OK\r\n", 3)
    ok = b"AGENT_OK\r\n" in out
    stats.installs += ok
    log(f"install {'OK' if ok else 'FAILED ' + repr(out[-200:])} banner={banner[-80:]!r}")
    return ok


def session(ser, log, stats, deadline):
    """Run until deadline or until the port disappears. Returns True if deadline reached."""
    if not install(ser, log, stats):
        return False
    buf = b""
    next_poll = time.time()
    pending = None
    while time.time() < deadline:
        now = time.time()
        if now >= next_poll and pending is None:
            ser.write(b"_q()\r")
            pending = now
            next_poll = now + POLL_S
        buf += ser.read(ser.in_waiting or 1)
        while b"\r\n" in buf:
            line, buf = buf.split(b"\r\n", 1)
            text = line.decode(errors="replace")
            ev = EVENT_RE.search(text)
            if ev:
                stats.events += 1
                log(f"E {ev[1]} {ev[2]}")
            elif POLL_RE.search(text) and pending is not None:
                ms = (time.time() - pending) * 1000
                stats.polls += 1
                stats.poll_ms_sum += ms
                stats.max_poll_ms = max(stats.max_poll_ms, ms)
                pending = None
            elif text.startswith(("Traceback", "NameError", "TypeError", "OSError")):
                log(f"DEVICE {text}")
        if pending is not None and time.time() - pending > 1.0:
            stats.poll_misses += 1
            log("poll timeout")
            pending = None
    return True


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 600
    out = open(sys.argv[2], "a") if len(sys.argv) > 2 else sys.stdout
    start = time.time()
    deadline = start + duration
    stats = Stats()

    def log(msg):
        out.write(f"{time.time() - start:9.3f} {msg}\n")
        out.flush()

    ser = None
    try:
        while time.time() < deadline:
            port = find_port()
            if not port:
                time.sleep(0.5)
                continue
            try:
                ser = serial.Serial(port, 115200, timeout=0.02)
                if stats.installs:
                    stats.reconnects += 1
                    log(f"reconnected on {port}")
                if session(ser, log, stats, deadline):
                    break
            except (serial.SerialException, OSError) as e:
                log(f"disconnected: {e}")
                try:
                    ser.close()
                except Exception:
                    pass
                ser = None
                time.sleep(0.5)
    except KeyboardInterrupt:
        log("interrupted")
    finally:
        if ser is not None and ser.is_open:
            try:
                ser.write(RESTORE.encode() + b"\r")
                res = read_lines_until(ser, b"AGENT_OFF\r\n", 3)
                log("restore " + ("OK" if b"AGENT_OFF\r\n" in res else f"CHECK {res[-200:]!r}"))
            finally:
                ser.close()
        avg = stats.poll_ms_sum / stats.polls if stats.polls else 0
        log(f"STATS polls={stats.polls} misses={stats.poll_misses} avg_ms={avg:.1f} "
            f"max_ms={stats.max_poll_ms:.1f} events={stats.events} installs={stats.installs} "
            f"reconnects={stats.reconnects}")
        if out is not sys.stdout:
            out.close()


if __name__ == "__main__":
    main()
