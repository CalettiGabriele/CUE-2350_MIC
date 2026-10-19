// Driver for the notch island in MacScreen.astro. Mirrors the app (HUD.swift):
// closed = the bare notch; open = notch + 2 wings wide (or wider for long text), notch + one row tall.

export function islandDriver(mac) {
  const el = mac.querySelector('[data-island]');
  const text = el.querySelector('[data-island-text]');
  const time = el.querySelector('[data-island-time]');
  const css = getComputedStyle(mac);
  const px = (v) => parseFloat(css.getPropertyValue(v)) || 0;
  let last = '';

  function width() {
    const nw = px('--nw'), wing = px('--wing');
    // text row: dot + gap + text + side padding
    return Math.max(nw + 2 * wing, text.scrollWidth + 6 + 8 + 34);
  }

  /** state: { open, cls: 'rec'|'think'|'done'|'', text, time } */
  function set({ open = false, cls = '', text: t = '', time: tm = '' }) {
    const key = `${open}|${cls}|${t}|${tm}`;
    if (key === last) return;
    const textChanged = t !== text.textContent;
    last = key;
    el.classList.toggle('rec', cls === 'rec');
    el.classList.toggle('think', cls === 'think');
    el.classList.toggle('done', cls === 'done');
    mac.classList.toggle('mic-on', cls === 'rec');
    if (open) {
      if (t) text.textContent = t;
      time.textContent = tm;
      el.classList.add('open');
      el.style.width = `${width()}px`;
      if (textChanged && t) { text.classList.remove('flash'); void text.offsetWidth; text.classList.add('flash'); }
    } else {
      el.classList.remove('open');
      el.style.width = '';
    }
  }

  return { el, set, refresh: () => { last = ''; } };
}
