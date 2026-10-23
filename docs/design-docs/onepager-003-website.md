# One-Pager 003 — Sito web di presentazione di CUE-2350 MIC

> Data: 2026-10-19 (rev. 2: contenuto più sintetico, animazioni allo scorrimento) · Stato: **Implementato in `site/` (v1), da rivedere** · Punti aperti in §9
> Nota (2026-10-23): le modalità dell'arancione sono state sostituite dai canali e dal comando vocale (One-Pager 004). Il sito è aggiornato; le scene e i numeri citati qui sotto descrivono la v1.
> Riferimenti: `README.md`, `docs/GESTURES.md`, `videos/fxmic-bridge-teaser/frame.md` e `BRIEF.md` (identità visiva "Chapter 8"), `app/Sources/FXMicBridge/Theme.swift` (token), `docs/CREDITS.md`

## 1. Obiettivi, in ordine di priorità
1. **Vendere l'idea.** Chi arriva deve pensare *"lo voglio"* prima ancora di capire tutti i dettagli: un oggetto bellissimo che diventa il telecomando vocale del tuo agente AI.
2. **Spiegare in breve funzionalità e vantaggi.** Tre o quattro concetti, non l'elenco completo dei gesti: parli e scrive, l'AI sistema il testo o lo trasforma in azioni, un pulsante manda i comandi all'agente, tutto resta sul Mac.
3. **Portare su GitHub** per i dettagli, il download e l'installazione. Il sito non duplica la documentazione.

**Pubblico:** sviluppatori su Mac che lavorano con Claude Code o altri agenti; appassionati di hardware teenage engineering. Lingua **inglese**.

**Cosa cambia rispetto al README:** il README spiega tutto; il sito racconta. Niente tabelle di gesti, soglie, profili o comandi di build: ogni sezione ha **un titolo, una frase e un'animazione**.

## 2. Stack e hosting (deciso)
- **Astro** in output statico, **CSS puro** con variabili.
- **GSAP** con **ScrollTrigger** e **SplitText** per le animazioni allo scorrimento. È la stessa libreria del teaser, gratuita anche per i plugin, circa 60 KB compressi in tutto. Le animazioni CSS native legate allo scorrimento non sono ancora affidabili su tutti i browser.
- **Lenis** (circa 4 KB) per uno scorrimento morbido, facoltativo: si valuta in prova perché alcuni utenti lo trovano innaturale.
- Font **Barlow** e **IBM Plex Mono** self-hosted in woff2.
- Deploy su **Hostinger**: `dist/` in `public_html`, più un `.htaccess` per HTTPS, compressione e cache.
- Codice in `site/` dentro questa repo.

## 3. La pagina
Il sito è **una sola pagina**, più `/legal` e una 404. Il racconto segue un imbuto: gancio → magia → vantaggi → GitHub.

| # | Sezione | Obiettivo | Testo (bozza) | Cosa succede allo scorrimento |
|---|---|---|---|---|
| 0 | **Hero** | vendere | **talk to your agent.** · *your EP-2350 FX-MIC, now a voice remote for your Mac.* · pulsante **Get it on GitHub** · *open source · macOS · local AI* | Il mic entra dal basso. Il cursore arancione digita il titolo. La griglia di puntini del mic "respira" piano, come in attesa della voce. |
| 1 | **The idea** | vendere | *your agent is a conversation. stop typing it.* · *squeeze the handle, say what you want, let go.* | Frase gigante in Barlow 900 che si compone parola per parola mentre scorri; le parole già lette sbiadiscono. |
| 2 | **The magic** (sequenza fissa, vedi 3.1) | vendere + spiegare | quattro scene, una frase ciascuna | La sezione resta ferma sullo schermo e lo scorrimento fa avanzare la storia: voce → testo → AI → azione → agente. |
| 3 | **Why you'll love it** | spiegare i vantaggi | tre punti (vedi 3.2) | Tre blocchi entrano sfalsati; ognuno ha una piccola animazione del mic. |
| 4 | **By the numbers** | spiegare | **4** modes · **15** slots per app · **+9000** aura points · **0** words sent to the cloud | I numeri contano in su quando entrano; i LED del mic si accendono a ritmo. |
| 5 | **Get it** | portare su GitHub | *open source. free. yours.* · requisiti in una riga: *Mac with Apple silicon · macOS 14+ · EP-2350 FX-MIC* · pulsante grande **Get it on GitHub** · link secondario **Watch the teaser** | Fondo che passa da paper ad arancione mentre arrivi; il pulsante è l'unico elemento in primo piano. |
| — | **Footer** | — | autore, GitHub, LinkedIn, MIT, crediti, avviso di non affiliazione completo | statico, fondo scuro |

Il **pulsante GitHub** compare in tre punti: hero, sezione 5 e barra superiore (che appare solo dopo l'hero).

### 3.1 "The magic": la sequenza fissa
È il cuore del sito e dell'effetto wow. A sinistra il **mic**, a destra uno **schermo** stilizzato (una finestra paper con filetto da 1px, poi un terminale scuro). La sezione resta ferma per circa 4 altezze di schermo e ogni scena occupa un tratto di scorrimento.

| Scena | Titolo · frase | Mic | Schermo | Dove si vede l'AI |
|---|---|---|---|---|
| **A. hold. talk.** | *hold the handle and talk.* | La maniglia scende; i LED rossi partono con lo sweep KITT a scatti; l'isola nera scende dall'alto con REC e il timer. | I **puntini della griglia** si staccano dal mic come un'onda sonora e volano verso lo schermo. | La voce diventa materia visibile. |
| **B. the AI listens.** | *your words, written where your cursor is.* | LED in "thinking" (1+3 / 2+4 alternati); isola su *thinking*. | I puntini arrivano e **si trasformano in lettere**: il testo grezzo si decodifica carattere per carattere (lettere casuali in Plex Mono che si fissano in Barlow). | Trascrizione: dal suono al testo. |
| **C. the AI cleans up.** | *enhanced mode turns rambling into writing.* | Arancione premuto: si accende il LED rosso 2. | Il testo grezzo *"ehm so the the login page crashes when like you hit enter twice"* **si riscrive da solo**: le parole superflue si barrano e svaniscono, punteggiatura e maiuscole compaiono, il resto scivola al suo posto. Risultato: *"The login page crashes when you press Enter twice."* | È il momento più "magico": il testo cambia sotto gli occhi. |
| **D. one button to the agent.** | *pick a skill. press grey. done.* | Bianco premuto tre volte: i LED bianchi contano in binario fino a 3, accanto compare `/review`. Grigio premuto. | La finestra diventa un **terminale**: `> /review` si digita, l'agente risponde con righe che compaiono una alla volta e un `✓` finale. | L'AI agisce: la voce diventa lavoro fatto. |

Una sottile **barra di avanzamento** in Plex Mono (`((8.1)) ((8.2)) ((8.3)) ((8.4))`) indica a che punto della storia sei e richiama la numerazione dei capitoli.

**Su mobile** la sequenza resta fissa, con un layout compatto: mic piccolo accanto alla didascalia e terminale sotto. È più semplice da mantenere di cinque blocchi separati e in prova funziona bene. Con *riduci movimento* la sequenza non è fissa: tutte le didascalie sono elencate accanto al terminale nello stato finale.

### 3.2 I tre vantaggi
| Titolo | Frase | Animazione |
|---|---|---|
| **/ a button you can feel** | *a physical handle keeps you in the flow. no shortcuts to remember.* | La maniglia si abbassa e risale al passaggio. |
| **/ your voice stays home** | *speech-to-text and the language model run on your Mac. audio is never saved.* | Un puntino d'onda sonora prova a uscire dal riquadro e rimbalza dentro. |
| **/ every app, its own skills** | *buttons follow the app in front: /review in the terminal, "rewrite as email" everywhere else.* | I nomi degli slot cambiano mentre cambia l'icona dell'app in primo piano. |

Il punto *nothing permanent on the mic* resta una riga sotto i tre blocchi: è una rassicurazione, non un argomento di vendita.

## 4. Identità visiva e "magia dell'AI"

### 4.1 Cosa resta uguale
Le regole vengono dall'app e dal teaser (`Theme.swift`, `frame.md`):
- **Colori:** `--ink #1A1A1A`, `--paper #EDEDE8`, `--accent #F05A28` (unico accento), `--led-red #E3242B` solo per LED e registrazione; `--muted #8C8C88`, `--rule #C9C9C3`, `--bar #5E5E5B`, `--grille #3A3A38`.
- **Registri:** *paper* principale; *dark* per terminale e footer; *orange* per la chiusura "Get it".
- **Tipografia:** Barlow per tutto il testo, titoli **minuscoli** e grandi (pesi 800–900, tracking negativo); IBM Plex Mono maiuscolo solo per etichette, numeri di capitolo e terminale.
- **Superfici piatte:** filetti da 1px, barra grigia dei capitoli, marcatore `/`. Niente ombre, gradienti viola o vetro smerigliato.

### 4.2 Come passa la magia, senza tradire lo stile
La magia non viene da effetti "da AI" generici (gradienti al neon, particelle blu, glow), che stonerebbero con l'estetica della guida. Viene dalla **trasformazione**: vedere la voce diventare testo e il testo diventare azione.

- **La griglia del mic come campo di particelle.** I puntini della griglia sono l'elemento più riconoscibile dell'oggetto: diventano onda sonora, poi lettere. Un solo `<canvas>` con alcune centinaia di puntini, nei colori del mic.
- **Decodifica del testo.** Le parole compaiono come lettere casuali in Plex Mono che si fissano nella parola giusta (SplitText più un effetto scramble). È il segno visivo di "la macchina sta capendo".
- **Riscrittura in diretta.** Nella scena C il testo si corregge da solo: è l'immagine più chiara di cosa fa il modello.
- **Cursore arancione** che scrive titoli e frasi, come nel teaser.
- **LED a scatti** (circa 8 passi al secondo), mai sfumati: è il ritmo dell'hardware vero.
- **Stato "thinking"**: unica concessione al bagliore, un alone arancione morbido dietro l'isola mentre l'AI elabora.

### 4.3 Regole per il movimento
- Ogni animazione è legata allo scorrimento (si può tornare indietro e rivederla), tranne i piccoli cicli d'attesa.
- Facilità di movimento decise e brevi (`power3`, `expo`), come nel teaser; niente rimbalzi cartoon.
- **`prefers-reduced-motion`:** niente sequenza fissa né particelle; ogni scena mostra subito il suo stato finale.
- Le animazioni usano solo `transform` e `opacity`, e il canvas si ferma quando esce dallo schermo.

## 5. Asset
**Già disponibili:**
- mic vettoriale animabile: `videos/fxmic-bridge-teaser/assets/fxmic-device.svg` (va reso indirizzabile: LED, pulsanti, maniglia, puntini della griglia);
- illustrazioni del README in `docs/readme/` come riferimento;
- video teaser `videos/fxmic-bridge-teaser/renders/video.mp4`, per il link *Watch the teaser* (si apre in sovrimpressione, ricompresso);
- font woff2 e icona dell'app.

**Da produrre:**
- **immagine Open Graph** 1200×630 (mic, *talk to your agent.*, wordmark);
- favicon dall'icona dell'app;
- testi definitivi delle frasi (bozze nella sezione 3).

Gli screenshot dell'app non servono più: l'isola e il terminale sono ridisegnati come componenti animati.

## 6. Requisiti non funzionali
- **Peso:** pagina sotto i 400 KB al primo caricamento (JS compreso); il video si carica solo se lo apri.
- **Prestazioni:** 60 fps nelle animazioni su un MacBook Air e su un iPhone recente; Lighthouse ≥ 90 su mobile.
- **Responsive:** da 360 px, con la sequenza "magic" non fissa su mobile (vedi 3.1).
- **Accessibilità:** il testo di ogni scena è HTML vero (leggibile da screen reader e motori di ricerca), non solo canvas; contrasto AA; movimento ridotto rispettato.
- **SEO:** titolo, descrizione, Open Graph e Twitter, `sitemap.xml`, `robots.txt`, dati strutturati `SoftwareApplication`.
- **Privacy del sito:** nessun cookie, nessuno script di terze parti, nessun font remoto, nessun embed. Niente banner per i cookie; una breve nota in `/legal`.
- **Avviso legale:** *"unofficial · not affiliated with teenage engineering"* visibile già nell'hero, avviso completo nel footer.

## 7. Struttura dei file
```
site/
  astro.config.mjs
  package.json
  public/
    fonts/  media/  favicon.svg  og.png
    .htaccess  robots.txt
  src/
    styles/tokens.css       # colori, tipografia, spaziature
    styles/global.css
    layouts/Base.astro      # <head>, barra superiore, footer
    components/
      Mic.astro             # SVG del mic con LED, pulsanti, maniglia indirizzabili
      Island.astro          # isola nera (REC / thinking / written)
      Screen.astro          # finestra paper che diventa terminale
      ChapterProgress.astro # ((8.1)) … ((8.4))
      GitHubButton.astro
    sections/               # Hero, Idea, Magic, Benefits, Numbers, GetIt
    scripts/
      scroll.js             # ScrollTrigger: timeline delle sezioni
      grille.js             # canvas dei puntini: onda sonora → lettere
      decode.js             # effetto decodifica e riscrittura del testo
      leds.js               # LED a scatti
    pages/  index.astro  legal.astro  404.astro
```

## 8. Alternative considerate
- **Landing a capitoli completa come il README** (rev. 1 di questo documento): scartata, troppo testo per un sito che deve prima vendere l'idea.
- **Video al posto delle animazioni:** più semplice, ma non segue lo scorrimento, pesa di più e non si adatta allo schermo.
- **Three.js / WebGL con un mic in 3D:** grande effetto, ma pesante, lontano dallo stile piatto della guida e lungo da realizzare.
- **Animazioni CSS native legate allo scorrimento:** leggere, ma con supporto ancora incompleto e poco controllo sulle sequenze lunghe.

## 9. Punti aperti
1. **Dominio:** quale nome, e se è già su Hostinger.
2. **Download:** il pulsante porta alla pagina principale della repo (proposta) o alla pagina delle Release? Oggi non c'è un binario: per un vero "download" serve un `.dmg`, con l'avviso di Gatekeeper o la notarizzazione Apple.
3. **Testi:** vanno bene i toni e le bozze della sezione 3, in particolare *"talk to your agent."* come titolo?
4. **Esempio della scena C:** va bene un bug report, oppure preferisci un esempio più vicino a Claude (per esempio un prompt)?
5. **Lenis:** scorrimento morbido sì o no? Si decide guardando il prototipo.
6. **Statistiche:** nessuna (proposta) o uno strumento senza cookie come Plausible?

## 10. Piano
1. Revisione di questo documento e risposte ai punti aperti.
2. Scheletro Astro, token, font, layout, mic SVG indirizzabile.
3. Prototipo della sequenza "magic" (scene A–D) su desktop: è la parte più rischiosa, si valida per prima.
4. Hero, idea, vantaggi, numeri, chiusura; versione mobile e movimento ridotto.
5. SEO, Open Graph, `/legal`, 404, `.htaccess`; controllo di prestazioni e accessibilità.
6. Primo deploy su Hostinger.
