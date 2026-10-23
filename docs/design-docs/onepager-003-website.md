# One-Pager 003 — CUE-2350 MIC presentation website

> Date: 2026-10-19 (rev. 2: shorter content, scroll-driven animations) · Status: **Implemented in `site/` (v1), to be reviewed** · Open points in §9
> Note (2026-10-23): the orange button's modes were replaced by channels and the voice command (One-Pager 004). The site is updated; the scenes and numbers quoted below describe v1.
> References: `README.md`, `docs/GESTURES.md`, `videos/fxmic-bridge-teaser/frame.md` and `BRIEF.md` ("Chapter 8" visual identity), `app/Sources/FXMicBridge/Theme.swift` (tokens), `docs/CREDITS.md`

## 1. Goals, in order of priority
1. **Sell the idea.** Visitors should think *"I want it"* before they understand every detail: a beautiful object that becomes the voice remote of your AI agent.
2. **Explain features and benefits briefly.** Three or four concepts, not the full list of gestures: you talk and it types, the AI tidies the text or turns it into actions, a button sends commands to the agent, everything stays on the Mac.
3. **Send people to GitHub** for details, download and installation. The site does not duplicate the documentation.

**Audience:** Mac developers working with Claude Code or other agents; teenage engineering hardware fans. Language: **English**.

**What differs from the README:** the README explains everything; the site tells a story. No tables of gestures, thresholds, profiles or build commands: each section has **one title, one sentence and one animation**.

## 2. Stack and hosting (decided)
- **Astro** with static output, **plain CSS** with variables.
- **GSAP** with **ScrollTrigger** and **SplitText** for the scroll animations. It is the same library as the teaser, free including the plugins, about 60 KB compressed in all. Native CSS scroll-driven animations are not yet reliable in every browser.
- **Lenis** (about 4 KB) for smooth scrolling, optional: to be judged in testing, because some users find it unnatural.
- **Barlow** and **IBM Plex Mono** fonts self-hosted as woff2.
- Deploy on **Hostinger**: `dist/` into `public_html`, plus an `.htaccess` for HTTPS, compression and caching.
- Code in `site/` inside this repo.

## 3. The page
The site is **a single page**, plus `/legal` and a 404. The story follows a funnel: hook → magic → benefits → GitHub.

| # | Section | Goal | Copy (draft) | What happens on scroll |
|---|---|---|---|---|
| 0 | **Hero** | sell | **talk to your agent.** · *your EP-2350 FX-MIC, now a voice remote for your Mac.* · **Get it on GitHub** button · *open source · macOS · local AI* | The mic enters from below. The orange cursor types the title. The mic's dot grille "breathes" slowly, as if waiting for the voice. |
| 1 | **The idea** | sell | *your agent is a conversation. stop typing it.* · *squeeze the handle, say what you want, let go.* | A giant sentence in Barlow 900 builds word by word as you scroll; the words already read fade. |
| 2 | **The magic** (pinned sequence, see 3.1) | sell + explain | four scenes, one sentence each | The section stays pinned on screen and scrolling moves the story forward: voice → text → AI → action → agent. |
| 3 | **Why you'll love it** | explain the benefits | three points (see 3.2) | Three blocks enter staggered; each has a small mic animation. |
| 4 | **By the numbers** | explain | **4** modes · **15** slots per app · **+9000** aura points · **0** words sent to the cloud | The numbers count up as they enter; the mic's LEDs light up in rhythm. |
| 5 | **Get it** | send to GitHub | *open source. free. yours.* · requirements in one line: *Mac with Apple silicon · macOS 14+ · EP-2350 FX-MIC* · large **Get it on GitHub** button · secondary link **Watch the teaser** | The background goes from paper to orange as you arrive; the button is the only element in the foreground. |
| — | **Footer** | — | author, GitHub, LinkedIn, MIT, credits, full non-affiliation notice | static, dark background |

The **GitHub button** appears in three places: the hero, section 5 and the top bar (which appears only after the hero).

### 3.1 "The magic": the pinned sequence
It is the heart of the site and of the wow effect. On the left the **mic**, on the right a stylised **screen** (a paper window with a 1px rule, then a dark terminal). The section stays pinned for about 4 screen heights and each scene takes up a stretch of scrolling.

| Scene | Title · sentence | Mic | Screen | Where you see the AI |
|---|---|---|---|---|
| **A. hold. talk.** | *hold the handle and talk.* | The handle goes down; the red LEDs start the stepped KITT sweep; the black island drops from the top with REC and the timer. | The **grille dots** come off the mic like a sound wave and fly towards the screen. | The voice becomes visible matter. |
| **B. the AI listens.** | *your words, written where your cursor is.* | LEDs in "thinking" (1+3 / 2+4 alternating); island on *thinking*. | The dots arrive and **turn into letters**: the raw text decodes character by character (random Plex Mono letters that settle into Barlow). | Transcription: from sound to text. |
| **C. the AI cleans up.** | *enhanced mode turns rambling into writing.* | Orange pressed: red LED 2 lights up. | The raw text *"ehm so the the login page crashes when like you hit enter twice"* **rewrites itself**: the filler words are struck through and vanish, punctuation and capitals appear, the rest slides into place. Result: *"The login page crashes when you press Enter twice."* | It is the most "magic" moment: the text changes before your eyes. |
| **D. one button to the agent.** | *pick a skill. press grey. done.* | White pressed three times: the white LEDs count in binary up to 3, and `/review` appears beside them. Grey pressed. | The window becomes a **terminal**: `> /review` is typed, the agent answers with lines that appear one at a time and a final `✓`. | The AI acts: the voice becomes work done. |

A thin **progress bar** in Plex Mono (`((8.1)) ((8.2)) ((8.3)) ((8.4))`) shows where you are in the story and echoes the chapter numbering.

**On mobile** the sequence stays pinned, with a compact layout: a small mic next to the caption and the terminal below. It is simpler to maintain than five separate blocks and works well in testing. With *reduce motion* the sequence is not pinned: all captions are listed next to the terminal in its final state.

### 3.2 The three benefits
| Title | Sentence | Animation |
|---|---|---|
| **/ a button you can feel** | *a physical handle keeps you in the flow. no shortcuts to remember.* | The handle goes down and back up as you pass. |
| **/ your voice stays home** | *speech-to-text and the language model run on your Mac. audio is never saved.* | A sound-wave dot tries to leave its box and bounces back inside. |
| **/ every app, its own skills** | *buttons follow the app in front: /review in the terminal, "rewrite as email" everywhere else.* | The slot names change as the icon of the app in front changes. |

The *nothing permanent on the mic* point stays as a line below the three blocks: it is reassurance, not a selling point.

## 4. Visual identity and "AI magic"

### 4.1 What stays the same
The rules come from the app and the teaser (`Theme.swift`, `frame.md`):
- **Colours:** `--ink #1A1A1A`, `--paper #EDEDE8`, `--accent #F05A28` (the only accent), `--led-red #E3242B` only for LEDs and recording; `--muted #8C8C88`, `--rule #C9C9C3`, `--bar #5E5E5B`, `--grille #3A3A38`.
- **Registers:** *paper* as the main one; *dark* for the terminal and the footer; *orange* for the "Get it" close.
- **Typography:** Barlow for all text, **lowercase** and large titles (weights 800–900, negative tracking); IBM Plex Mono uppercase only for labels, chapter numbers and the terminal.
- **Flat surfaces:** 1px rules, grey chapter bar, `/` marker. No shadows, purple gradients or frosted glass.

### 4.2 How the magic comes across without betraying the style
The magic does not come from generic "AI" effects (neon gradients, blue particles, glow), which would clash with the guide's aesthetic. It comes from **transformation**: seeing the voice become text and the text become action.

- **The mic's grille as a particle field.** The grille dots are the most recognisable element of the object: they become a sound wave, then letters. A single `<canvas>` with a few hundred dots, in the mic's colours.
- **Text decoding.** Words appear as random Plex Mono letters that settle into the right word (SplitText plus a scramble effect). It is the visual sign of "the machine is understanding".
- **Live rewriting.** In scene C the text corrects itself: it is the clearest picture of what the model does.
- **Orange cursor** that types titles and sentences, as in the teaser.
- **Stepped LEDs** (about 8 steps per second), never faded: it is the rhythm of the real hardware.
- **"Thinking" state:** the only concession to glow, a soft orange halo behind the island while the AI is processing.

### 4.3 Motion rules
- Every animation is tied to scrolling (you can go back and watch it again), except the small idle loops.
- Decisive, short easings (`power3`, `expo`), as in the teaser; no cartoon bounces.
- **`prefers-reduced-motion`:** no pinned sequence and no particles; each scene shows its final state at once.
- Animations only use `transform` and `opacity`, and the canvas stops when it leaves the screen.

## 5. Assets
**Already available:**
- animatable vector mic: `videos/fxmic-bridge-teaser/assets/fxmic-device.svg` (to be made addressable: LEDs, buttons, handle, grille dots);
- the README illustrations in `docs/readme/` as a reference;
- teaser video `videos/fxmic-bridge-teaser/renders/video.mp4`, for the *Watch the teaser* link (opens in an overlay, recompressed);
- woff2 fonts and the app icon.

**To be produced:**
- **Open Graph image** 1200×630 (mic, *talk to your agent.*, wordmark);
- favicon from the app icon;
- final copy for the sentences (drafts in section 3).

App screenshots are no longer needed: the island and the terminal are redrawn as animated components.

## 6. Non-functional requirements
- **Weight:** page under 400 KB on first load (JS included); the video loads only if you open it.
- **Performance:** 60 fps animations on a MacBook Air and a recent iPhone; Lighthouse ≥ 90 on mobile.
- **Responsive:** from 360 px, with the "magic" sequence not pinned on mobile (see 3.1).
- **Accessibility:** each scene's text is real HTML (readable by screen readers and search engines), not canvas only; AA contrast; reduced motion respected.
- **SEO:** title, description, Open Graph and Twitter, `sitemap.xml`, `robots.txt`, `SoftwareApplication` structured data.
- **Site privacy:** no cookies, no third-party scripts, no remote fonts, no embeds. No cookie banner; a short note in `/legal`.
- **Legal notice:** *"unofficial · not affiliated with teenage engineering"* visible already in the hero, full notice in the footer.

## 7. File structure
```
site/
  astro.config.mjs
  package.json
  public/
    fonts/  media/  favicon.svg  og.png
    .htaccess  robots.txt
  src/
    styles/tokens.css       # colours, typography, spacing
    styles/global.css
    layouts/Base.astro      # <head>, top bar, footer
    components/
      Mic.astro             # mic SVG with addressable LEDs, buttons, handle
      Island.astro          # black island (REC / thinking / written)
      Screen.astro          # paper window that becomes a terminal
      ChapterProgress.astro # ((8.1)) … ((8.4))
      GitHubButton.astro
    sections/               # Hero, Idea, Magic, Benefits, Numbers, GetIt
    scripts/
      scroll.js             # ScrollTrigger: section timelines
      grille.js             # dot canvas: sound wave → letters
      decode.js             # text decoding and rewriting effect
      leds.js               # stepped LEDs
    pages/  index.astro  legal.astro  404.astro
```

## 8. Alternatives considered
- **A full chaptered landing page like the README** (rev. 1 of this document): rejected, too much text for a site that must first sell the idea.
- **Video instead of animations:** simpler, but it does not follow scrolling, weighs more and does not adapt to the screen.
- **Three.js / WebGL with a 3D mic:** a great effect, but heavy, far from the guide's flat style and slow to build.
- **Native CSS scroll-driven animations:** light, but support is still incomplete and there is little control over long sequences.

## 9. Open points
1. **Domain:** which name, and whether it is already on Hostinger.
2. **Download:** should the button go to the repo's main page (proposal) or to the Releases page? There is no binary today: a real "download" needs a `.dmg`, with the Gatekeeper warning or Apple notarisation.
3. **Copy:** are the tone and the drafts in section 3 right, in particular *"talk to your agent."* as the title?
4. **Scene C example:** is a bug report fine, or would you prefer an example closer to Claude (for example a prompt)?
5. **Lenis:** smooth scrolling yes or no? To be decided by looking at the prototype.
6. **Analytics:** none (proposal) or a cookie-free tool such as Plausible?

## 10. Plan
1. Review of this document and answers to the open points.
2. Astro skeleton, tokens, fonts, layout, addressable mic SVG.
3. Prototype of the "magic" sequence (scenes A–D) on desktop: it is the riskiest part, so it is validated first.
4. Hero, idea, benefits, numbers, close; mobile version and reduced motion.
5. SEO, Open Graph, `/legal`, 404, `.htaccess`; performance and accessibility check.
6. First deploy on Hostinger.
