import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { initMagic } from './magic.js';
import { islandDriver } from './island.js';
import { kitt, ledDriver, prefersReducedMotion } from './leds.js';

gsap.registerPlugin(ScrollTrigger);
const reduced = prefersReducedMotion();

// ------------------------------------------------------------------ hero
function initHero() {
  const hero = document.querySelector('[data-hero]');
  if (!hero) return;
  const title = hero.querySelector('[data-hero-title]');
  const ins = hero.querySelectorAll('[data-hero-in]');
  const art = hero.querySelector('[data-hero-art]');

  if (!reduced) {
    // the title types itself, the orange caret follows
    const chars = [];
    title.querySelectorAll('.ht-line').forEach((line) => {
      [...line.childNodes].forEach((node) => {
        if (node.nodeType !== 3) { if (!node.classList.contains('caret')) { chars.push(node); node.style.display = 'none'; } return; }
        const frag = document.createDocumentFragment();
        for (const ch of node.textContent) {
          const s = document.createElement('span');
          s.textContent = ch; s.style.display = 'none';
          frag.appendChild(s); chars.push(s);
        }
        node.replaceWith(frag);
      });
    });
    const tl = gsap.timeline({ delay: 0.35 });
    tl.from(art, { y: 80, opacity: 0, duration: 1.2, ease: 'power3.out' }, 0);
    chars.forEach((c, i) => tl.call(() => { c.style.display = ''; }, null, 0.25 + i * 0.055));
    tl.from(ins, { y: 22, opacity: 0, duration: 0.8, stagger: 0.08, ease: 'power3.out' }, 0.25 + chars.length * 0.055);

    // scrolling out: the copy lifts faster than the mic
    gsap.to(title, { yPercent: -18, opacity: 0.25, ease: 'none', scrollTrigger: { trigger: hero, start: 'top top', end: 'bottom top', scrub: true } });
    gsap.to(art, { yPercent: -10, rotate: -4, ease: 'none', scrollTrigger: { trigger: hero, start: 'top top', end: 'bottom top', scrub: true } });
  }

  // ambient loop, as on a MacBook: the island grows out of the notch while you talk,
  // thinks, says "written" and retracts into the notch
  const mic = hero.querySelector('.hero-mic');
  const mac = hero.querySelector('.hero-mac');
  const island = islandDriver(mac);
  const leds = ledDriver([mic, island.el]);
  leds(0b0010);
  if (reduced) return;

  let visible = true, timers = [], ivl = 0;
  const clear = () => { timers.forEach(clearTimeout); timers = []; clearInterval(ivl); };
  const at = (ms, fn) => timers.push(setTimeout(fn, ms));
  function cycle() {
    clear();
    if (!visible) return;
    let step = 0, start = 0;
    at(1400, () => {
      mic.classList.add('held', 'talking');
      start = performance.now();
      island.set({ open: true, cls: 'rec', text: 'recording · enhanced', time: '0:00' });
      ivl = setInterval(() => {
        leds(1 << kitt(step++));
        island.set({ open: true, cls: 'rec', text: 'recording · enhanced', time: `0:0${Math.floor((performance.now() - start) / 1000)}` });
      }, 125);
    });
    at(4300, () => {
      clearInterval(ivl);
      mic.classList.remove('held', 'talking');
      island.set({ open: true, cls: 'think', text: 'thinking' });
      let k = 0;
      ivl = setInterval(() => leds(k++ % 2 ? 0b0101 : 0b1010), 110);
    });
    at(5400, () => {
      clearInterval(ivl);
      leds(0b0010);
      island.set({ open: true, cls: 'done', text: 'written ✓ 1.0 s' });
    });
    at(7300, () => island.set({ open: false }));
    at(8800, cycle);
  }
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (visible) cycle();
    else { clear(); mic.classList.remove('held', 'talking'); island.set({ open: false }); leds(0b0010); }
  }).observe(hero);
}

// ------------------------------------------------------------------ the idea: words light up as you read
function initIdea() {
  const words = document.querySelectorAll('[data-idea-text] .iw');
  if (!words.length || reduced) return;
  gsap.to(words, {
    opacity: 1, stagger: 0.12, ease: 'none',
    scrollTrigger: { trigger: '[data-idea-text]', start: 'top 82%', end: 'bottom 45%', scrub: 0.4 },
  });
}

// ------------------------------------------------------------------ generic reveals + counters
function initReveals() {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('is-in');
      io.unobserve(e.target);
    }
  }, { rootMargin: '0px 0px -12% 0px' });
  document.querySelectorAll('[data-reveal]').forEach((el) => io.observe(el));

  const nums = document.querySelectorAll('[data-count]');
  const cio = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      cio.unobserve(e.target);
      const el = e.target, to = +el.dataset.count, from = +el.dataset.from, pre = el.dataset.prefix || '';
      const tag = el.parentElement.querySelector('.scouter-tag');
      if (reduced) { el.textContent = pre + to; tag?.classList.add('on'); continue; }
      if (el.hasAttribute('data-scouter')) { scouter(el, pre, to, tag); continue; }
      const o = { v: from };
      el.textContent = pre + from;
      gsap.to(o, { v: to, duration: from > to ? 1.8 : 1.3, ease: 'power3.out', onUpdate: () => { el.textContent = pre + Math.round(o.v); } });
    }
  }, { rootMargin: '0px 0px -15% 0px' });
  nums.forEach((n) => cio.observe(n));
}

// "it's over 9000!": the reading climbs faster and faster, the scouter goes haywire, then it settles
function scouter(el, pre, to, tag) {
  const show = (txt) => { el.textContent = txt; el.dataset.text = txt; };
  const o = { v: 0 };
  show(pre + 0);
  gsap.timeline()
    .to(o, { v: to * 0.89, duration: 1.2, ease: 'power2.in', onUpdate: () => show(pre + Math.round(o.v)) })
    .call(() => {
      el.classList.add('glitch');
      let n = 0;
      const id = setInterval(() => {
        // readings jump around (four digits, so the number never leaves its column)
        const r = Math.floor(8000 + Math.random() * 1999);
        show(n % 5 === 4 ? 'ERR' : pre + r);
        if (++n > 16) {
          clearInterval(id);
          el.classList.remove('glitch');
          show(pre + to);
          el.classList.remove('pop'); void el.offsetWidth; el.classList.add('pop');
          tag?.classList.add('on');
        }
      }, 55);
    });
}

// ------------------------------------------------------------------ get it: the orange floods in
function initGet() {
  const fill = document.querySelector('[data-get-fill]');
  if (fill && !reduced) {
    gsap.fromTo(fill, { '--r': '0%' }, {
      '--r': '150%', ease: 'none',
      scrollTrigger: { trigger: '[data-get]', start: 'top 95%', end: 'top 15%', scrub: 0.5 },
    });
  }
  const dlg = document.querySelector('[data-teaser]');
  const video = dlg?.querySelector('video');
  document.querySelector('[data-teaser-open]')?.addEventListener('click', () => {
    dlg.showModal();
    video.play().catch(() => {});
  });
  const close = () => { video.pause(); dlg.close(); };
  dlg?.querySelector('[data-teaser-close]').addEventListener('click', close);
  dlg?.addEventListener('click', (e) => { if (e.target === dlg) close(); });
  dlg?.addEventListener('close', () => video.pause());
}

// ------------------------------------------------------------------ top bar appears after the hero
function initTopBar() {
  const bar = document.querySelector('[data-topbar]');
  const hero = document.querySelector('[data-hero]');
  if (!bar || !hero) return;
  ScrollTrigger.create({
    trigger: hero, start: 'bottom 80px',
    onEnter: () => bar.classList.add('show'),
    onLeaveBack: () => bar.classList.remove('show'),
  });
}

initHero();
initIdea();
initMagic();
initReveals();
initGet();
initTopBar();
