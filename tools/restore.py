"""Bring the FX MIC back to its factory state after exploratory tests.

1. Device RAM: re-installs the factory UI callback (undoes event_tap.py).
2. FX MIC DISK: compares the disk with backup/factory-disk and lists files that
   tests added or changed. Dry run by default; pass --apply to fix them
   (added files are removed, changed/missing factory files are copied back).
3. Reminds you to power-cycle, which resets every RAM-only change
   (presets, samples loaded from REPL, callbacks).

usage: restore.py [--apply]
"""
import hashlib
import os
import shutil
import sys
import time

import serial

from fxserial import find_port, read_until_prompt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKUP = os.path.join(ROOT, "backup", "factory-disk")
DISK = "/Volumes/FX MIC DISK"
SYSTEM = {"System Volume Information", ".fseventsd", ".Spotlight-V100", ".Trashes"}


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def restore_callback():
    ser = serial.Serial(find_port(), 115200, timeout=0.1)
    try:
        ser.write(b"ui.callback(python_callback);print('CB_OK')\r")
        out = b""
        end = time.time() + 3
        while b"CB_OK\r\n" not in out and time.time() < end:
            out += ser.read(ser.in_waiting or 1)
        print("callback:", "factory callback restored" if b"CB_OK\r\n" in out else f"CHECK {out!r}")
    finally:
        ser.close()


def restore_disk(apply):
    expected = {}
    with open(os.path.join(BACKUP, "SHA256SUMS")) as f:
        for line in f:
            digest, name = line.split(maxsplit=1)
            expected[name.strip()] = digest
    on_disk = {n for n in os.listdir(DISK) if n not in SYSTEM and not n.startswith("._")}
    added = sorted(on_disk - expected.keys())
    changed = sorted(n for n in expected if n in on_disk and sha256(os.path.join(DISK, n)) != expected[n])
    missing = sorted(expected.keys() - on_disk)
    if not (added or changed or missing):
        print("disk: identical to factory backup")
        return
    print(f"disk: added={added} changed={changed} missing={missing}")
    if not apply:
        print("dry run: re-run with --apply to restore")
        return
    for n in added:
        p = os.path.join(DISK, n)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    for n in changed + missing:
        shutil.copy2(os.path.join(BACKUP, n), os.path.join(DISK, n))
    os.sync()
    print("disk: restored")


def main():
    apply = "--apply" in sys.argv
    restore_callback()
    if os.path.isdir(DISK):
        restore_disk(apply)
    else:
        print("disk: not mounted, skipped")
    print("then power-cycle: press the button above the USB port, then push the handle")


if __name__ == "__main__":
    main()
