# FXMic firmware (One-Pager 002, ADR-002/003). Runs on the EP-2350 (MicroPython, 64 KB heap).
# Recognises the gestures on the mic and plays one acoustic code (3 symbols, 12-19 kHz) for each.
# The Mac owns mode and slot. Fixed buffers, nothing grows in callbacks.
# Handle release is repeated once (REP ms later) and the heartbeat is never played while the handle
# is held or right after a gesture, so the Mac can always recover a lost release code.
import ui, spl, fx, time
from fxmic_cfg import *

tm = time.ticks_ms
td = time.ticks_diff
ta = time.ticks_add

_q = bytearray(16)
_qh = _qt = 0
_ps = -1          # symbol being played; -1 = idle, 3 = waiting for the gap
_pm = 0
_pt = 0
_hb = 0
_t0 = 0
_pr = [0, 0, 0]   # press time per button (grey, white, orange); 0 = up
_pend = [0, 0, 0]  # release time of a tap waiting for its double tap
_lf = _vf = 0      # long / very long already fired (bit per button)
_hd = False
_hp = 0
_rep = 0          # when to repeat the handle release code (0 = none)
_la = 0           # last gesture time
_chord = False
_sc = _hs = _hl = _lsh = _pollt = 0
_hf = False
_on = False
_r = -1           # red LEDs: -1 = all (free), 0..3 = one channel
_sl = 0           # white LEDs: slot number in binary, 0 = none


def _leds():
    for i in range(4):
        ui.led_level(i, 1.0 if _r < 0 or _r == i else 0)
        ui.led_level(4 + i, 1.0 if (_sl >> i) & 1 else 0)


def _page(k, b):
    # The Mac cannot talk to the mic over the jack: the mic pages its own LEDs like the app pages
    # channels (orange) and slots (white): tap = next, double tap = previous, long white = none.
    global _r, _sl
    if b == 2 and k < 2:
        d = 1 if k == 0 else -1
        _r = (0 if d > 0 else LEDCH - 1) if _r < 0 else (_r + d) % LEDCH
    elif b == 1:
        _sl = 0 if k == 2 else (_sl + (1 if k == 0 else -1)) % (LEDSL + 1)
    else:
        return
    _leds()


def _emit(i):
    global _qt, _la
    if i:
        _la = tm()
    n = (_qt + 1) & 15
    if n != _qh:
        _q[_qt] = i
        _qt = n


def _btn(b, act, t):
    global _chord, _lf, _vf
    m = 1 << b
    if act:
        _pr[b] = t
        _lf &= ~m
        _vf &= ~m
        if b == 0 and _hd:
            _chord = True
            _emit(16)
        return
    st = _pr[b]
    if not st:
        return
    _pr[b] = 0
    if b == 0 and _chord:
        _chord = False
        return
    _vf &= ~m
    if _lf & m:
        _lf &= ~m
        return
    if td(t, st) > TAP or (_hd and b):
        return
    p = _pend[b]
    if p and td(t, p) <= DBL:
        _pend[b] = 0
        _page(1, b)
        _emit(7 + b)
    else:
        _pend[b] = t


def _hnd(act, t):
    global _hd, _hp, _rep, _la
    if act == _hd:
        return
    _hd = act
    _la = t
    if act:
        _hp = t
        _rep = 0
        _emit(1)
        return
    _emit(2)
    _rep = ta(t, REP)


def _shake(t):
    global _sc, _lsh, _hs, _hl, _hf
    s = ui.shaker()
    if s > HOLDT:
        if not _hs:
            _hs = t
        _hl = t
        if not _hf and td(t, _hs) >= HOLD:
            _hf = True
            _emit(18)
    elif td(t, _hl) > HOLDTOL:
        _hs = 0
        _hf = False
    if s > SHK:
        _sc += 1
        if _sc >= SHKN and td(t, _lsh) >= SHKCD:
            _lsh = t
            _sc = 0
            _emit(17)
    else:
        _sc = 0


def _tick(t):
    global _lf, _vf, _rep
    if _rep and td(t, _rep) >= 0:
        _rep = 0
        if not _hd:
            _emit(2)
    for b in (0, 1, 2):
        st = _pr[b]
        if st and not (b == 0 and _chord):
            m = 1 << b
            d = td(t, st)
            if not (_lf & m) and d >= LONG:
                _lf |= m
                _page(2, b)
                _emit(10 + b)
            if (_lf & m) and not (_vf & m) and not _hd and d >= VLONG:
                _vf |= m
                _emit(13 + b)
        p = _pend[b]
        if p and td(t, p) > DBL:
            _pend[b] = 0
            _page(0, b)
            _emit(4 + b)


def _play(t):
    global _ps, _pm, _pt, _qh
    if _ps == 3:
        if td(t, _pt) < 0:
            return
        _ps = -1
    if _ps < 0:
        if _qh == _qt:
            return
        _pm = _q[_qh]
        _qh = (_qh + 1) & 15
        _ps = 0
        _pt = t
    if td(t, _pt) < 0:
        return
    spl.trigger(-1, CODES[_pm * 3 + _ps], True)
    _pt = ta(_pt, SYM + GAP if _ps == 2 else SYM)
    _ps += 1


def _factory():
    # Escape hatch: orange held in the first seconds hands the mic back to the factory logic.
    stop()
    import fxmic_factory


def _cb(m):
    global _pollt, _hb
    t = m >> 16
    if t == 3:
        n = tm() | 1
        _tick(n)
        if td(n, _pollt) >= POLL:
            _pollt = n
            _shake(n)
        _play(n)
        if _ps < 0 and _qh == _qt and not _hd and td(n, _hb) >= HB and td(n, _la) >= QUIET:
            _hb = n
            _emit(0)
        if _pr[2] and td(n, _t0) < 8000 and td(n, _pr[2]) >= 1500:
            stop()
            try:
                import micropython
                micropython.schedule(_run_factory, 0)
            except Exception:
                _factory()
    elif t == 1 or t == 2:
        v = m & 0xFFFF
        n = tm() | 1
        if v == 4:
            _hnd(t == 2, n)
        elif v < 3:
            _btn(v, t == 1, n)
    elif t == 4 and (m & 0xFFFF) == 1:
        import vfs, rp2
        b = rp2.Flash()
        vfs.umount('/fat')
        vfs.mount(vfs.VfsFat(b), '/fat')


def _run_factory(_):
    import fxmic_factory


def _reset():
    global _qh, _qt, _ps, _lf, _vf, _hd, _chord, _hp, _rep, _la, _sc, _hs, _hl, _hf, _t0, _hb
    _qh = _qt = 0
    _ps = -1
    _lf = _vf = 0
    _hd = _chord = _hf = False
    _hp = _rep = _la = _sc = _hs = _hl = 0
    for i in range(3):
        _pr[i] = _pend[i] = 0
    _t0 = tm() | 1
    _hb = _t0


def version():
    return VERSION


def resume():
    # Back from the USB agent: same sounds, clean voice, first red LED on, our callback.
    global _on
    _reset()
    fx.load_preset(-1)
    ui.led_control(0)
    _leds()
    ui.callback(_cb)
    _on = True


def pause():
    global _on
    ui.callback(0)
    _on = False


def stop():
    pause()
    ui.led_control(1)


def start():
    for i in range(4):
        f = open('/fat/.fxmic/s%d.wav' % i, 'rb')
        ok = spl.load_wav(i, f)
        f.close()
        if not ok:
            raise OSError('fxmic symbol %d' % i)
    resume()
