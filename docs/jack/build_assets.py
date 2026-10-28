#!/usr/bin/env python3
"""Builds the sounds, charts and animations of docs/JACK-CHANNEL.md. Standard library only.

Everything is computed from the real codebook (app/Sources/FXMicCore/JackCodebook.swift) and,
for the spectrogram, from a real recording of the mic taken through the jack dongle
(docs/jack/audio/real-heartbeat.wav, 48 kHz mono).

usage: python3 docs/jack/build_assets.py      (writes docs/jack/audio/*.wav and docs/jack/*.svg)
"""
import base64
import json
import math
import os
import re
import struct
import wave
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
AUDIO = os.path.join(HERE, "audio")

INK, PAPER, ORANGE, RED = "#1A1A1A", "#EDEDE8", "#F05A28", "#E3242B"
MUTED, RULE = "#8C8C88", "#C9C9C3"
SYM_COLORS = ["#F05A28", "#2F7DA8", "#5F8F2A", "#8E5BA8"]
SANS = "font-family:Barlow,'Helvetica Neue',Arial,sans-serif"
MONO = "font-family:'IBM Plex Mono',Menlo,monospace"

cb = json.load(open(os.path.join(ROOT, "firmware/fxmic/codebook.json")))
FS = cb["sampleRate"]
SYM_MS, GAP_MS = cb["symbolMs"], cb["gapMs"]
SYMBOLS = cb["symbols"]
swift = open(os.path.join(ROOT, "app/Sources/FXMicCore/JackCodebook.swift")).read()
MESSAGES = {m: [int(x) for x in s.split(",")] for m, s in re.findall(r'"([\w.]+)": \[([\d, ]+)\]', swift)}


# ---------------------------------------------------------------------------- audio

def tone_pair(a, b, ms, fs=FS, gain=0.45):
    n = int(fs * ms / 1000)
    fade = int(fs * 0.003)
    out = []
    for k in range(n):
        env = min(1.0, k / fade, (n - 1 - k) / fade)
        out.append(gain * env * (math.sin(2 * math.pi * a * k / fs) + math.sin(2 * math.pi * b * k / fs)))
    return out


def silence(ms, fs=FS):
    return [0.0] * int(fs * ms / 1000)


def message(name, slow=1):
    """As the mic plays it; `slow` divides the tones and stretches the time (to hear the shape)."""
    out = silence(150 * slow)
    for s in MESSAGES[name]:
        a, b = SYMBOLS[s]
        out += tone_pair(a / slow, b / slow, SYM_MS * slow)
    return out + silence(GAP_MS * slow + 150 * slow)


def write_wav(name, samples, fs=FS):
    with wave.open(os.path.join(AUDIO, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs)
        w.writeframes(struct.pack("<%dh" % len(samples), *(int(max(-1, min(1, v)) * 32767) for v in samples)))


def read_wav(name):
    with wave.open(os.path.join(AUDIO, name)) as w:
        n = w.getnframes()
        return [v / 32768 for v in struct.unpack("<%dh" % n, w.readframes(n))], w.getframerate()


# ---------------------------------------------------------------------------- decoder (Python port)

WIN, HOP = int(FS * 0.02), int(FS * 0.01)
TONES = sorted({f for p in SYMBOLS for f in p})


def goertzel(x, f, fs=FS):
    c = 2 * math.cos(2 * math.pi * f / fs)
    s1 = s2 = 0.0
    for v in x:
        s1, s2 = v + c * s1 - s2, s1
    return math.sqrt(max(s1 * s1 + s2 * s2 - c * s1 * s2, 0)) * 2 / len(x)


def scores(x):
    a = {f: goertzel(x, f) for f in TONES}
    return [min(a[p], a[q]) for p, q in SYMBOLS]


def label(sc, threshold=0.008, separation=2.5):
    best = max(range(4), key=lambda k: sc[k])
    second = sorted(sc)[-2]
    return best if sc[best] >= threshold and sc[best] >= separation * second else -1


# ---------------------------------------------------------------------------- svg helpers

def svg(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'role="img" aria-label="{title}"><title>{title}</title>'
            f'<rect width="{w}" height="{h}" rx="14" fill="{PAPER}"/>{body}</svg>\n')


def text(x, y, s, size=14, fill=INK, weight=600, anchor="start", mono=False, extra=""):
    fam = MONO if mono else SANS
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}" '
            f'text-anchor="{anchor}" style="{fam}" {extra}>{s}</text>')


def save(name, content):
    with open(os.path.join(HERE, name), "w") as f:
        f.write(content)


# ---------------------------------------------------------------------------- 1. pipeline

def pipeline():
    boxes = [
        ("Button / handle", "press, release,", "shaker"),
        ("FXMic firmware", "gesture recognizer", "16 ms tick"),
        ("Code queue", "one code at a time", "3 symbols + gap"),
        ("Sampler", "4 two-tone WAVs", "in slots 0-3"),
        ("3.5 mm jack", "line out", "voice + codes"),
        ("USB-C dongle", "48 kHz input", "flat to 19.7 kHz"),
        ("Goertzel decoder", "8 tones, 20 ms", "every 10 ms"),
        ("Gesture", "same enum as", "the USB path"),
    ]
    w, h = 1120, 330
    body = text(32, 44, "From a button press to a gesture on the Mac", 22, weight=800)
    body += text(32, 70, "One audio wire, one direction: the mic speaks, the Mac listens.", 14, MUTED)
    bw, gap, y = 118, 18, 120
    for i, (t, a, b) in enumerate(boxes):
        x = 32 + i * (bw + gap)
        side = ORANGE if i < 4 else INK
        body += f'<rect x="{x}" y="{y}" width="{bw}" height="96" rx="10" fill="#fff" stroke="{side}" stroke-width="2"/>'
        body += text(x + bw / 2, y + 30, t, 13, side, 800, "middle")
        body += text(x + bw / 2, y + 56, a, 11, INK, 500, "middle", True)
        body += text(x + bw / 2, y + 74, b, 11, INK, 500, "middle", True)
        if i < len(boxes) - 1:
            ax = x + bw + 2
            body += f'<path d="M{ax} {y + 48} h{gap - 6}" stroke="{MUTED}" stroke-width="2"/>'
            body += f'<path d="M{ax + gap - 6} {y + 43} l6 5 l-6 5 z" fill="{MUTED}"/>'
    # the two halves
    body += f'<rect x="32" y="236" width="{4 * bw + 3 * gap}" height="6" rx="3" fill="{ORANGE}"/>'
    body += text(32, 268, "ON THE MIC (MicroPython, 64 KB heap)", 12, ORANGE, 800)
    x2 = 32 + 4 * (bw + gap)
    body += f'<rect x="{x2}" y="236" width="{4 * bw + 3 * gap}" height="6" rx="3" fill="{INK}"/>'
    body += text(x2, 268, "ON THE MAC (Swift app)", 12, INK, 800)
    # the moving dot: one code travelling
    body += (f'<circle r="7" fill="{RED}"><animateMotion dur="4s" repeatCount="indefinite" '
             f'path="M{32 + bw / 2} {y - 16} H{32 + 7 * (bw + gap) + bw / 2}" keyTimes="0;1" calcMode="linear"/>'
             f'<animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.08;0.92;1" dur="4s" repeatCount="indefinite"/></circle>')
    body += text(32, 306, "The voice travels on the same wire: the app cuts the take between the “handle down” and “handle up” codes.", 13, MUTED, 500)
    save("pipeline.svg", svg(w, h, body, "Jack channel pipeline"))


# ---------------------------------------------------------------------------- 2. frequency plan

def spectrum_plan():
    w, h = 1120, 420
    x0, x1, yb = 60, 1080, 330
    def fx(f): return x0 + (x1 - x0) * f / 24000
    body = text(32, 44, "Where the codes live in the spectrum", 22, weight=800)
    body += text(32, 70, "48 kHz sampling: everything up to 24 kHz is on the wire. Whisper only keeps what is below 8 kHz.", 14, MUTED)
    # bands
    body += f'<rect x="{fx(80)}" y="110" width="{fx(8000) - fx(80)}" height="{yb - 110}" fill="{INK}" opacity="0.08"/>'
    body += text(fx(4000), 132, "VOICE KEPT BY WHISPER (16 kHz audio)", 12, INK, 800, "middle")
    body += f'<rect x="{fx(12000) - 6}" y="110" width="{fx(19000) - fx(12000) + 12}" height="{yb - 110}" fill="{ORANGE}" opacity="0.12"/>'
    body += text(fx(15500), 128, "FXMIC CODES 12-19 kHz", 12, ORANGE, 800, "middle")
    body += f'<line x1="{fx(19700)}" y1="104" x2="{fx(19700)}" y2="{yb}" stroke="{RED}" stroke-dasharray="4 4" stroke-width="2"/>'
    body += text(fx(19700) + 6, 160, "dongle", 12, RED, 700)
    body += text(fx(19700) + 6, 176, "roll-off", 12, RED, 700)
    body += text(fx(19700) + 6, 192, "19.7 kHz", 12, RED, 700, mono=True)
    # tones
    for s, (a, b) in enumerate(SYMBOLS):
        for f in (a, b):
            top = yb - 70 - 36 * s
            body += f'<line x1="{fx(f)}" y1="{yb}" x2="{fx(f)}" y2="{top}" stroke="{SYM_COLORS[s]}" stroke-width="4" stroke-linecap="round"/>'
        top = yb - 70 - 36 * s
        body += f'<path d="M{fx(a)} {top} H{fx(b)}" stroke="{SYM_COLORS[s]}" stroke-width="1.5" stroke-dasharray="3 3"/>'
        body += f'<rect x="{(fx(a) + fx(b)) / 2 - 16}" y="{top - 9}" width="32" height="18" rx="4" fill="{PAPER}"/>'
        body += text((fx(a) + fx(b)) / 2, top + 5, f"S{s}", 12, SYM_COLORS[s], 800, "middle", True)
    # axis
    body += f'<line x1="{x0}" y1="{yb}" x2="{x1}" y2="{yb}" stroke="{INK}" stroke-width="2"/>'
    for k in range(0, 25, 2):
        x = fx(k * 1000)
        body += f'<line x1="{x}" y1="{yb}" x2="{x}" y2="{yb + 6}" stroke="{INK}"/>'
        body += text(x, yb + 24, f"{k}", 12, INK, 500, "middle", True)
    body += text(x1, yb + 48, "kHz", 12, MUTED, 600, "end", True)
    body += text(32, 404, "Each symbol is two tones at once. Tones sit on 1 kHz multiples, so a 20 ms analysis window separates them cleanly.", 13, MUTED, 500)
    save("spectrum-plan.svg", svg(w, h, body, "Frequency plan"))


# ---------------------------------------------------------------------------- 3. message timeline (static)

def timeline():
    w, h = 1120, 300
    body = text(32, 44, "One message on the wire: tap.orange", 22, weight=800)
    body += text(32, 70, "Three symbols of 40 ms, then 50 ms of silence before the next code may start.", 14, MUTED)
    x0, scale, y = 60, 4.6, 120     # px per ms
    t = 0
    for i, s in enumerate(MESSAGES["tap.orange"]):
        x = x0 + t * scale
        body += f'<rect x="{x}" y="{y}" width="{SYM_MS * scale - 2}" height="70" rx="6" fill="{SYM_COLORS[s]}"/>'
        a, b = SYMBOLS[s]
        body += text(x + SYM_MS * scale / 2, y + 32, f"S{s}", 18, "#fff", 800, "middle", True)
        body += text(x + SYM_MS * scale / 2, y + 54, f"{a // 1000}+{b // 1000} kHz", 12, "#fff", 600, "middle", True)
        t += SYM_MS
    x = x0 + t * scale
    body += f'<rect x="{x}" y="{y}" width="{GAP_MS * scale}" height="70" rx="6" fill="none" stroke="{MUTED}" stroke-dasharray="5 5"/>'
    body += text(x + GAP_MS * scale / 2, y + 40, "gap", 14, MUTED, 700, "middle", True)
    end = t + GAP_MS
    body += f'<line x1="{x0}" y1="{y + 96}" x2="{x0 + end * scale}" y2="{y + 96}" stroke="{INK}"/>'
    for ms in range(0, end + 1, 10):
        xx = x0 + ms * scale
        tall = ms % 40 == 0 and end - ms >= 20 or ms == end
        body += f'<line x1="{xx}" y1="{y + 96}" x2="{xx}" y2="{y + (104 if tall else 100)}" stroke="{INK}"/>'
        if tall:
            body += text(xx, y + 122, f"{ms} ms", 12, INK, 500, "middle", True)
    body += text(x0 + end * scale + 30, y + 30, "4 symbols, 3 per message,", 14, INK, 700)
    body += text(x0 + end * scale + 30, y + 52, "no two equal neighbours:", 14, INK, 700)
    body += text(x0 + end * scale + 30, y + 74, "4 × 3 × 3 = 36 words,", 14, INK, 700)
    body += text(x0 + end * scale + 30, y + 96, f"{len(MESSAGES)} in use.", 14, INK, 700)
    body += text(32, 280, "Equal neighbours are banned because the sampler retriggers the same slot without a gap: S1 S1 would sound like one long S1.", 13, MUTED, 500)
    save("message-timeline.svg", svg(w, h, body, "Message timeline"))


# ---------------------------------------------------------------------------- 4. decoder animation

def decoder_animation():
    """Slow motion of the real algorithm on the real waveform of tap.orange."""
    x = silence(30) + message("tap.orange")[int(FS * 0.15):]   # 30 ms lead-in
    total_ms = len(x) * 1000 / FS
    windows = []
    for start in range(0, len(x) - WIN, HOP):
        sc = scores(x[start:start + WIN])
        windows.append((start * 1000 / FS, sc, label(sc)))
    # runs and early delivery, like JackDecoder.step
    events, runs, cur, length, delivered = [], [], -1, 0, None
    for i, (_, sc, lb) in enumerate(windows):
        if lb >= 0 and lb == cur:
            length += 1
            if delivered is None and length == 2 and len(runs) == 2:
                runs.append(cur)
                delivered = i
        elif lb >= 0:
            if cur >= 0 and length >= 2 and delivered is None:
                runs.append(cur)
            cur, length = lb, 1
        else:
            if cur >= 0 and length >= 2 and delivered is None:
                runs.append(cur)
            cur, length = -1, 0
        events.append(list(runs))
    found = [n for n, s in MESSAGES.items() if s == runs[:3]]
    n = len(windows)
    step = 0.32                         # seconds per window in the animation
    dur = n * step + 2.5                # + a pause on the result
    w, h = 1120, 560
    x0, scale = 60, (1000 - 60) / total_ms
    body = text(32, 44, "The decoder, in slow motion", 22, weight=800)
    body += text(32, 70, f"A 20 ms window slides every 10 ms over the input. Real waveform of tap.orange, real thresholds. {step * 1000 / 10:.0f}× slower.", 14, MUTED)
    # waveform (envelope drawing: symbols as coloured blocks + sine-ish texture)
    yw = 150
    t = 30
    for s in MESSAGES["tap.orange"]:
        xx = x0 + t * scale
        body += f'<rect x="{xx}" y="{yw - 34}" width="{SYM_MS * scale}" height="68" fill="{SYM_COLORS[s]}" opacity="0.18"/>'
        pts = " ".join(f"{xx + k * SYM_MS * scale / 80:.1f},{yw + 28 * math.sin(k * 1.9) * math.sin(k * 0.37):.1f}" for k in range(81))
        body += f'<polyline points="{pts}" fill="none" stroke="{SYM_COLORS[s]}" stroke-width="1.5"/>'
        body += text(xx + SYM_MS * scale / 2, yw - 44, f"S{s}", 13, SYM_COLORS[s], 800, "middle", True)
        t += SYM_MS
    body += f'<line x1="{x0}" y1="{yw}" x2="{x0 + total_ms * scale}" y2="{yw}" stroke="{RULE}"/>'
    body += text(x0 - 10, yw + 4, "input", 12, MUTED, 600, "end")
    # sliding window
    kt = ";".join(f"{i / n:.4f}" for i in range(n)) + ";1"
    xs = ";".join(f"{x0 + windows[i][0] * scale:.1f}" for i in range(n)) + f";{x0 + windows[-1][0] * scale:.1f}"
    frac = n * step / dur
    def times(vals_per_window, last):
        vals = ";".join(vals_per_window) + f";{last};{last}"
        keys = ";".join(f"{i * step / dur:.4f}" for i in range(n)) + f";{frac:.4f};1"
        return vals, keys
    vals, keys = times([f"{x0 + windows[i][0] * scale:.1f}" for i in range(n)], f"{x0 + windows[-1][0] * scale:.1f}")
    body += (f'<rect y="{yw - 50}" width="{20 * scale}" height="100" rx="4" fill="none" stroke="{INK}" stroke-width="2.5">'
             f'<animate attributeName="x" values="{vals}" keyTimes="{keys}" calcMode="discrete" dur="{dur}s" repeatCount="indefinite"/></rect>')
    body += text(x0 + total_ms * scale + 20, yw - 10, "20 ms window", 12, INK, 700)
    body += text(x0 + total_ms * scale + 20, yw + 8, "hop 10 ms", 12, MUTED, 600)
    # score bars
    yb, bh = 380, 120
    body += text(32, yb - bh - 24, "Goertzel score of each symbol = the weaker of its two tones", 14, INK, 800)
    thr_y = yb - min(bh, 0.008 / 0.5 * bh * 6)
    for s in range(4):
        bx = 80 + s * 150
        vals_h, vals_y = [], []
        for _, sc, _ in windows:
            v = min(1.0, sc[s] / 0.5)
            hh = max(1.0, v * bh)
            vals_h.append(f"{hh:.1f}"); vals_y.append(f"{yb - hh:.1f}")
        hv, kv = times(vals_h, "1")
        yv, _ = times(vals_y, f"{yb - 1}")
        body += (f'<rect x="{bx}" width="70" rx="4" fill="{SYM_COLORS[s]}">'
                 f'<animate attributeName="height" values="{hv}" keyTimes="{kv}" calcMode="discrete" dur="{dur}s" repeatCount="indefinite"/>'
                 f'<animate attributeName="y" values="{yv}" keyTimes="{kv}" calcMode="discrete" dur="{dur}s" repeatCount="indefinite"/></rect>')
        a, b = SYMBOLS[s]
        body += text(bx + 35, yb + 22, f"S{s}", 14, SYM_COLORS[s], 800, "middle", True)
        body += text(bx + 35, yb + 40, f"{a // 1000}+{b // 1000}k", 11, MUTED, 600, "middle", True)
    body += f'<line x1="60" y1="{yb}" x2="660" y2="{yb}" stroke="{INK}"/>'
    body += text(680, yb - bh + 8, "A window names a symbol when", 13, INK, 700)
    body += text(680, yb - bh + 28, "• both its tones are present, and", 13, INK, 500)
    body += text(680, yb - bh + 48, "• it beats every other symbol by 2.5×.", 13, INK, 500)
    body += text(680, yb - bh + 76, "Two windows in a row make a run;", 13, INK, 500)
    body += text(680, yb - bh + 96, "three runs in the codebook make a message,", 13, INK, 500)
    body += text(680, yb - bh + 116, "delivered as soon as the third run is stable.", 13, INK, 500)
    # label per window and runs
    ylab = yb + 84
    body += text(32, ylab, "window says:", 13, MUTED, 700)
    lab_vals = [("S%d" % lb if lb >= 0 else "—") for _, _, lb in windows]
    for i, lv in enumerate(lab_vals):
        vis = ";".join("1" if j == i else "0" for j in range(n)) + ";0;0"
        _, kv = times(["0"] * n, "0")
        col = SYM_COLORS[windows[i][2]] if windows[i][2] >= 0 else MUTED
        body += (f'<g opacity="0">{text(140, ylab, lv, 16, col, 800, mono=True)}'
                 f'<animate attributeName="opacity" values="{vis}" keyTimes="{kv}" calcMode="discrete" dur="{dur}s" repeatCount="indefinite"/></g>')
    body += text(260, ylab, "runs:", 13, MUTED, 700)
    for r in range(3):
        rx = 320 + r * 60
        body += f'<rect x="{rx}" y="{ylab - 20}" width="48" height="28" rx="6" fill="none" stroke="{RULE}"/>'
        first = next((i for i, e in enumerate(events) if len(e) > r), None)
        if first is None:
            continue
        s = runs[r]
        vis = ";".join("1" if j >= first else "0" for j in range(n)) + ";1;1"
        _, kv = times(["0"] * n, "0")
        body += (f'<g opacity="0"><rect x="{rx}" y="{ylab - 20}" width="48" height="28" rx="6" fill="{SYM_COLORS[s]}"/>'
                 f'{text(rx + 24, ylab, f"S{s}", 15, "#fff", 800, "middle", True)}'
                 f'<animate attributeName="opacity" values="{vis}" keyTimes="{kv}" calcMode="discrete" dur="{dur}s" repeatCount="indefinite"/></g>')
    if delivered is not None and found:
        vis = ";".join("1" if j >= delivered else "0" for j in range(n)) + ";1;1"
        _, kv = times(["0"] * n, "0")
        body += (f'<g opacity="0">{text(520, ylab, "→ " + found[0], 22, RED, 800, mono=True)}'
                 f'{text(520, ylab + 26, f"delivered {windows[delivered][0] + 20 - 30:.0f} ms after the code started", 13, MUTED, 600)}'
                 f'<animate attributeName="opacity" values="{vis}" keyTimes="{kv}" calcMode="discrete" dur="{dur}s" repeatCount="indefinite"/></g>')
    save("decoder-animation.svg", svg(w, h, body, "Decoder animation"))
    return found, delivered and windows[delivered][0] + 20 - 30


# ---------------------------------------------------------------------------- 5. spectrogram of a real recording

def png(width, height, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def colour(v):
    """0..1 → paper to orange to ink."""
    stops = [(0.0, (237, 237, 232)), (0.45, (240, 90, 40)), (0.75, (227, 36, 43)), (1.0, (26, 26, 26))]
    for (a, ca), (b, cb_) in zip(stops, stops[1:]):
        if v <= b:
            t = (v - a) / (b - a)
            return [round(ca[i] + (cb_[i] - ca[i]) * t) for i in range(3)]
    return list(stops[-1][1])


def spectrogram(samples, fs, fmin, fmax, fstep, hop_ms, win_ms, title, sub, name, marks=()):
    win, hop = int(fs * win_ms / 1000), int(fs * hop_ms / 1000)
    hann = [0.5 - 0.5 * math.cos(2 * math.pi * i / (win - 1)) for i in range(win)]
    freqs = list(range(fmax, fmin - 1, -fstep))
    cols = []
    for st in range(0, len(samples) - win, hop):
        seg = [samples[st + i] * hann[i] for i in range(win)]
        cols.append([goertzel(seg, f, fs) for f in freqs])
    db = [[20 * math.log10(max(v, 1e-6)) for v in c] for c in cols]
    lo, hi = -80, max(max(c) for c in db)
    px, py = 4, 3
    rows = []
    for r in range(len(freqs)):
        line = []
        for c in db:
            line += colour(min(1, max(0, (c[r] - lo) / (hi - lo)))) * px
        rows += [line] * py
    W, H = len(db) * px, len(freqs) * py
    data = base64.b64encode(png(W, H, rows)).decode()
    w, h = max(W + 140, 760), H + 150
    ix, iy = 80, 90
    body = text(32, 40, title, 20, weight=800) + text(32, 64, sub, 13, MUTED, 500)
    body += f'<image x="{ix}" y="{iy}" width="{W}" height="{H}" href="data:image/png;base64,{data}"/>'
    for f in range(fmin, fmax + 1, 2000):
        y = iy + (fmax - f) / fstep * py + py / 2
        body += f'<line x1="{ix - 6}" y1="{y}" x2="{ix}" y2="{y}" stroke="{INK}"/>' + text(ix - 10, y + 4, f"{f // 1000}k", 11, INK, 500, "end", True)
    dur = len(samples) * 1000 / fs
    for ms in range(0, int(dur) + 1, 50):
        x = ix + ms / hop_ms * px
        if x > ix + W:
            break
        body += f'<line x1="{x}" y1="{iy + H}" x2="{x}" y2="{iy + H + 6}" stroke="{INK}"/>' + text(x, iy + H + 22, f"{ms}", 11, INK, 500, "middle", True)
    body += text(ix + W, iy + H + 42, "ms", 11, MUTED, 600, "end", True)
    for ms, lab, col in marks:
        x = ix + ms / hop_ms * px
        body += text(x, iy - 8, lab, 12, col, 800, "middle", True)
    save(name, svg(w, h, body, title))


# ---------------------------------------------------------------------------- 6. latency budget

def latency(delivered_ms):
    w, h = 1120, 300
    body = text(32, 44, "Where the time goes (estimate from the timings, not a measurement)", 20, weight=800)
    rows = [("v1: 60 ms symbols, wait for silence", [("tick", 16, MUTED), ("S", 60, SYM_COLORS[0]), ("S", 60, SYM_COLORS[1]), ("S", 60, SYM_COLORS[2]), ("quiet", 30, RED), ("tap+main", 21, INK)]),
            ("now: 40 ms symbols, early delivery", [("tick", 16, MUTED), ("S", 40, SYM_COLORS[0]), ("S", 40, SYM_COLORS[1]), ("S", 40, SYM_COLORS[2]), ("tap+main", 21, INK)])]
    scale = 3.2
    for r, (name, parts) in enumerate(rows):
        y = 100 + r * 80
        body += text(32, y - 10, name, 14, INK, 700)
        x = 32
        for lab, ms, col in parts:
            body += f'<rect x="{x}" y="{y}" width="{ms * scale - 2}" height="34" rx="5" fill="{col}"/>'
            if ms * scale > 40:
                body += text(x + ms * scale / 2, y + 22, lab, 11, "#fff", 700, "middle", True)
            x += ms * scale
        total = sum(p[1] for p in parts)
        body += text(x + 12, y + 23, f"≈ {total} ms", 16, INK, 800, mono=True)
    body += text(32, 256, "tick = the firmware reacts on its next 16 ms tick; tap+main = one 1024-sample audio buffer at 48 kHz plus the hop to the main thread.", 12, MUTED, 500)
    body += text(32, 276, f"v1 waited for two quiet windows after the code; now the last symbol is accepted after two stable windows ({delivered_ms:.0f} ms after the onset in the animation).", 12, MUTED, 500)
    save("latency.svg", svg(w, h, body, "Latency budget"))


# ---------------------------------------------------------------------------- main

def main():
    os.makedirs(AUDIO, exist_ok=True)
    for s, (a, b) in enumerate(SYMBOLS):
        write_wav(f"symbol-{s}.wav", silence(100) + tone_pair(a, b, 600) + silence(100))
    for name in ("heartbeat", "handleDown", "handleUp", "tap.orange"):
        write_wav(f"msg-{name.replace('.', '-')}.wav", message(name))
        slow = message(name, slow=8)[::4]           # tones are below 2.4 kHz now: 12 kHz is plenty
        write_wav(f"msg-{name.replace('.', '-')}-slow.wav", slow, FS // 4)
    pipeline()
    spectrum_plan()
    timeline()
    found, delivered = decoder_animation()
    real, fs = read_wav("real-heartbeat.wav")
    spectrogram(real, fs, 10000, 21000, 125, 2.5, 10, "A real heartbeat, recorded from the jack",
                "EP-2350 → 3.5 mm → USB-C dongle → Mac, 48 kHz. Colour: level from −80 dBFS (paper) to the peak (ink).",
                "spectrogram-real.svg")
    latency(delivered)
    print("decoded in the animation:", found, "delivered at", delivered, "ms")


if __name__ == "__main__":
    main()
