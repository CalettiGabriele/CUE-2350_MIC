# CUE-2350 MIC — website

The presentation site of CUE-2350 MIC: one scroll-driven page, plus `/legal` and a 404.
Design and content: [One-Pager 003](../docs/design-docs/onepager-003-website.md).

Self-contained: nothing here is imported from the app; fonts, media and the mic drawing are copied in.

## Stack

- [Astro](https://astro.build) with static output, plain CSS with tokens (`src/styles/tokens.css`).
- [GSAP](https://gsap.com) + ScrollTrigger for the scroll animations.
- No cookies, no analytics, no third-party requests.

## Develop

```bash
cd site
npm install
npm run dev        # http://localhost:4321
```

## Build

```bash
npm run build
```

The site defaults to `https://cue-2350.lofai.xyz`; set `SITE_URL=https://other-domain` to override it. `SITE_URL` drives canonical links, Open Graph URLs, structured data, `robots.txt` and the sitemap. The output is in `dist/`.

## Deploy on Hostinger

1. Build with the real `SITE_URL`.
2. Upload the **contents** of `dist/` (including the hidden `.htaccess`) to `public_html/`, with the
   File Manager or over FTP/SFTP.
3. Enable the free SSL certificate in hPanel: `.htaccess` redirects every request to HTTPS.

## Where things are

| Path | What |
|---|---|
| `src/site.config.ts` | name, links, disclaimer |
| `src/sections/` | the page sections, top to bottom |
| `src/components/Mic.astro` | the FX-MIC drawing with addressable LEDs, buttons, handle, grille |
| `src/scripts/magic.js` | the pinned "magic" story: every frame is a function of the scroll position |
| `src/scripts/main.js` | hero, reveals, counters, the orange finale, top bar, teaser dialog |
| `public/media/` | teaser video (re-encoded) and poster |
| `public/og.png`, `favicon.svg`, `apple-touch-icon.png` | share image and icons |

With *reduce motion* turned on, the story is not pinned: every caption is listed next to the final terminal.

## Search and accessibility

- **Titles, description, Open Graph, structured data** (WebSite, SoftwareApplication, FAQPage): `src/layouts/Base.astro`, copy in `src/site.config.ts`. The FAQ text (`src/faq.ts`, shown on `/faq`) is both the visible FAQ and the FAQPage data: keep it in step with the README.
- **One address**: `.htaccess` redirects `www` and plain http to `https://<domain>`, so search engines see a single site.
- **Accessibility**: skip link, one `h1`, landmarks, links that open a new tab are announced, reduced motion respected. Known trade-off: the brand orange and grey keep the original look, so small orange/grey text on paper is below WCAG AA contrast (2.9:1). Audit with axe-core after changes.
- **After going live**: verify the domain in Google Search Console and Bing Webmaster Tools, submit `/sitemap-index.xml`, and link the site from the GitHub repo (About → Website), the README and your profiles.
