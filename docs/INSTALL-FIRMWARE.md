# Install the FXMic firmware on the EP-2350 FX MIC

> For humans and for AI agents. It takes about 5 minutes.
> **[YOU]** = a physical step only a person can do. An agent must stop and ask for it, then wait for a "done".
> **[ANY]** = a command: an agent can run it, or a person can (in the Claude desktop app every command block has a Run button).
> What FXMic is and how it works: [JACK-CHANNEL.md](JACK-CHANNEL.md).

## What you get
With FXMic the mic recognises its own gestures and sends them as short high-pitched codes through the 3.5 mm jack, so the CUE-2350 MIC app works **without the USB-C cable**. The install is reversible: the factory image is saved on your Mac before anything is written.

## Requirements
- EP-2350 FX MIC with factory firmware **1.0.9** (the installer checks it).
- A USB-C **data** cable from the mic to the Mac (for the install only).
- For jack-only use afterwards: a USB-C (or USB) audio adapter with an input, and a 3.5 mm cable from the mic's output.
- macOS, Python 3.9 or later, this repository.

## Rules (read once)
- **Never soft-reset the mic** (Ctrl-D, `mpremote run`, `mpremote repl`): on this firmware it drops off USB and needs a power cycle with the lever.
- **The CUE-2350 MIC app must be closed** during install and restore: it uses the same serial port and loads code into the mic's memory.
- **Power-cycle right before installing.** The mic has 64 KB of RAM; the installer refuses to start if it is fragmented.
- If the mic disappears from USB at any point: **[YOU]** switch it off and on with the lever.

## Install

1. **[ANY]** One-time setup of the Python tools, from the repository root:
   ```bash
   python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt
   ```

2. **[ANY]** Quit the app if it is running:
   ```bash
   osascript -e 'quit app id "com.fxmicbridge.app"'
   ```

3. **[YOU]** Connect the mic to the Mac with the USB-C data cable.

4. **[YOU]** Switch the mic **off and on with the lever**. Wait until the disk **FX MIC DISK** appears in Finder.

5. **[ANY]** Install (do not run `status` first: it uses up the fresh memory):
   ```bash
   .venv/bin/python tools/fxmic_install.py install
   ```
   Expected end of the output:
   ```
   written and verified, sha256 …
   Now switch the mic off and on with the lever to start FXMic.
   ```
   If it says `heap too fragmented`, repeat steps 2, 4 and 5. If it says `FX MIC serial port not found`, check the cable (it must carry data) and repeat step 4. Nothing has been written in either case.

6. **[YOU]** Switch the mic **off and on with the lever**. The LEDs light one by one down the column, then the four red LEDs stay on. FXMic is running.

## Use it with the jack only

7. **[YOU]** Unplug the USB-C cable. Connect the mic's 3.5 mm output to the audio adapter, and the adapter to the Mac.

8. **[YOU]** In the app: **Settings › Device › Connection › Jack only**, and **Settings › Audio › Microphone** = the audio adapter (for example "USB Advanced Audio Device"). Save. After a few seconds the status says "Mic: connected through the jack".

9. **[ANY]** Optional check, without the app: record 12 s from the adapter and look for heartbeats (needs `ffmpeg`; device `:0` is the first audio input listed by `ffmpeg -f avfoundation -list_devices true -i ""`):
   ```bash
   ffmpeg -loglevel error -f avfoundation -i ":0" -ar 48000 -ac 1 -t 12 /tmp/fxmic-check.wav && echo "recorded: open it in an audio editor, a short high tick every ~5 s is the heartbeat"
   ```

## Check what is on the mic

**[ANY]** With the app closed and the mic connected over USB-C:
```bash
.venv/bin/python tools/fxmic_install.py status
```
It prints `factory`, `FXMic` or `UNKNOWN`. After `status`, power-cycle the mic before an install or a restore.

## Go back to the factory firmware

1. **[ANY]** Quit the app (step 2 above).
2. **[YOU]** USB-C connected, switch the mic off and on with the lever, wait for FX MIC DISK.
3. **[ANY]** Restore:
   ```bash
   .venv/bin/python tools/fxmic_install.py restore
   ```
4. **[YOU]** Switch the mic off and on with the lever.

The restore writes back the image saved at the first install (`~/Library/Application Support/FXMicBridge/firmware/factory-1.0.9.bin`) and removes the `.fxmic` folder from FX MIC DISK.

## If something goes wrong

| Symptom | What to do |
|---|---|
| FXMic misbehaves and you want the factory behaviour now | **[YOU]** switch on with the lever and **hold orange for 1.5 s within the first 8 s**: the mic runs the factory logic until the next power cycle. Then restore. (Simulated, not yet tried on a real mic.) |
| `READ-BACK MISMATCH` | Do **not** switch the mic off. Run the install again, or `restore`. |
| `unknown /rom content: refusing to write` | The mic has a firmware this tool does not know. Nothing was written; do not force it. |
| `unsupported firmware` | Only factory 1.0.9 is supported. |
| No heartbeat on the jack | Check the cable goes into the mic's **output**, raise the mic's volume a little, pick the right input in Settings › Audio. |

## Notes for AI agents
- Ask the person for every **[YOU]** step, one at a time, and wait for confirmation. Do not guess that the lever was used.
- Do not run any other tool that opens the mic's serial port (`mpremote`, `screen`, the app) between the power cycle and `install`.
- Treat any output other than `written and verified` as "not installed" and report it as is.
- Never commit anything read from the mic: the factory files are Teenage Engineering's.
