// Shared helpers for the mic's LEDs and small deterministic effects.

export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
/** 0 → 1 while t goes from a to b, clamped. */
export const seg = (t, a, b) => clamp((t - a) / (b - a));
export const easeInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
export const easeOut = (x) => 1 - Math.pow(1 - x, 3);
/** Stable pseudo-random number in [0, 1) for an integer seed. */
export const hash = (i) => {
  const x = Math.sin(i * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
};

const GLYPHS = 'abcdefghijklmnopqrstuvwxyz#%&*+=/<>{}01';
/** A "decoding" glyph for character slot `i` at animation tick `tick`. */
export const glyph = (i, tick) => GLYPHS[Math.floor(hash(i * 13 + tick) * GLYPHS.length)];

/** KITT sweep: one red LED running up and down (0..3), `step` is any integer. */
export const kitt = (step) => [0, 1, 2, 3, 2, 1][((step % 6) + 6) % 6];

/**
 * Light LEDs in every given root (mic SVGs and status islands share the r1..r4 / w1..w4 classes).
 * red: 4-bit mask (bit 0 = r1), white: 4-bit mask (bit 0 = w1, the top LED = 1 in binary).
 */
export function ledDriver(roots) {
  const pick = (cls) => roots.filter(Boolean).flatMap((r) => [...r.querySelectorAll(cls)]);
  const red = [1, 2, 3, 4].map((n) => pick(`.r${n}`));
  const white = [1, 2, 3, 4].map((n) => pick(`.w${n}`));
  let last = -1;
  return (redMask, whiteMask = 0) => {
    const key = redMask | (whiteMask << 4);
    if (key === last) return;
    last = key;
    for (let k = 0; k < 4; k++) {
      red[k].forEach((el) => el.classList.toggle('on', !!(redMask & (1 << k))));
      white[k].forEach((el) => el.classList.toggle('on', !!(whiteMask & (1 << k))));
    }
  };
}

export const prefersReducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
