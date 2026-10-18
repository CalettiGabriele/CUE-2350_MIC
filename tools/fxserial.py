"""Minimal, non-destructive serial helper for exploring the EP-2350 FX MIC.

Modes:
  listen  SECONDS            only read, send nothing
  repl    CMD [CMD ...]      Ctrl-C into the REPL, run each command, print output
  reset                      Ctrl-D soft reset (re-runs the factory boot/main)

Nothing here writes to the device filesystem; commands are typed by the caller.
"""
import glob
import sys
import time

import serial


def find_port():
    ports = glob.glob("/dev/cu.usbmodemEP*")
    if not ports:
        sys.exit("FX MIC serial port not found (/dev/cu.usbmodemEP*)")
    return ports[0]


def read_for(ser, seconds):
    out = b""
    end = time.time() + seconds
    while time.time() < end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            out += chunk
    return out


def read_until_prompt(ser, timeout=5.0):
    out = b""
    end = time.time() + timeout
    while time.time() < end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            out += chunk
            if out.endswith(b">>> "):
                break
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    mode = sys.argv[1]
    ser = serial.Serial(find_port(), 115200, timeout=0.1)
    try:
        if mode == "listen":
            data = read_for(ser, float(sys.argv[2]) if len(sys.argv) > 2 else 3)
            print(f"[{len(data)} bytes] {data!r}")
        elif mode == "repl":
            # The factory firmware already sits at a free REPL prompt, so try a
            # plain newline first and only interrupt with Ctrl-C if needed.
            ser.write(b"\r")
            banner = read_until_prompt(ser, 2)
            if not banner.endswith(b">>> "):
                ser.write(b"\x03")
                banner += read_until_prompt(ser, 3)
                print("[sent Ctrl-C]")
            print(banner.decode(errors="replace"))
            for cmd in sys.argv[2:]:
                ser.write(cmd.encode() + b"\r")
                print(read_until_prompt(ser, 10).decode(errors="replace"))
        elif mode == "cat":
            # cat DEVICE_PATH LOCAL_PATH: copy a device file to the Mac (read-only on device)
            src, dst = sys.argv[2], sys.argv[3]
            ser.write(b"\r")
            read_until_prompt(ser, 2)
            ser.write(f"import binascii;_f=open('{src}','rb')\r".encode())
            read_until_prompt(ser, 3)
            data = b""
            while True:
                ser.write(b"print('@'+binascii.hexlify(_f.read(1024)).decode())\r")
                raw = read_until_prompt(ser, 10).decode(errors="replace")
                line = next(l for l in raw.split("\r\n") if l.startswith("@"))
                chunk = bytes.fromhex(line[1:])
                if not chunk:
                    break
                data += chunk
            ser.write(b"_f.close();del _f\r")
            read_until_prompt(ser, 3)
            with open(dst, "wb") as f:
                f.write(data)
            print(f"{src} -> {dst} ({len(data)} bytes)")
        elif mode == "reset":
            ser.write(b"\x03")
            time.sleep(0.2)
            ser.write(b"\x04")
            print(read_for(ser, 3).decode(errors="replace"))
        else:
            sys.exit(__doc__)
    finally:
        ser.close()


if __name__ == "__main__":
    main()
