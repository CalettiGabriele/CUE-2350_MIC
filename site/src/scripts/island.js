// Driver for the notch island in MacScreen.astro. Mirrors the app (HUD.swift, One-Pager 006):
// closed = the bare notch; open = notch + 2 wings wide (or wider for a long title), notch + one
// row tall (two with a detail); folded = recording with the title row gone, a little thicker than
// the notch. The pips are lit by ledDriver (leds.js), which shares the r1..r4 / w1..w4 classes.

const svg = (body, view = 16, extra = '') => `<svg viewBox="0 0 ${view} ${view}" ${extra}aria-hidden="true">${body}</svg>`;
const stroke = 'fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"';

// An app (a terminal session) and the AI mark (a voice command): white glyphs, no orange.
const ICONS = {
  app: svg(`<rect x="1.5" y="2.5" width="13" height="11" rx="3" ${stroke}/><path d="M5 6.5l2.2 1.7L5 9.9M8.6 10h2.6" ${stroke}/>`),
  ai: svg('<path d="M6.5 2.5l1.1 3.1 3.1 1.1-3.1 1.1-1.1 3.1-1.1-3.1-3.1-1.1 3.1-1.1z" fill="currentColor"/><path d="M12 9.5l.6 1.6 1.6.6-1.6.6-.6 1.6-.6-1.6-1.6-.6 1.6-.6z" fill="currentColor"/>'),
};

// Right wing glyphs: the check draws itself in a ring; slot kinds are ▶ run, ✎ template, ✦ LLM.
const GLYPHS = {
  check: svg('<circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M6 10.5l3 3 5-6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>', 20, 'class="ni-check" '),
  run: svg('<path d="M5 3l8 5-8 5z" fill="currentColor"/>'),
  template: svg(`<path d="M3 13l.6-2.8 7.2-7.2a1.4 1.4 0 0 1 2 2l-7.2 7.2z" ${stroke}/>`),
  llm: ICONS.ai,
};

/** Right wing content. `right`: { type: 'time'|'text'|'check'|'run'|'template'|'llm', text }. */
function rightHtml(right, folded, rec) {
  let html = '';
  // recording with the title row gone: a red dot before the time
  if (folded && rec) html += '<i class="ni-rec"></i>';
  if (right?.type && GLYPHS[right.type]) html += GLYPHS[right.type];
  if (right?.text) html += `<span>${right.text}</span>`;
  return html;
}

export function islandDriver(mac) {
  const el = mac.querySelector('[data-island]');
  const title = el.querySelector('[data-island-title]');
  const detail = el.querySelector('[data-island-detail]');
  const icon = el.querySelector('[data-island-icon]');
  const rightEl = el.querySelector('[data-island-right]');
  const css = getComputedStyle(mac);
  const num = (v, d) => parseFloat(css.getPropertyValue(v)) || d;
  let last = '';

  function width(folded) {
    const s = num('--s', 0.75), nw = num('--nw', 120), wing = 72 * s;
    if (folded) return nw + 2 * wing;
    const row = title.scrollWidth + (icon.innerHTML ? (16 + 8) * s : 0);
    return Math.min(Math.max(nw + 2 * wing, Math.max(row, detail.scrollWidth) + 48 * s), nw + 2 * wing + 120);
  }

  /**
   * state: { open, folded, rec, icon: 'app'|'ai'|'', title, detail, right: { type, text } }
   * `rec` = recording (the mic is held). `folded` only means something while open.
   */
  function set(state = {}) {
    const key = JSON.stringify(state);
    if (key === last) return;
    last = key;
    const { open = false, folded = false, rec = false, icon: ic = '', title: t = '', detail: d = '', right = null } = state;
    mac.classList.toggle('mic-on', rec);
    if (open) {
      if (t) title.textContent = t;
      detail.textContent = d;
      icon.innerHTML = ICONS[ic] || '';
      rightEl.innerHTML = rightHtml(right, folded, rec);
      el.classList.add('open');
      el.classList.toggle('folded', folded);
      el.classList.toggle('has-detail', !!d);
      el.style.width = `${width(folded)}px`;
    } else {
      el.classList.remove('open', 'folded');
      el.style.width = '';
    }
  }

  return { el, set, refresh: () => { last = ''; } };
}
