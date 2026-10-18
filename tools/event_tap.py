"""Temporarily tap FX MIC UI events (RAM only) and log them.

Installs a wrapper around the factory `python_callback` that prints every
non-tick message plus handle/switch state changes, always forwarding to the
original callback. After DURATION seconds the factory callback is restored.
A power cycle also restores everything, since nothing is written to flash.

usage: event_tap.py [DURATION_SECONDS] [LOGFILE]
"""
import sys
import time

import serial

from fxserial import find_port, read_until_prompt

TAP = """\
_last = None
def _tap(m):
    global _last
    t = m >> 16
    try:
        if t != 3:
            print('EV', t, m & 0xFFFF)
        s = (round(ui.handle(), 2), ui.sw(0), ui.sw(1), ui.sw(2), ui.sw(3), ui.sw(4))
        if s != _last:
            _last = s
            print('ST', s)
    except Exception as e:
        print('ERR', e)
    python_callback(m)
ui.callback(_tap)
print('TAP_ON')
"""


def paste(ser, code):
    ser.write(b"\x05")  # paste mode
    time.sleep(0.1)
    ser.write(code.encode().replace(b"\n", b"\r"))
    ser.write(b"\x04")


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 60
    logfile = sys.argv[2] if len(sys.argv) > 2 else None
    ser = serial.Serial(find_port(), 115200, timeout=0.1)
    log = open(logfile, "w") if logfile else sys.stdout
    try:
        ser.write(b"\r")
        read_until_prompt(ser, 2)
        paste(ser, TAP)
        start = time.time()
        buf = b""
        while time.time() - start < duration:
            buf += ser.read(ser.in_waiting or 1)
            while b"\r\n" in buf:
                line, buf = buf.split(b"\r\n", 1)
                text = line.decode(errors="replace")
                if text.startswith(("EV", "ST", "ERR", "TAP_ON")):
                    log.write(f"{time.time() - start:7.3f} {text}\n")
                    log.flush()
    finally:
        ser.write(b"ui.callback(python_callback);print('TAP_OFF')\r")
        tail = b""
        end = time.time() + 3
        while b"TAP_OFF\r\n" not in tail and time.time() < end:
            tail += ser.read(ser.in_waiting or 1)
        tail = tail.decode(errors="replace")
        log.write(f"restore: {'OK' if 'TAP_OFF' in tail else 'CHECK! ' + tail!r}\n")
        log.close() if logfile else None
        ser.close()


if __name__ == "__main__":
    main()
