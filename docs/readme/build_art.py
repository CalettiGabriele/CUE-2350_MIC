#!/usr/bin/env python3
"""Builds the animated SVG illustrations of the README ("Chapter 8" identity).

Every scene is a looping timeline: the mic's LEDs, the status island and the texts are driven
by the same clock, with SMIL animations (they play inside <img>, so on GitHub too). Fonts are
the app's own WOFF2 files (Barlow, IBM Plex Mono, SIL OFL), embedded as data URIs.

usage: python3 docs/readme/build_art.py      (writes docs/readme/*.svg)
"""
import base64
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")

INK, PAPER, ORANGE, RED = "#1A1A1A", "#EDEDE8", "#F05A28", "#E3242B"
MUTED, RULE, BAR = "#8C8C88", "#C9C9C3", "#5E5E5B"
RED_OFF, WHITE_OFF = "#5B2B28", "#6E6E6A"
EASE = "0.22 1 0.36 1"        # power3.out: everything that moves settles softly
LINEAR = "0 0 1 1"


# ---------------------------------------------------------------------------- fonts

def font_css(families):
    rules = []
    for family, weight, name in families:
        with open(os.path.join(FONTS, name), "rb") as f:
            data = base64.b64encode(f.read()).decode()
        rules.append(f"@font-face{{font-family:'{family}';font-weight:{weight};"
                     f"src:url(data:font/woff2;base64,{data}) format('woff2');}}")
    return "".join(rules)


ALL_FONTS = [
    ("Barlow", 600, "barlow-latin-600-normal.woff2"),
    ("Barlow", 800, "barlow-latin-800-normal.woff2"),
    ("Barlow", 900, "barlow-latin-900-normal.woff2"),
    ("Plex", 500, "ibm-plex-mono-latin-500-normal.woff2"),
    ("Plex", 600, "ibm-plex-mono-latin-600-normal.woff2"),
]

STYLE = """
.d{font-family:Barlow,'Helvetica Neue',Arial,sans-serif;}
.m{font-family:Plex,Menlo,monospace;letter-spacing:.14em;text-transform:uppercase;}
"""


def svg(width, height, body, fonts=ALL_FONTS, title=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
            f'width="{width}" height="{height}" role="img" aria-label="{title}">'
            f'<title>{title}</title><style>{font_css(fonts)}{STYLE}</style>{body}</svg>\n')


# ---------------------------------------------------------------------------- SMIL helpers

def _fmt(x):
    return f"{x:.4f}".rstrip("0").rstrip(".") if isinstance(x, float) else str(x)


def tween(attr, frames, period, ease=EASE, once=False):
    """Eased animation through (time, value) keyframes over `period` seconds."""
    if frames[0][0] != 0:
        frames = [(0, frames[0][1])] + frames
    if frames[-1][0] < period:
        frames = frames + [(period, frames[-1][1])]
    times = ";".join(_fmt(t / period) for t, _ in frames)
    values = ";".join(str(v) for _, v in frames)
    splines = ";".join(ease if a[1] != b[1] else LINEAR for a, b in zip(frames, frames[1:]))
    repeat = 'fill="freeze"' if once else 'repeatCount="indefinite"'
    return (f'<animate attributeName="{attr}" dur="{period}s" {repeat} calcMode="spline" '
            f'keyTimes="{times}" values="{values}" keySplines="{splines}"/>')


def steps(attr, frames, period, once=False):
    """Discrete animation: (time, value) holds until the next time."""
    if frames[0][0] != 0:
        frames = [(0, frames[0][1])] + frames
    compact = [frames[0]]
    for t, v in frames[1:]:
        if v != compact[-1][1]:
            compact.append((t, v))
    if len(compact) == 1:
        return ""
    times = ";".join(_fmt(t / period) for t, _ in compact)
    values = ";".join(str(v) for _, v in compact)
    repeat = 'fill="freeze"' if once else 'repeatCount="indefinite"'
    return (f'<animate attributeName="{attr}" dur="{period}s" {repeat} calcMode="discrete" '
            f'keyTimes="{times}" values="{values}"/>')


def rotate(frames, cx, cy, period, ease=EASE):
    """Eased rotation (degrees) around (cx, cy)."""
    if frames[-1][0] < period:
        frames = frames + [(period, frames[-1][1])]
    times = ";".join(_fmt(t / period) for t, _ in frames)
    values = ";".join(f"{a} {cx} {cy}" for _, a in frames)
    splines = ";".join(ease if a[1] != b[1] else LINEAR for a, b in zip(frames, frames[1:]))
    return (f'<animateTransform attributeName="transform" type="rotate" dur="{period}s" '
            f'repeatCount="indefinite" calcMode="spline" keyTimes="{times}" values="{values}" '
            f'keySplines="{splines}"/>')


def visible_between(spans, period, attr="opacity"):
    """1 inside any (start, end) span, 0 elsewhere (discrete)."""
    frames = [(0, 0)]
    for start, end in spans:
        frames += [(start, 1), (end, 0)]
    frames.sort()
    return steps(attr, frames, period)


def fade_between(spans, period, fade=0.25):
    frames = [(0, 0)]
    for start, end in spans:
        frames += [(start, 0), (start + fade, 1), (end - fade, 1), (end, 0)]
    return tween("opacity", sorted(frames), period, ease="0.4 0 0.2 1")


# ---------------------------------------------------------------------------- LED timelines

KITT = [0, 1, 2, 3, 2, 1]
TICK = 0.12


def led_masks(period, phases):
    """phases: list of (start, end, kind, arg) → [(t, mask)] sampled every TICK.
    kind: 'idle' (arg = mask), 'kitt' (arg = white bits), 'think' (arg = white bits),
    'boot', 'count' (arg = list of white values, one per span step)."""
    out = []
    t = 0.0
    while t < period - 1e-9:
        mask = 0
        for start, end, kind, arg in phases:
            if start <= t < end:
                f = int(round((t - start) / TICK))
                if kind == "idle":
                    mask = arg
                elif kind == "kitt":
                    mask = (1 << KITT[f % 6]) | arg
                elif kind == "think":
                    mask = (0b0101 if (f // 2) % 2 == 0 else 0b1010) | arg
                elif kind == "boot":
                    mask = (1 << f) if f < 8 else 0
        out.append((round(t, 3), mask))
        t += TICK
    return out


def led_fills(masks, period, bit, red):
    on, off = (RED if red else "#FFFFFF"), (RED_OFF if red else WHITE_OFF)
    return steps("fill", [(t, on if m & (1 << bit) else off) for t, m in masks], period)


def led_glows(masks, period, bit):
    return steps("opacity", [(t, 1 if m & (1 << bit) else 0) for t, m in masks], period)


# ---------------------------------------------------------------------------- the mic

def mic(x, y, scale, period, masks, handle_frames=None, press=None, tag="CUE-2350", uid="a"):
    """The EP-2350 FX-MIC redrawn as flat vector art (style homage, same drawing as the app).
    `press`: {"orange"|"white"|"grey": [(t, dx)]} slides a side button in."""
    press = press or {}
    ink = f'stroke="{INK}" stroke-width="3" stroke-linejoin="round"'
    handle_anim = rotate(handle_frames, 20, 150, period) if handle_frames else ""
    parts = [f'<g transform="translate({x} {y}) scale({scale})">',
             f'<defs><pattern id="grille-{uid}" width="22" height="22" patternUnits="userSpaceOnUse" x="57" y="41">'
             f'<circle cx="11" cy="11" r="6.5" fill="#2E2E2C"/></pattern>'
             f'<filter id="glow-{uid}" x="-1" y="-1" width="3" height="3"><feGaussianBlur stdDeviation="6"/></filter></defs>',
             # handle (rotates around its pivot while held)
             f'<g transform="rotate(-12 20 150)">{handle_anim}'
             f'<rect x="-46" y="46" width="132" height="214" rx="14" fill="{ORANGE}" {ink}/></g>',
             # curly cable
             f'<path d="M200 540 v18 c-40 0 -40 22 0 22 c40 0 40 22 0 22 c-40 0 -40 22 0 22 c40 0 40 22 0 22 '
             f'c-40 0 -40 22 0 22 c40 0 40 22 0 22 c-40 0 -40 22 0 22 v40" fill="none" stroke="{INK}" '
             f'stroke-width="5" stroke-linecap="round"/>']
    for name, fill, by, bh in [("orange", ORANGE, 78, 74), ("white", "#F7F7F3", 206, 62), ("grey", "#A3A39E", 392, 62)]:
        anim = tween("x", [(t, 344 + dx) for t, dx in press[name]], period) if name in press else ""
        parts.append(f'<rect x="344" y="{by}" width="34" height="{bh}" rx="8" fill="{fill}" {ink}>{anim}</rect>')
    parts += [f'<rect x="40" y="20" width="320" height="520" rx="24" fill="#E6E6E1" {ink}/>',
              f'<path d="M64 20 H336 a24 24 0 0 1 24 24 V318 H40 V44 a24 24 0 0 1 24 -24 Z" fill="#4E4E4B" {ink}/>',
              f'<rect x="57" y="41" width="242" height="264" fill="url(#grille-{uid})"/>',
              '<rect x="316" y="44" width="30" height="258" rx="15" fill="#3A3A38"/>']
    for bit, cy in enumerate([66, 96, 126, 156, 196, 226, 256, 286]):
        red = bit < 4
        glow_color = RED if red else "#FFFFFF"
        parts.append(f'<circle cx="331" cy="{cy}" r="11" fill="{glow_color}" filter="url(#glow-{uid})" opacity="0">'
                     f'{led_glows(masks, period, bit)}</circle>')
        parts.append(f'<circle cx="331" cy="{cy}" r="8" fill="{RED_OFF if red else WHITE_OFF}">'
                     f'{led_fills(masks, period, bit, red)}</circle>')
    parts += [f'<line x1="40" y1="318" x2="360" y2="318" {ink}/>']
    for cx, cy in [(70, 348), (330, 348), (70, 510), (330, 510)]:
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="9" fill="none" stroke="{INK}" stroke-width="2.5"/>'
                     f'<line x1="{cx - 6}" y1="{cy}" x2="{cx + 6}" y2="{cy}" stroke="{INK}" stroke-width="2.5"/>')
    parts += [f'<rect x="130" y="408" width="140" height="40" rx="6" fill="none" stroke="{INK}" stroke-width="2.5"/>',
              f'<text x="200" y="434" text-anchor="middle" class="m" font-weight="600" font-size="15" '
              f'letter-spacing="2" fill="{INK}">{tag}</text>', '</g>']
    return "".join(parts)


# ---------------------------------------------------------------------------- the island

def island(cx, period, open_at, close_at, masks, rows, timer=None, width=420, height=78, flash_at=None):
    """Status island hanging from the top edge: grows out of a notch-sized shape, holds,
    retracts. `rows`: [(start, end, text, color)] for the line under the notch."""
    notch_w, notch_h = 190, 34
    w_frames = [(0, notch_w), (open_at, notch_w), (open_at + 0.45, width), (close_at, width), (close_at + 0.4, notch_w)]
    h_frames = [(0, notch_h), (open_at, notch_h), (open_at + 0.45, height), (close_at, height), (close_at + 0.4, notch_h)]
    x_frames = [(t, cx - w / 2) for t, w in w_frames]
    show = [(open_at, close_at + 0.4)]
    content_spans = [(open_at + 0.3, close_at + 0.1)]
    parts = [f'<g>{steps("opacity", [(0, 0), (open_at, 1), (close_at + 0.4, 0)], period)}',
             f'<rect y="-20" rx="18" fill="#000" width="{notch_w}" height="{notch_h + 20}" x="{cx - notch_w / 2}">'
             f'{tween("width", w_frames, period)}{tween("x", x_frames, period)}'
             f'{tween("height", [(t, h + 20) for t, h in h_frames], period)}</rect>',
             f'<g opacity="0">{fade_between(content_spans, period, fade=0.18)}']
    # LED mirror: two vertical columns in the left wing
    lx, ly = cx - width / 2 + 34, 6
    for bit in range(8):
        col, row = bit // 4, bit % 4
        red = bit < 4
        parts.append(f'<circle cx="{lx + col * 10}" cy="{ly + row * 7.4}" r="2.8" fill="{RED_OFF if red else WHITE_OFF}">'
                     f'{led_fills(masks, period, bit, red)}</circle>')
    if timer:
        for start, end, text in timer:
            parts.append(f'<text x="{cx + width / 2 - 40}" y="22" text-anchor="middle" class="m" font-weight="600" '
                         f'font-size="13" letter-spacing="1" fill="#DADAD6" opacity="0">{visible_between([(start, end)], period)}{text}</text>')
    for start, end, text, color in rows:
        parts.append(f'<text x="{cx}" y="{notch_h + 30}" text-anchor="middle" class="m" font-weight="600" '
                     f'font-size="14" fill="{color}" opacity="0">{visible_between([(start, end)], period)}{text}</text>')
    if flash_at:
        parts.append(f'<rect x="{cx - 70}" y="{notch_h + 37}" width="140" height="2.5" fill="{ORANGE}" opacity="0">'
                     f'{tween("opacity", [(0, 0), (flash_at, 0), (flash_at + 0.1, 1), (flash_at + 0.35, 1), (flash_at + 0.6, 0)], period)}</rect>')
    parts.append('</g></g>')
    return "".join(parts)


# ---------------------------------------------------------------------------- page chrome

def chapter_bar(x, y, number, length, period=None, once_at=0.0):
    """Grey chapter bar with the mono numeral; the rule wipes in once."""
    wipe = tween("width", [(0, 0), (once_at, 0), (once_at + 0.7, length)], once_at + 0.7, once=True)
    return (f'<rect x="{x}" y="{y}" width="92" height="34" fill="{BAR}"/>'
            f'<text x="{x + 46}" y="{y + 23}" text-anchor="middle" class="m" font-weight="600" font-size="15" '
            f'fill="#FFFFFF">(({number}))</text>'
            f'<rect x="{x + 92}" y="{y + 15}" width="0" height="3" fill="{BAR}">{wipe}</rect>')


def kicker(x, y, text, color=MUTED, size=15, anchor="start"):
    return (f'<text x="{x}" y="{y}" class="m" font-weight="500" font-size="{size}" fill="{color}" '
            f'text-anchor="{anchor}">{text}</text>')


def stub(x, y):
    return f'<rect x="{x}" y="{y}" width="36" height="3" fill="{ORANGE}"/>'


def display(x, y, text, size, color=INK, weight=900, anchor="start", extra=""):
    return (f'<text x="{x}" y="{y}" class="d" font-weight="{weight}" font-size="{size}" '
            f'letter-spacing="{-size * 0.035:.1f}" fill="{color}" text-anchor="{anchor}" {extra}>{text}</text>')


def wipe_reveal(uid, x, y, w, h, start, dur=0.8):
    """clipPath whose rect wipes left → right once."""
    anim = tween("width", [(0, 0), (start, 0), (start + dur, w)], start + dur, once=True)
    return f'<clipPath id="{uid}"><rect x="{x}" y="{y}" width="0" height="{h}">{anim}</rect></clipPath>'


def callout(x, y, text, toward, period, spans, side="left"):
    """Orange 'PRESS'-style callout with an arrow, shown during `spans`. `side`: where the
    box's anchor x sits ("left" = box starts at x, "right" = box ends at x); the arrow
    leaves from the edge facing the target."""
    tx, ty = toward
    w = 26 + len(text) * 13.5
    box_x = x if side == "left" else x - w
    edge = box_x + w if tx > box_x + w / 2 else box_x
    return (f'<g opacity="0">{fade_between(spans, period, fade=0.2)}'
            f'<rect x="{box_x}" y="{y - 22}" width="{w}" height="36" fill="{ORANGE}"/>'
            f'<text x="{box_x + w / 2}" y="{y + 2}" text-anchor="middle" class="m" font-weight="600" font-size="16" '
            f'fill="{INK}">{text}</text>'
            f'<line x1="{edge}" y1="{y - 4}" x2="{tx}" y2="{ty}" stroke="{ORANGE}" '
            f'stroke-width="3"/><circle cx="{tx}" cy="{ty}" r="6" fill="{ORANGE}"/></g>')


# ============================================================================ scenes

def button_point(x, y, scale, name):
    """Outer edge centre of a side button, for callout arrows."""
    cy = {"orange": 115, "white": 237, "grey": 423}[name]
    return (round(x + 378 * scale + 4), round(y + cy * scale))


def hero():
    W, H, P = 1600, 900, 8.0
    masks = led_masks(P, [
        (0.0, 0.9, "idle", 0b0010_0010),
        (0.9, 3.7, "kitt", 0b0010_0000),
        (3.7, 4.7, "think", 0b0010_0000),
        (4.7, P, "idle", 0b0010_0010),
    ])
    handle = [(0, -12), (0.75, -12), (0.95, -3), (3.6, -3), (3.8, -12)]
    body = [f'<rect width="{W}" height="{H}" fill="{PAPER}"/>',
            chapter_bar(80, 70, "8", 420),
            kicker(80, 140, "EP–2350 FX–MIC · user guide · unofficial chapter"),
            wipe_reveal("l1", 70, 200, 900, 190, 0.2),
            wipe_reveal("l2", 70, 360, 900, 190, 0.55),
            f'<g clip-path="url(#l1)">{display(76, 352, "talking to", 168)}</g>',
            '<g clip-path="url(#l2)">' + display(76, 512, f"your agent<tspan fill='{ORANGE}'>.</tspan>", 168) + '</g>',
            f'<g opacity="0">{tween("opacity", [(0, 0), (1.1, 0), (1.6, 1)], 1.6, once=True)}',
            display(82, 600, "hold the handle. talk. release.", 40, color=INK, weight=600),
            display(82, 650, "your words land where the cursor is — or in your coding agent.", 30, color=MUTED, weight=600),
            stub(82, 712), kicker(132, 722, "local whisper · local llm · nothing leaves your mac", color=INK),
            f'<rect x="82" y="770" width="330" height="58" fill="{ORANGE}"/>',
            f'<text x="247" y="808" text-anchor="middle" class="m" font-weight="600" font-size="22" fill="{INK}">CUE-2350 MIC</text>',
            kicker(436, 806, "open source · macos", color=MUTED),
            '</g>',
            mic(1090, 150, 0.92, P, masks, handle_frames=handle, uid="h"),
            callout(930, 250, "HOLD + TALK", (1060, 300), P, [(0.6, 3.8)], side="right"),
            island(800, P, 0.9, 5.6, masks, width=440, rows=[
                (0.9, 3.7, "RECORDING · ENHANCED", "#FFFFFF"),
                (3.7, 4.7, "PROCESSING · ENHANCED", "#DADAD6"),
                (4.7, 6.0, "WRITTEN (1.2 S)", "#FFFFFF")],
                timer=[(0.9, 1.9, "0:00"), (1.9, 2.9, "0:01"), (2.9, 3.7, "0:02")], flash_at=4.75)]
    return svg(W, H, "".join(body), title="CUE-2350 MIC — talking to your agent")


def talk():
    W, H, P = 1600, 640, 9.0
    masks = led_masks(P, [(0, 1.0, "idle", 0b0001), (1.0, 4.0, "kitt", 0), (4.0, 4.8, "idle", 0b0001), (4.8, P, "idle", 0b0001)])
    handle = [(0, -12), (0.85, -12), (1.05, -3), (3.9, -3), (4.1, -12)]
    sentence = "refactor the auth middleware and add tests for expired tokens."
    steps_ui = [("01", "hold", 0.8, 1.2), ("02", "talk", 1.2, 3.9), ("03", "release", 3.9, 6.5)]
    body = [f'<rect width="{W}" height="{H}" fill="{PAPER}"/>',
            chapter_bar(80, 60, "8.1", 330),
            display(80, 175, "hold. talk. release.", 76),
            kicker(82, 222, "dictate anywhere on your mac — terminal, editor, browser, chat"),
            mic(120, 270, 0.44, P, masks, handle_frames=handle, uid="t"),
            island(1010, P, 1.0, 5.6, masks, width=400, rows=[
                (1.0, 4.0, "RECORDING · DICTATION", "#FFFFFF"), (4.0, 6.0, "WRITTEN (0.8 S)", "#FFFFFF")],
                timer=[(1.0, 2.0, "0:00"), (2.0, 3.0, "0:01"), (3.0, 4.0, "0:02")], flash_at=4.05)]
    # the three steps, lighting in turn
    for i, (num, word, start, end) in enumerate(steps_ui):
        x = 470 + i * 180
        body.append(f'<rect x="{x}" y="300" width="150" height="3" fill="{RULE}"/>'
                    f'<rect x="{x}" y="300" width="0" height="3" fill="{ORANGE}">'
                    f'{tween("width", [(0, 0), (start, 0), (start + 0.3, 150), (6.5, 150), (6.8, 0)], P)}</rect>'
                    + kicker(x, 336, num, color=MUTED, size=14)
                    + display(x, 382, word, 40, weight=800))
    # the text field the dictation lands in
    body.append(f'<rect x="470" y="430" width="1050" height="130" fill="#FFFFFF" stroke="{RULE}" stroke-width="1.5"/>'
                + kicker(494, 462, "notes.md", color=MUTED, size=13))
    # Barlow SemiBold averages ~0.255 em per character at this tracking (measured in the browser).
    text_w = round(len(sentence) * 38 * 0.255)
    reveal = (f'<clipPath id="tw"><rect x="492" y="472" width="0" height="70">'
              f'{tween("width", [(0, 0), (4.1, 0), (4.9, text_w + 6), (7.8, text_w + 6), (8.1, 0)], P, ease=LINEAR)}</rect></clipPath>')
    body.append(reveal)
    body.append(f'<g clip-path="url(#tw)">{display(494, 524, sentence, 38, weight=600)}</g>')
    caret_x = [(0, 498), (4.1, 498), (4.9, 498 + text_w + 6), (7.8, 498 + text_w + 6), (8.1, 498)]
    body.append(f'<rect x="494" y="492" width="3" height="38" fill="{ORANGE}">{tween("x", caret_x, P, ease=LINEAR)}'
                f'{steps("opacity", [(i * 0.5, 1 - i % 2) for i in range(int(P * 2))], P)}</rect>')
    return svg(W, H, "".join(body), title="Hold the handle, talk, release")


def modes():
    W, H, P = 1600, 640, 9.6
    rows = [("dictate", "as spoken, word for word", "“see you at three”", True),
            ("enhanced", "polished by a local llm", "“See you at 3 p.m.”", True),
            ("command", "voice becomes keystrokes", "“make it a bullet list”", True),
            ("computer use", "coming soon", "—", False)]
    # one press every 2.4 s, cycling the 4 modes
    phases, press = [], []
    for i in range(4):
        start = i * 2.4
        phases.append((start, start + 2.4, "idle", 1 << i))
        press += [(start + 0.05, 0), (start + 0.15, -10), (start + 0.35, 0)]
    masks = led_masks(P, phases)
    body = [f'<rect width="{W}" height="{H}" fill="{PAPER}"/>',
            chapter_bar(80, 60, "8.2", 330),
            display(80, 175, "four modes.", 76),
            kicker(82, 222, "orange button · one red led for each mode"),
            mic(110, 250, 0.44, P, masks, press={"orange": press}, uid="o"),
            callout(330, 262, "PRESS", button_point(110, 250, 0.44, "orange"), P, [(0.0, P)])]
    top = 270
    for i, (name, lead, example, available) in enumerate(rows):
        y = top + i * 88
        active = [(i * 2.4, i * 2.4 + 2.4)]
        body.append(f'<line x1="470" y1="{y}" x2="1520" y2="{y}" stroke="{RULE}" stroke-width="1.5"/>')
        body.append(f'<rect x="470" y="{y + 10}" width="6" height="66" fill="{ORANGE}" opacity="0">{fade_between(active, P, 0.15)}</rect>')
        body.append(kicker(500, y + 50, f"((8.2.{i + 1}))", color=MUTED, size=14))
        color = INK if available else MUTED
        body.append(f'<g opacity="0.45">{steps("opacity", [(0, 0.45)] + [(s, 1) for s, _ in active] + [(e, 0.45) for _, e in active], P)}'
                    + display(640, y + 58, name, 46, color=color, weight=800)
                    + kicker(960, y + 40, lead, color=INK if available else MUTED, size=15)
                    + f'<text x="960" y="{y + 66}" class="d" font-weight="600" font-size="22" fill="{MUTED}">{example}</text>'
                    + '</g>')
    body.append(f'<line x1="470" y1="{top + 4 * 88}" x2="1520" y2="{top + 4 * 88}" stroke="{RULE}" stroke-width="1.5"/>')
    return svg(W, H, "".join(body), title="Four modes on the orange button")


def slots():
    W, H, P = 1600, 640, 9.0
    names = ["/compact", "/clear", "/review", "bug report", "commit message"]
    phases, press = [], []
    for i in range(5):
        start = i * 1.8
        phases.append((start, start + 1.8, "idle", 0b0010 | ((i + 1) << 4)))
        press += [(start + 0.05, 0), (start + 0.15, -10), (start + 0.35, 0)]
    masks = led_masks(P, phases)
    body = [f'<rect width="{W}" height="{H}" fill="{PAPER}"/>',
            chapter_bar(80, 60, "8.3", 330),
            display(80, 175, "fifteen slots.", 76),
            kicker(82, 222, "white button · the white leds count in binary"),
            mic(110, 250, 0.44, P, masks, press={"white": press}, uid="s"),
            callout(330, 312, "PRESS", button_point(110, 250, 0.44, "white"), P, [(0.0, P)])]
    # big binary readout
    for bit in range(4):
        cy = 300 + bit * 62
        frames = [(i * 1.8, "#FFFFFF" if (i + 1) >> bit & 1 else WHITE_OFF) for i in range(5)]
        glow = [(i * 1.8, 1 if (i + 1) >> bit & 1 else 0) for i in range(5)]
        body.append(f'<rect x="478" y="{cy - 28}" width="56" height="56" rx="28" fill="#3A3A38"/>'
                    f'<circle cx="506" cy="{cy}" r="20" fill="#FFFFFF" opacity="0" style="filter:blur(7px)">{steps("opacity", glow, P)}</circle>'
                    f'<circle cx="506" cy="{cy}" r="18" fill="{WHITE_OFF}">{steps("fill", frames, P)}</circle>'
                    + kicker(560, cy + 6, str(1 << bit), color=MUTED, size=14))
    # slot list
    for i, name in enumerate(names):
        y = 290 + i * 62
        active = [(i * 1.8, i * 1.8 + 1.8)]
        body.append(f'<line x1="700" y1="{y - 32}" x2="1520" y2="{y - 32}" stroke="{RULE}" stroke-width="1.5"/>')
        body.append(f'<rect x="700" y="{y - 26}" width="6" height="52" fill="{ORANGE}" opacity="0">{fade_between(active, P, 0.12)}</rect>')
        body.append(kicker(730, y + 6, f"{i + 1:02d}", color=MUTED, size=14))
        body.append(f'<g opacity="0.4">{steps("opacity", [(0, 0.4), (active[0][0], 1), (active[0][1], 0.4)], P)}'
                    + display(800, y + 14, name, 40, weight=800) + '</g>')
    body.append(kicker(1520, 610, "slots change with the app in front · coding agent profile", color=MUTED, size=13, anchor="end"))
    return svg(W, H, "".join(body), title="Fifteen slots on the white button")


def send():
    W, H, P = 1600, 640, 8.0
    masks = led_masks(P, [(0, 1.2, "idle", 0b0011_0010), (1.2, P, "idle", 0b0010)])
    press = [(1.0, 0), (1.1, -12), (1.35, 0)]
    body = [f'<rect width="{W}" height="{H}" fill="{PAPER}"/>',
            chapter_bar(80, 60, "8.4", 330),
            display(80, 175, "send it.", 76),
            kicker(82, 222, "grey button · runs the slot, or presses return"),
            mic(110, 250, 0.44, P, masks, press={"grey": press}, uid="g"),
            callout(330, 410, "PRESS", button_point(110, 250, 0.44, "grey"), P, [(0.4, 1.6)])]
    # terminal, ink register
    tx, ty, tw, th = 470, 260, 1050, 320
    body.append(f'<rect x="{tx}" y="{ty}" width="{tw}" height="{th}" fill="{INK}"/>'
                f'<rect x="{tx}" y="{ty}" width="{tw}" height="38" fill="#262624"/>'
                + kicker(tx + 24, ty + 25, "terminal · coding agent", color="#8C8C88", size=13)
                + ''.join(f'<circle cx="{tx + tw - 30 - i * 22}" cy="{ty + 19}" r="6" fill="#3A3A38"/>' for i in range(3)))
    lines = [(1.2, "› /review", "#FFFFFF", 600, 30),
             (2.0, "● reading 4 changed files", "#8C8C88", 500, 22),
             (2.9, "● 2 suggestions on auth/session.ts", "#8C8C88", 500, 22),
             (3.8, "✓ review ready", ORANGE, 600, 24)]
    for i, (start, text, color, weight, size) in enumerate(lines):
        y = ty + 100 + i * 52
        cid = f"line{i}"
        body.append(f'<clipPath id="{cid}"><rect x="{tx + 30}" y="{y - 34}" width="0" height="48">'
                    f'{tween("width", [(0, 0), (start, 0), (start + 0.45, 980), (6.8, 980), (7.1, 0)], P, ease=LINEAR)}</rect></clipPath>'
                    f'<text x="{tx + 34}" y="{y}" clip-path="url(#{cid})" class="m" font-weight="{weight}" '
                    f'font-size="{size}" letter-spacing="1" style="text-transform:none" fill="{color}">{text}</text>')
    body.append(kicker(1520, 615, "slot 1 on the white leds, then grey: the command is sent", color=MUTED, size=13, anchor="end"))
    return svg(W, H, "".join(body), title="Send the slot with the grey button")


def end_card():
    W, H, P = 1600, 600, 4.32
    masks = led_masks(P, [(0, P, "kitt", 0)])
    body = [f'<rect width="{W}" height="{H}" fill="{INK}"/>',
            kicker(80, 90, "((8)) · end of chapter", color=ORANGE),
            display(76, 250, "cue-2350 mic<tspan fill='" + ORANGE + "'>.</tspan>", 150, color=PAPER),
            kicker(82, 320, "open source · macos · local by design", color="#DADAD6", size=17),
            kicker(82, 380, "unofficial · not affiliated with teenage engineering", color="#8C8C88", size=14)]
    # a row of LEDs running the KITT sweep
    for bit in range(4):
        x = 1310 + bit * 52
        body.append(f'<circle cx="{x}" cy="240" r="18" fill="{RED}" opacity="0" style="filter:blur(8px)">{led_glows(masks, P, bit)}</circle>'
                    f'<circle cx="{x}" cy="240" r="13" fill="{RED_OFF}">{led_fills(masks, P, bit, True)}</circle>')
    # colophon: a hairline, then the author, set like the printer's line of a manual.
    # Everything plays once (it is the last thing on the page) and then stays still.
    name = "gabriele caletti"
    name_w = round(len(name) * 44 * 0.5)       # Barlow ExtraBold ≈ 0.5 em/char at 44px
    body.append(f'<rect x="80" y="440" width="0" height="1.5" fill="#3A3A38">'
                f'{tween("width", [(0, 0), (0.5, 0), (1.3, 1440)], 1.3, once=True)}</rect>')
    body.append(f'<g opacity="0">{tween("opacity", [(0, 0), (1.0, 0), (1.4, 1)], 1.4, once=True)}'
                + kicker(80, 497, "colophon", color=ORANGE, size=15)
                + stub(80, 512)
                + kicker(200, 497, "designed &amp; built by", color="#8C8C88", size=15)
                + '</g>')
    body.append(f'<clipPath id="who"><rect x="196" y="500" width="0" height="80">'
                f'{tween("width", [(0, 0), (1.4, 0), (2.4, name_w + 20)], 2.4, ease=LINEAR, once=True)}</rect></clipPath>'
                f'<g clip-path="url(#who)">{display(198, 560, name, 44, color=PAPER, weight=800)}</g>')
    body.append(f'<g opacity="0">{tween("opacity", [(0, 0), (2.5, 0), (3.0, 1)], 3.0, once=True)}'
                + kicker(1520, 497, "github.com/CalettiGabriele", color="#DADAD6", size=15, anchor="end")
                + kicker(1520, 521, "linkedin.com/in/gabriele-caletti-a952301b6", color="#DADAD6", size=15, anchor="end")
                + kicker(1520, 551, "mit license", color="#8C8C88", size=15, anchor="end")
                + '</g>')
    body.append(f'<rect x="198" y="524" width="4" height="40" fill="{ORANGE}" opacity="0">'
                f'{tween("x", [(0, 198), (1.4, 198), (2.4, 198 + name_w + 4)], 2.4, ease=LINEAR, once=True)}'
                f'{steps("opacity", [(0, 0), (1.4, 1), (2.9, 1), (3.1, 0), (3.3, 1), (3.5, 0), (3.7, 1), (3.9, 0)], 4.2, once=True)}</rect>')
    return svg(W, H, "".join(body), title="CUE-2350 MIC — open source, macOS, local by design. Designed and built by Gabriele Caletti. MIT license.")


def main():
    scenes = {"hero.svg": hero, "talk.svg": talk, "modes.svg": modes, "slots.svg": slots,
              "send.svg": send, "end.svg": end_card}
    for name, build in scenes.items():
        path = os.path.join(HERE, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(build())
        print(f"wrote {os.path.relpath(path, ROOT)} ({os.path.getsize(path) // 1024} KB)")


if __name__ == "__main__":
    main()
