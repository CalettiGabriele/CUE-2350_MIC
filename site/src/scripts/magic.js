// "The magic": a pinned stage whose every frame is a pure function of the scroll position `t`
// (0 → END, one unit per scene), so the story scrubs back and forth without drift.
//   A 0–1 hold. talk.   B 1–2 the ai listens.   C 2–3 the ai cleans up.
//   D 3–4 send it.      E 4–5 one button, any skill.
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { islandDriver } from './island.js';
import { seg, easeInOut, easeOut, hash, glyph, kitt, ledDriver, prefersReducedMotion } from './leds.js';

gsap.registerPlugin(ScrollTrigger);

const END = 5.25;
const SLOTS = ['/compact', '/clear', '/review'];
const TYPE_A = 1.05, TYPE_B = 1.85; // raw dictation types in during B

export function initMagic() {
  const section = document.getElementById('magic');
  const stage = section?.querySelector('[data-magic]');
  if (!stage) return;

  const $ = (s) => stage.querySelector(s);
  const $$ = (s) => [...stage.querySelectorAll(s)];
  const mic = $('.magic-mic');
  const mac = $('.magic-mac');
  const island = islandDriver(mac);
  const caps = $$('[data-cap]');
  const steps = $$('[data-step]');
  const dots = [...mic.querySelectorAll('.mic-dot')];
  const btn = {
    orange: mic.querySelector('.mic-btn-orange'),
    white: mic.querySelector('.mic-btn-white'),
    grey: mic.querySelector('.mic-btn-grey'),
  };
  const in1 = $('[data-in1]'), in2 = $('[data-in2]');
  const cur1 = $('[data-cur1]'), cur2 = $('[data-cur2]');
  const cmd = $('[data-cmd]');
  const lines = $$('[data-l]');
  const canvas = $('[data-fx]');
  const ctx = canvas.getContext('2d');
  const leds = ledDriver([mic, island.el]);

  // tokens of the raw dictation, with what the model does to each one
  const toks = $$('.tk').map((el) => ({
    el,
    t: el.dataset.t,
    to: el.dataset.to ?? null,
    drop: el.hasAttribute('data-drop'),
    w: 0, wTo: 0, start: 0,
  }));
  let nChars = 0;
  for (const k of toks) { k.start = nChars; nChars += k.t.length; }
  const dropOrder = toks.filter((k) => k.drop);
  const swapOrder = toks.filter((k) => k.to);

  // ---------------------------------------------------------------- layout (on load / resize)
  let W = 0, H = 0, dpr = 1;
  let src = [];   // grille dot centres, stage coordinates
  let dst = [];   // character centres of the raw text, stage coordinates
  let parts = []; // particles: { s, d, dep, arr, ink, seed }
  let pr = 3;

  function measure() {
    const r = stage.getBoundingClientRect();
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = r.width; H = r.height;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);

    src = dots.map((d) => {
      const b = d.getBoundingClientRect();
      return { x: b.left + b.width / 2 - r.left, y: b.top + b.height / 2 - r.top };
    });
    pr = Math.max(2, (dots[0].getBoundingClientRect().width || 6) * 0.42);

    // full raw text, natural widths: where every character will sit
    for (const k of toks) { k.el.textContent = k.t; k.el.style.width = ''; k.el.style.opacity = ''; k.el.style.color = ''; }
    dst = [];
    for (const k of toks) {
      const b = k.el.getBoundingClientRect();
      k.w = b.width;
      const cw = b.width / k.t.length;
      for (let j = 0; j < k.t.length; j++) dst.push({ x: b.left - r.left + cw * (j + 0.5), y: b.top - r.top + b.height / 2, space: k.t[j] === ' ' });
    }
    for (const k of toks) {
      if (!k.to) continue;
      k.el.textContent = k.to;
      k.wTo = k.el.getBoundingClientRect().width;
      k.el.textContent = k.t;
    }

    // two particles per visible character, each leaving from a scattered grille dot
    parts = [];
    const chars = dst.map((d, g) => ({ ...d, g })).filter((d) => !d.space);
    const n = chars.length * 2;
    for (let i = 0; i < n; i++) {
      const c = chars[i >> 1];
      parts.push({
        s: src[(i * 37) % src.length],
        si: (i * 37) % src.length,
        d: c,
        dep: 0.16 + 0.74 * (i / n) + hash(i) * 0.04,
        arr: TYPE_A + (TYPE_B - TYPE_A) * (c.g / nChars) - 0.02,
        ink: i % 6 === 0,
        seed: hash(i + 7),
      });
    }
    // when each grille dot first lets a particle go (it flashes orange)
    dotDep = new Array(src.length).fill(9);
    for (const p of parts) dotDep[p.si] = Math.min(dotDep[p.si], p.dep);
  }
  let dotDep = [];

  // ---------------------------------------------------------------- frame
  function setIsland(cls, text, time = '') {
    island.set({ open: !!text, cls, text, time });
  }
  const press = (el, t, a) => el.classList.toggle('pressed', t >= a && t < a + 0.06);
  const show = (el, t, a, dur = 0.08) => {
    const k = easeOut(seg(t, a, a + dur));
    el.style.opacity = k;
    el.style.transform = `translateY(${(1 - k) * 8}px)`;
  };

  function render(t) {
    // captions + progress
    caps.forEach((c, i) => {
      const lo = i === 0 ? -9 : i - 0.12, hi = i === caps.length - 1 ? 99 : i + 1 - 0.12;
      const k = Math.min(seg(t, lo, lo + 0.12), 1 - seg(t, hi, hi + 0.12));
      c.style.opacity = k;
      c.style.transform = `translateY(${(1 - k) * (t < i + 0.5 ? 18 : -18)}px)`;
      c.style.visibility = k < 0.01 ? 'hidden' : 'visible';
    });
    const scene = Math.min(4, Math.floor(t));
    steps.forEach((s, i) => { s.style.setProperty('--p', seg(t, i, i + 1)); s.classList.toggle('on', i === scene); });

    // ---- mic: handle, buttons, LEDs
    mic.classList.toggle('held', t > 0.12 && t < 0.95);
    press(btn.orange, t, 2.08);
    press(btn.grey, t, 3.1);
    press(btn.white, t, 4.1); if (t >= 4.22 && t < 4.28) btn.white.classList.add('pressed'); if (t >= 4.34 && t < 4.4) btn.white.classList.add('pressed');
    if (t >= 4.5 && t < 4.56) btn.grey.classList.add('pressed');

    const thinking = (x) => (Math.floor(x * 18) % 2 ? 0b0101 : 0b1010);
    let red = 0b0001, white = 0;
    if (t > 0.12 && t < 0.95) red = 1 << kitt(Math.floor(seg(t, 0.12, 0.95) * 30));
    else if (t >= 0.95 && t < 1.9) red = thinking(t);
    else if (t >= 2.1) red = 0b0010;
    if (t >= 2.25 && t < 2.92) red = thinking(t);
    const slot = t >= 4.62 ? 0 : t >= 4.34 ? 3 : t >= 4.22 ? 2 : t >= 4.1 ? 1 : 0;
    white = slot;
    leds(red, white);

    // grille: a wave of orange flashes as the voice leaves the mic
    for (let i = 0; i < dots.length; i++) {
      const lit = t >= dotDep[i] - 0.02 && t < dotDep[i] + 0.16;
      if (dots[i]._lit !== lit) { dots[i]._lit = lit; dots[i].classList.toggle('lit', lit); }
    }

    // ---- island
    if (t < 0.12) setIsland('', '');
    else if (t < 0.95) setIsland('rec', 'recording · dictate', `0:0${Math.min(4, Math.floor(seg(t, 0.12, 0.95) * 5))}`);
    else if (t < 1.9) setIsland('think', 'transcribing');
    else if (t < 2.08) setIsland('done', 'written ✓ 0.9 s');
    else if (t < 2.25) setIsland('done', 'mode 2/4 · enhanced');
    else if (t < 2.92) setIsland('think', 'enhanced · thinking');
    else if (t < 3.1) setIsland('done', 'written ✓ 1.2 s');
    else if (t < 3.35) setIsland('done', 'sent ⏎');
    else if (t < 4.08) setIsland('', '');
    else if (t < 4.5) setIsland('', slot ? `slot ${slot} · ${SLOTS[slot - 1]}` : 'slot');
    else if (t < 5.05) setIsland('done', 'run · /review');
    else setIsland('', '');

    // ---- terminal: raw dictation decodes in (B)
    const shown = seg(t, TYPE_A, TYPE_B) * nChars;
    const tick = Math.floor(t * 60);
    const cleaning = t >= 2.25;
    for (const k of toks) {
      if (!cleaning) {
        let s = '';
        for (let j = 0; j < k.t.length; j++) {
          const g = k.start + j;
          if (g < shown - 4 || t >= TYPE_B) s += k.t[j];
          else if (g < shown) s += k.t[j] === ' ' ? ' ' : glyph(g, tick);
        }
        k.el.textContent = s;
        k.el.style.width = '';
        k.el.style.opacity = '';
        k.el.style.color = '';
        k.el.classList.remove('strike');
      }
    }

    // ---- terminal: the model rewrites it (C)
    if (cleaning) {
      dropOrder.forEach((k, j) => {
        const a = 2.27 + j * 0.05;
        const s = seg(t, a, a + 0.16), c = easeInOut(seg(t, a + 0.2, a + 0.38));
        k.el.textContent = k.t;
        k.el.classList.add('strike');
        k.el.style.setProperty('--s', s);
        k.el.style.width = `${k.w * (1 - c)}px`;
        k.el.style.opacity = 1 - c;
        k.el.style.color = s > 0 ? 'var(--muted)' : '';
      });
      swapOrder.forEach((k, j) => {
        const a = 2.5 + j * 0.06;
        const m = seg(t, a, a + 0.22);
        let s;
        if (m <= 0) s = k.t;
        else if (m >= 1) s = k.to;
        else {
          const target = m < 0.5 ? k.t : k.to;
          const keep = Math.floor(seg(m, 0.5, 1) * target.length);
          s = [...target].map((ch, i) => (i < keep || ch === ' ' ? ch : glyph(k.start + i, tick))).join('');
        }
        k.el.textContent = s;
        k.el.style.width = `${k.w + (k.wTo - k.w) * easeInOut(m)}px`;
        k.el.style.color = m > 0 && m < 1 ? 'var(--accent)' : '';
        k.el.style.opacity = '';
      });
      toks.filter((k) => !k.drop && !k.to).forEach((k) => { k.el.textContent = k.t; k.el.style.width = ''; k.el.style.opacity = ''; k.el.style.color = ''; });
    }
    cur1.classList.toggle('on', t > 1.0 && t < 3.1);
    in1.classList.toggle('focus', t > 1.0 && t < 3.1);
    in1.classList.toggle('sent', t >= 3.12);

    // ---- agent works (D), then the /review slot (E)
    show(lines[0], t, 3.3); show(lines[1], t, 3.48); show(lines[2], t, 3.68);
    show(in2, t, 4.0);
    const typed = Math.floor(seg(t, 4.52, 4.62) * SLOTS[2].length);
    cmd.textContent = SLOTS[2].slice(0, typed);
    cur2.classList.toggle('on', t >= 4.0 && t < 4.64);
    in2.classList.toggle('focus', t >= 4.0 && t < 4.64);
    in2.classList.toggle('sent', t >= 4.64);
    show(lines[3], t, 4.72); show(lines[4], t, 4.92);

    drawParticles(t);
  }

  // ---- the voice, made visible: grille dots fly to the screen and land as letters
  function drawParticles(t) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (t < 0.1 || t > TYPE_B + 0.2) return;
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (t < p.dep) continue;
      const fade = 1 - seg(t, p.arr, p.arr + 0.06);
      if (fade <= 0) continue;
      const u = easeInOut(seg(t, p.dep, p.arr));
      const { s, d } = p;
      // cubic Bézier: up and out of the mic, a loop over the gap, down onto the character
      const c1x = s.x + (d.x - s.x) * 0.25, c1y = s.y - 120 - p.seed * 160;
      const c2x = s.x + (d.x - s.x) * 0.7, c2y = d.y - 80 - p.seed * 120;
      const v = 1 - u;
      let x = v * v * v * s.x + 3 * v * v * u * c1x + 3 * v * u * u * c2x + u * u * u * d.x;
      let y = v * v * v * s.y + 3 * v * v * u * c1y + 3 * v * u * u * c2y + u * u * u * d.y;
      // a sound wave riding on the path, fading out as it lands
      y += Math.sin(u * Math.PI * 5 + i * 0.9) * 26 * Math.sin(u * Math.PI);
      const r = pr * (0.7 + 0.5 * Math.sin(u * Math.PI)) * (0.6 + 0.4 * fade);
      ctx.globalAlpha = fade;
      ctx.fillStyle = p.ink ? '#1a1a1a' : '#f05a28';
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  // ---------------------------------------------------------------- wiring
  const state = { t: 0 };
  if (prefersReducedMotion()) {
    section.classList.add('static');
    measure();
    render(END);
    return;
  }

  const go = () => {
    measure();
    render(state.t);
    gsap.to(state, {
      t: END,
      ease: 'none',
      onUpdate: () => render(state.t),
      scrollTrigger: {
        trigger: stage,
        start: 'top top',
        end: () => `+=${window.innerHeight * (window.innerWidth < 860 ? 4.2 : 5)}`,
        pin: true,
        scrub: 0.6,
        invalidateOnRefresh: true,
      },
    });
    ScrollTrigger.addEventListener('refreshInit', () => { for (const k of toks) { k.el.textContent = k.t; k.el.style.width = ''; } });
    ScrollTrigger.addEventListener('refresh', () => { measure(); island.refresh(); render(state.t); });
  };
  (document.fonts?.ready ?? Promise.resolve()).then(go);
}
