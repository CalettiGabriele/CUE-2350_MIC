#!/usr/bin/env python3
"""Installs / removes the FXMic firmware on the EP-2350 over USB-C (One-Pager 002, ADR-003).

  fxmic_install.py status    what is on the mic (factory / FXMic / unknown)
  fxmic_install.py install   symbols on FX MIC DISK + /rom image with the boot hook, then power-cycle
  fxmic_install.py restore   writes the saved factory image back and removes the symbols

Needs: the app quit (it owns the serial port), `pip install pyserial mpremote mpy-cross`, the mic
freshly powered on (64 KB heap), FX MIC DISK mounted on the Mac for install/restore.
Never soft-resets the mic (Ctrl-D): on this firmware that detaches it from USB.
"""
import argparse, glob, hashlib, os, pathlib, re, shutil, subprocess, sys, tempfile, time

import serial

ROOT = pathlib.Path(__file__).resolve().parent.parent
FW = ROOT / "firmware" / "fxmic"
FACTORY_BIN = ROOT / "backup" / "rom" / "romfs-partition-1.0.9.bin"
FACTORY_SHA = "264e54d4"          # prefix of the SHA-256 of the 128 KB factory partition
BLOCK, BLOCKS = 4096, 32
DISK = pathlib.Path("/Volumes/FX MIC DISK")
SUPPORT = pathlib.Path.home() / "Library/Application Support/FXMicBridge/firmware"


class Mic:
    def __init__(self):
        ports = glob.glob("/dev/cu.usbmodemEP*")
        if not ports:
            sys.exit("FX MIC serial port not found: is the mic on and the USB-C cable in? (quit the app first)")
        self.s = serial.Serial(ports[0], 115200, timeout=0.2)
        self.s.write(b"\x03\x03"); time.sleep(0.3); self.s.read(5000)

    def ex(self, cmd, timeout=3.0):
        self.s.write(cmd.encode() + b"\r")
        out, end = b"", time.time() + timeout
        while time.time() < end:
            out += self.s.read(4096)
            if out.endswith(b">>> "):
                break
        text = out.decode(errors="replace")
        lines = text.replace("\r", "").split("\n")
        body = "\n".join(l for l in lines[1:] if l and not l.startswith(">>>"))
        if "Error" in body or "Traceback" in body:
            raise RuntimeError(f"{cmd!r} -> {body}")
        return body.strip()


def sha(b): return hashlib.sha256(b).hexdigest()


def check(mic):
    banner = mic.ex("import sys;print(sys.implementation._machine)")
    if "1.0.9" not in banner:
        sys.exit(f"unsupported firmware: {banner!r} (only EP-2350 1.0.9)")
    mem = mic.ex("import micropython;micropython.mem_info()")
    largest = int(re.search(r"max free sz: (\d+)", mem).group(1))
    if largest < 2048:
        sys.exit(f"heap too fragmented (largest free block {largest} B): switch the mic off and on, then retry")


def read_rom(mic):
    mic.ex("import vfs;dev=vfs.rom_ioctl(2,0);buf=bytearray(512)")
    data = b""
    for b in range(BLOCKS):
        for off in range(0, BLOCK, 512):
            mic.ex(f"dev.readblocks({b},buf,{off});print(buf.hex())")
            data += bytes.fromhex(mic.ex("print(buf.hex())"))
    return data


def listing(mic):
    return mic.ex("import os;print(os.listdir('/rom'))")


def write_rom(mic, image):
    image = image + b"\x00" * (-len(image) % 256)
    full = image + b"\xff" * (BLOCK * BLOCKS - len(image))
    mic.ex("import vfs,os;dev=vfs.rom_ioctl(2,0)")
    try: mic.ex("import fxmic;fxmic.pause()")
    except RuntimeError: pass
    mic.ex("vfs.umount('/rom')")
    for b in range(BLOCKS):
        mic.ex(f"dev.ioctl(6,{b})", 5)
    for off in range(0, len(image), 256):
        blk, o = divmod(off, BLOCK)
        mic.ex(f"dev.writeblocks({blk},bytes.fromhex('{image[off:off+256].hex()}'),{o})", 5)
    back = read_rom(mic)
    mic.ex("vfs.mount(vfs.VfsRom(vfs.rom_ioctl(2,0)),'/rom')")
    if back != full:
        sys.exit("READ-BACK MISMATCH: do not power off; run `restore` or retry install")
    print("written and verified, sha256", sha(back)[:16])


def build_image():
    """Factory files + FXMic files."""
    subprocess.run([sys.executable, str(FW / "build.py")], check=True, stdout=subprocess.DEVNULL)
    mpy = shutil.which("mpy-cross") or str(pathlib.Path(sys.executable).parent / "mpy-cross")
    if not os.path.exists(mpy):
        sys.exit("mpy-cross not found: pip install mpy-cross")
    from mpremote.romfs import make_romfs
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        factory = ROOT / "backup" / "rom"
        for name in ("README.md", "main.py"):
            shutil.copy(factory / name, d / name)
        shutil.copy(FW / "device" / "json.py", d / "json.py")
        for src, out in ((FW / "device" / "fxmic.py", "fxmic.mpy"), (FW / "build" / "fxmic_cfg.py", "fxmic_cfg.mpy"),
                         (factory / "main.py", "fxmic_factory.mpy")):
            subprocess.run([mpy, "-o", str(d / out), str(src)], check=True)
        return make_romfs(str(d), mpy_cross=False)


def symbols(install):
    if not DISK.exists():
        sys.exit("FX MIC DISK is not mounted on the Mac: it is needed to copy the symbols (and nothing else is written there)")
    target = DISK / ".fxmic"
    if install:
        target.mkdir(exist_ok=True)
        for f in sorted((FW / "build" / "symbols").glob("s*.wav")):
            subprocess.run(["cp", "-X", str(f), str(target / f.name)], check=True)
    elif target.exists():
        shutil.rmtree(target)
    subprocess.run(["dot_clean", "-m", str(DISK)], check=False)
    subprocess.run(["sync"])
    subprocess.run(["diskutil", "eject", str(DISK)], check=True)


def remount_fat(mic):
    mic.ex("import vfs,rp2;vfs.umount('/fat');vfs.mount(vfs.VfsFat(rp2.Flash()),'/fat')", 5)


def status(mic):
    files = listing(mic)
    data = read_rom(mic)
    kind = "factory" if sha(data).startswith(FACTORY_SHA) else "FXMic" if "fxmic.mpy" in files else "UNKNOWN"
    print(kind, "| /rom:", files, "| sha256", sha(data)[:16])
    return kind


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["status", "install", "restore"])
    a = ap.parse_args()
    mic = Mic()
    check(mic)
    kind = status(mic)
    if a.command == "status":
        return
    if kind == "UNKNOWN":
        sys.exit("unknown /rom content: refusing to write")
    SUPPORT.mkdir(parents=True, exist_ok=True)
    backup = SUPPORT / "factory-1.0.9.bin"
    if kind == "factory" and not backup.exists():
        shutil.copy(FACTORY_BIN, backup)
        print("factory image saved to", backup)
    if a.command == "install":
        symbols(True)
        time.sleep(2)
        remount_fat(mic)
        write_rom(mic, build_image())
        print("Now switch the mic off and on with the lever to start FXMic.")
    else:
        symbols(False)
        time.sleep(2)
        remount_fat(mic)
        write_rom(mic, (backup if backup.exists() else FACTORY_BIN).read_bytes().rstrip(b"\xff"))
        print("Factory image restored. Switch the mic off and on to run the factory logic.")


if __name__ == "__main__":
    main()
