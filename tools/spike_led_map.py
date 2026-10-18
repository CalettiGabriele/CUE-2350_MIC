"""Spike: map ui.led_level indices 0..7 to physical LEDs, then compare brightness levels.

Press the GREY button to advance. Each step lights exactly one thing; note what you see.
Everything is RAM-only; the end (or Ctrl-C) restores the factory LED control.

usage: spike_led_map.py [LOGFILE]
"""
import sys
import time

import serial

from fxserial import find_port, read_until_prompt

ALL_OFF = "[ui.led_level(j, 0) for j in range(8)] and None"
STEPS = [(f"indice {i} acceso", f"{ALL_OFF}; ui.led_level({i}, 1.0)") for i in range(8)]
STEPS += [
    ("TUTTI accesi a livello 1.0", "[ui.led_level(j, 1.0) for j in range(8)] and None"),
    ("TUTTI accesi a livello 0.1", "[ui.led_level(j, 0.1) for j in range(8)] and None"),
    ("TUTTI accesi a livello 0.02", "[ui.led_level(j, 0.02) for j in range(8)] and None"),
    ("TUTTI accesi a livello 255", "[ui.led_level(j, 255) for j in range(8)] and None"),
]


def run(ser, cmd):
    ser.write(cmd.encode() + b"\r")
    return read_until_prompt(ser, 3).decode(errors="replace")


def grey_pressed(ser):
    return "G 0" in run(ser, "print('G', ui.sw(0))")


def wait_grey(ser, deadline):
    while grey_pressed(ser):          # wait for release
        if time.time() > deadline:
            return False
        time.sleep(0.05)
    while not grey_pressed(ser):      # then a new press
        if time.time() > deadline:
            return False
        time.sleep(0.05)
    return True


def main():
    log = open(sys.argv[1], "w") if len(sys.argv) > 1 else sys.stdout
    ser = serial.Serial(find_port(), 115200, timeout=0.05)
    try:
        ser.write(b"\r")
        read_until_prompt(ser, 2)
        run(ser, "ui.led_control(0)")
        run(ser, ALL_OFF)
        deadline = time.time() + 600
        for n, (label, cmd) in enumerate(STEPS, 1):
            if not wait_grey(ser, deadline):
                log.write("timeout\n")
                return
            out = run(ser, cmd)
            result = [l for l in out.split("\r\n") if l and not l.startswith((">>>", cmd[:20]))]
            log.write(f"passo {n:2d} {time.strftime('%H:%M:%S')} {label} -> {result}\n")
            log.flush()
        wait_grey(ser, deadline)      # last press closes the test
    finally:
        run(ser, "ui.led_control(1)")
        run(ser, "ui.leds(fx_pos,sam_pos)")
        log.write("ripristinato: led_control(1), leds(fx_pos, sam_pos)\n")
        if log is not sys.stdout:
            log.close()
        ser.close()


if __name__ == "__main__":
    main()
