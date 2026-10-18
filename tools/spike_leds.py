"""Spike M0-b: interactive LED test. Press the GREY button to advance each step.

Every step is a RAM-only call; the last step restores the factory LED state
(a power cycle restores everything anyway).

usage: spike_leds.py [LOGFILE] [--auto SECONDS]   (--auto: advance every N s instead of grey)
"""
import sys
import time

import serial

from fxserial import find_port, read_until_prompt

STEPS = [
    "ui.leds(-1,0)",
    "ui.leds(0,0)",
    "ui.leds(3,0)",
    "ui.leds(-1,3)",
    "ui.leds(1,2)",
    "ui.led_level(0,0)",
    "ui.led_level(0,100)",
    "ui.led_level(1,100)",
    "ui.led_level(0,0.5)",
    "ui.led_level(1,1.0)",
    "ui.led_control(0)",
    "ui.leds(2,2)",
    "ui.led_control(1)",
    "ui.leds(fx_pos,sam_pos)",
]


def run(ser, cmd):
    ser.write(cmd.encode() + b"\r")
    return read_until_prompt(ser, 3).decode(errors="replace")


def grey_pressed(ser):
    out = run(ser, "print('G', ui.sw(0))")
    return "G 0" in out


def main():
    auto = float(sys.argv[sys.argv.index("--auto") + 1]) if "--auto" in sys.argv else None
    args = [a for a in sys.argv[1:] if a != "--auto" and not (auto and a == str(sys.argv[sys.argv.index("--auto") + 1]))]
    log = open(args[0], "w") if args else sys.stdout
    ser = serial.Serial(find_port(), 115200, timeout=0.05)
    try:
        ser.write(b"\r")
        read_until_prompt(ser, 2)
        if auto:
            time.sleep(5)  # countdown before step 1
        for i, cmd in enumerate(STEPS, 1):
            if auto:
                if i > 1:
                    time.sleep(auto)
                out = run(ser, cmd)
                result = [l for l in out.split("\r\n") if l and not l.startswith((">>>", cmd))]
                log.write(f"step {i:2d} {time.strftime('%H:%M:%S')} {cmd} -> {result}\n")
                log.flush()
                continue
            # wait for a fresh grey press (release first, then press)
            deadline = time.time() + 300
            while grey_pressed(ser) and time.time() < deadline:
                time.sleep(0.05)
            while not grey_pressed(ser):
                if time.time() > deadline:
                    log.write("timeout waiting for grey press\n")
                    return
                time.sleep(0.05)
            out = run(ser, cmd)
            result = [l for l in out.split("\r\n") if l and not l.startswith((">>>", cmd))]
            log.write(f"step {i:2d} {time.strftime('%H:%M:%S')} {cmd} -> {result}\n")
            log.flush()
    finally:
        run(ser, "ui.led_control(1)")
        run(ser, "ui.leds(fx_pos,sam_pos)")
        log.write("restored: ui.led_control(1); ui.leds(fx_pos,sam_pos)\n")
        if log is not sys.stdout:
            log.close()
        ser.close()


if __name__ == "__main__":
    main()
