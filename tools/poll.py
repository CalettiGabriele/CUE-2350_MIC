"""Poll FX MIC sensors over the REPL (read-only, nothing installed in callbacks).

Defines a tiny `_p()` helper in RAM that prints switches, handle, shaker,
accelerometer and the 4 ADC channels, then calls it at ~20 Hz. The helper is
deleted at the end; a power cycle also clears it.

usage: poll.py [DURATION_SECONDS] [LOGFILE]
"""
import sys
import time

import serial

from fxserial import find_port, read_until_prompt

HELPER = (
    "def _p(): print('P', [ui.sw(i) for i in range(5)], round(ui.handle(), 3), "
    "round(ui.shaker(), 4), ui.acc(), [ui.adc(i) for i in range(4)])"
)


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 60
    log = open(sys.argv[2], "w") if len(sys.argv) > 2 else sys.stdout
    ser = serial.Serial(find_port(), 115200, timeout=0.05)
    try:
        ser.write(b"\r")
        read_until_prompt(ser, 2)
        ser.write(HELPER.encode() + b"\r\r")
        read_until_prompt(ser, 2)
        start = time.time()
        while time.time() - start < duration:
            t0 = time.time()
            ser.write(b"_p()\r")
            out = read_until_prompt(ser, 1).decode(errors="replace")
            for line in out.split("\r\n"):
                if line.startswith("P "):
                    log.write(f"{t0 - start:7.3f} {line}\n")
            log.flush()
            time.sleep(max(0, 0.05 - (time.time() - t0)))
    finally:
        ser.write(b"del _p\r")
        read_until_prompt(ser, 2)
        if log is not sys.stdout:
            log.close()
        ser.close()


if __name__ == "__main__":
    main()
