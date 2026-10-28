# FXMic firmware (One-Pager 002, ADR-002/003). Runs on the EP-2350 (MicroPython, 64 KB heap).
# Recognises the gestures on the mic and plays one acoustic code (3 symbols, 12-19 kHz) for each.
# The Mac owns mode and slot. Fixed buffers, nothing grows in callbacks.
# Handle release is repeated once (REP ms later) and the heartbeat is never played while the handle
# is held or right after a gesture, so the Mac can always recover a lost release code.
# Orange sends the page the red LEDs land on (page.1..4), not 'next': the Mac goes to that channel. The
# number of bound pages is kept in /fat/.fxmic/n (written only without USB) so it survives a power cycle;
# until a count has been saved all four pages are allowed (the app says when a page has no channel).
# On batteries: SLEEP ms without any touch -> LEDs off and no heartbeat (power save, still listening);
# OFF ms later still untouched -> ui.shutdown(). On USB power the mic never sleeps or shuts down.
import ui, spl, fx, time, micropython
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
_r = -1           # red LEDs: channel page lit (0..3); -1 = free, all four lit
_n = 0            # channel pages bound (0..4), counted from the long presses of orange
_sl = 0           # white LEDs: slot number in binary (0..15), 0 = none
_fr = -1          # recording sweep frame on show
_bf = 8           # boot sweep: frame being shown, 8 = done
_act = 0          # last touch: handle, button or shake
_sv = False       # power save on
_dn = False       # the page count has to be saved
_SW = (0, 1, 2, 3, 2, 1)


def _leds():
    for i in range(4):
        ui.led_level(i, 1.0 if _r < 0 or _r == i else 0)
        ui.led_level(4 + i, 1.0 if (_sl >> i) & 1 else 0)


def _page(k, b, i):
    # The Mac cannot talk to the mic over the jack, so the mic pages its own LEDs the way the app
    # pages channels (orange) and slots (white), and tells the Mac the page it landed on (returned
    # message id). Orange: tap next, double tap previous, long = a page is bound (a new one while
    # there is room), very long = all unbound. White: tap next, double tap previous, long = none;
    # 0..15 in binary. Returns the message id to send.
    global _r, _n, _sl, _dn
    if b == 2:
        if k == 0 and _n:
            _r = 0 if _r < 0 else (_r + 1) % _n
            i = 19 + _r
        elif k == 1 and _n:
            _r = _n - 1 if _r < 0 else (_r - 1) % _n
            i = 19 + _r
        elif k == 2:
            if _n < 4:
                _r = _n
                _n += 1
                _dn = True
            elif _r < 0:
                _r = _n - 1
        elif k == 3:
            _r = -1
            _n = 0
            _dn = True
        else:
            return i
    elif b == 1 and k < 3:
        _sl = 0 if k == 2 else (_sl + (1 if k == 0 else -1)) % 16
    else:
        return i
    _leds()
    return i


def _save(_):
    try:
        f = open('/fat/.fxmic/n', 'w')
        f.write(str(_n))
        f.close()
    except OSError:
        pass


def _touch(t):
    global _act, _sv
    _act = t
    if _sv:
        _sv = False
        if _bf == 8:
            _leds()


def _idle(t):
    # Called every tick. Power save and shutdown only on batteries; USB power restarts the count.
    global _act, _sv
    if _hd:
        _act = t
        return
    d = td(t, _act)
    if d < SLEEP or (_sv and d < SLEEP + OFF):
        return
    if ui.get_vbus() > 4.0:
        _touch(t)
    elif not _sv:
        _sv = True
        for i in range(8):
            ui.led_level(i, 0)
    else:
        ui.shutdown()


def _anim(t):
    # Same animations as the app drives over USB: boot pass down the 8 LEDs, red sweep while the
    # handle is held. (Processing and confirmation come from the Mac: not possible over the jack.)
    global _bf, _fr
    if _bf < 8:
        if td(t, _t0) >= _bf * LEDFR:
            for i in range(8):
                ui.led_level(i, 1.0 if i == _bf else 0)
            _bf += 1
            if _bf == 8:
                _leds()
    elif _hd:
        f = (td(t, _hp) // LEDFR) % 6
        if f != _fr:
            _fr = f
            for i in range(4):
                ui.led_level(i, 1.0 if _SW[f] == i else 0)


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
    _touch(t)
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
        _emit(_page(1, b, 7 + b))
    else:
        _pend[b] = t


def _hnd(act, t):
    global _hd, _hp, _rep, _la, _fr
    if act == _hd:
        return
    _hd = act
    _la = t
    _touch(t)
    if act:
        _hp = t
        _rep = 0
        _fr = -1
        _emit(1)
        return
    _emit(2)
    _rep = ta(t, REP)
    if _bf == 8:
        _leds()


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
        _touch(t)
        _sc += 1
        if _sc >= SHKN and td(t, _lsh) >= SHKCD:
            _lsh = t
            _sc = 0
            _emit(17)
    else:
        _sc = 0


def _tick(t):
    global _lf, _vf, _rep
    _anim(t)
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
                _emit(_page(2, b, 10 + b))
            if (_lf & m) and not (_vf & m) and not _hd and d >= VLONG:
                _vf |= m
                _emit(_page(3, b, 13 + b))
        p = _pend[b]
        if p and td(t, p) > DBL:
            _pend[b] = 0
            _emit(_page(0, b, 4 + b))


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
    global _pollt, _hb, _dn
    t = m >> 16
    if t == 3:
        n = tm() | 1
        _tick(n)
        if td(n, _pollt) >= POLL:
            _pollt = n
            _shake(n)
        _play(n)
        _idle(n)
        if _dn and not _hd and not (_pr[0] or _pr[1] or _pr[2]) and _ps < 0 and _qh == _qt and td(n, _la) >= QUIET:
            _dn = False
            if ui.get_vbus() < 4.0:
                micropython.schedule(_save, 0)
        if _ps < 0 and _qh == _qt and not _hd and not _sv and td(n, _hb) >= HB and td(n, _la) >= QUIET:
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
    global _qh, _qt, _ps, _lf, _vf, _hd, _chord, _hp, _rep, _la, _sc, _hs, _hl, _hf, _t0, _hb, _bf, _act, _sv
    _qh = _qt = 0
    _ps = -1
    _lf = _vf = 0
    _hd = _chord = _hf = False
    _hp = _rep = _la = _sc = _hs = _hl = 0
    for i in range(3):
        _pr[i] = _pend[i] = 0
    _t0 = tm() | 1
    _hb = _t0
    _bf = 0
    _act = _t0
    _sv = False


def version():
    return VERSION


def resume():
    # Back from the USB agent: same sounds, clean voice, first red LED on, our callback.
    global _on
    _reset()
    fx.load_preset(-1)
    ui.led_control(0)
    ui.callback(_cb)
    _on = True


def sync(n, r, sl):
    # The app's channel count, position (-1 = free) and slot, sent over USB when it hands the mic back.
    global _n, _r, _sl
    _n = n
    _r = r
    _sl = sl
    resume()


def pause():
    global _on
    ui.callback(0)
    _on = False


def stop():
    pause()
    ui.led_control(1)


def start():
    global _n
    for i in range(4):
        f = open('/fat/.fxmic/s%d.wav' % i, 'rb')
        ok = spl.load_wav(i, f)
        f.close()
        if not ok:
            raise OSError('fxmic symbol %d' % i)
    try:
        f = open('/fat/.fxmic/n')
        v = int(f.read())
        f.close()
    except (OSError, ValueError):
        v = 4   # never counted: the app may already have channels, so allow all four pages
    _n = v if 0 <= v <= 4 else 4
    resume()
