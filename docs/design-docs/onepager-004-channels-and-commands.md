# One-Pager 004 — Canali (arancione), azioni (grigio), prompt e skill (bianco) e comandi vocali

> Data: 2026-10-22 (rev. 2, dopo le verifiche del §10) · rev. 3 del 2026-10-23 (§14–§15) · Stato: **Implementato in parte** (canali, comandi vocali, Impostazioni); restano gli hook (LED di stato, risposta ai permessi) e il modello esterno, vedi §14
> Sostituisce il One-Pager 001 per l'arancione; il bianco e i LED manuali restano, con nomi nuovi
> **Durante l'implementazione alcune scelte sono cambiate rispetto ai §3–§6:** prevale il §14.
> Riferimenti: One-Pager 001, TDD v1 §3.2–3.3, `docs/GESTURES.md`, `app/Sources/FXMicCore/Config.swift`, `app/Sources/FXMicCore/ProfileEngine.swift`, `app/Sources/FXMicBridge/DictationController.swift`

## 1. Problema
Le quattro modalità dell'arancione (Dettato, Migliorato, Comando, Computer Use) non convincono per l'uso principale del dispositivo, cioè **lavorare con agenti AI** come Claude Code e Codex:
- **Migliorato** serve a poco: chi riceve il testo è già un LLM, e il modello locale aggiunge attesa e storpia i termini tecnici;
- **Comando** come modalità persistente è uno stato nascosto: si detta credendo di scrivere e invece si eseguono tasti;
- **Computer Use** è un segnaposto;
- l'LLM viene chiamato anche quando non serve, e la latenza si sente.

Manca invece ciò che serve davvero a chi lavora con più agenti insieme:
- passare da una sessione all'altra senza mouse;
- sapere quale agente sta aspettando una risposta;
- dare comandi a voce senza ricordare parole chiave.

## 2. Obiettivi
1. **Nessun LLM nel percorso normale:** la dettatura di base è Whisper → testo nel canale, senza attese.
2. **L'arancione sceglie a chi parlo** (canali), non come elaboro il parlato.
3. **I comandi vocali sono espliciti e fisici:** leva + grigio. Niente parole chiave da imparare.
4. **Generico:** funziona con Claude Code e Codex (app o terminale), con altri harness e con app classiche come Word, Mail o un `.md` in un editor. Nessuna app è cablata nel codice.
5. **Multilingue:** Whisper riconosce la lingua da solo (`speech.language = "auto"`, già così), e i prompt dell'LLM non presuppongono una lingua.
6. **Locale per impostazione predefinita**, con la possibilità di collegare un modello esterno compatibile con lo standard OpenAI.

Fuori ambito per ora: ritorno vocale (sintesi), coda dei messaggi, cattura in file di note, formattatori letterali, Computer Use.

## 3. La nuova mappatura

| Pulsante | Tocco | Doppio tocco | Pressione lunga | Durante la dettatura |
|---|---|---|---|---|
| **Maniglia** | tieni premuto e parla: porta in primo piano il canale e scrive il testo grezzo | a capo (⇧↩) | — | — |
| **Arancione** · canali | canale successivo; se un agente ti aspetta, salta prima a quello | canale precedente | **aggancia** la finestra attiva al canale corrente | — |
| **Grigio** · azioni | esegue lo slot Esegui selezionato; se non c'è nessuno slot, **Invio** | annulla l'ultimo inserimento | **Interrompi** (Esc, o l'azione del profilo) | **la frase diventa un comando** (§6) |
| **Bianco** · prompt e skill | slot successivo | slot precedente | nessuno slot | — |

Scuotimento breve (annulla la dettatura in corso) e scuotimento forte (cancella tutto) restano come oggi.

## 4. Arancione: i canali

### 4.1 Cos'è un canale
Un canale è una **destinazione con un nome**, legata a uno dei 4 LED rossi. Può essere:
- una sessione di un agente (Claude Code desktop, Codex, una sessione in terminale, un altro harness);
- un'app classica (Mail, Word);
- un documento aperto (un `TODO.md` in VS Code o in un altro editor).

Quattro canali sono sufficienti (deciso con l'utente).

Quando si parla, l'app **porta in primo piano la finestra del canale** e scrive lì. È voluto: così l'utente vede subito cosa viene trascritto e può correggerlo.

### 4.2 Agganciare un canale
Nessuna configurazione obbligatoria, basta un gesto:
1. si porta in primo piano la finestra voluta;
2. si tiene premuto l'arancione;
3. la pillola conferma, per esempio "Canale 2 → Claude · progetto-api".

L'app salva un'**impronta**, che permette di ritrovare la finestra anche dopo un riavvio:

| Destinazione | Impronta |
|---|---|
| App classica | bundle id |
| Documento | bundle id + percorso del file (`AXDocument` dove l'app lo espone) o, in mancanza, il titolo della finestra |
| Sessione di agente | bundle id + **id di sessione** + cartella di progetto (`cwd`) e titolo, per riconoscerla se l'id cambia |

Il **profilo** del canale (slot, intenti, suggerimenti per l'LLM) si ricava dal bundle id, come oggi.

**Agganciare una sessione di agente.** Al momento dell'aggancio l'app deve capire *quale* sessione è in primo piano. Lo fa leggendo l'indice delle sessioni (§4.3) e scegliendo quella con l'attività più recente nell'app attiva. Se il risultato è ambiguo, la pillola propone le ultime sessioni per titolo e si sceglie con il bianco.

### 4.3 Più sessioni nella stessa finestra: deep link e indice delle sessioni
Claude Code desktop e Codex mostrano più sessioni in una sola finestra, con una barra laterale. Le verifiche del 2026-10-22 hanno mostrato che **tutte e due le app hanno un deep link per aprire una sessione precisa**. Non serve quindi cliccare nella barra laterale.

| App | Deep link per aprire la sessione | Indice delle sessioni (solo lettura) | Id usato dagli hook |
|---|---|---|---|
| **Claude desktop** (`com.anthropic.claudefordesktop`) | `claude://code/continue?session=local_<id>` | `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`, con `sessionId`, `cliSessionId`, `cwd`, `title`, `isArchived`, `lastActivityAt` | `cliSessionId` (verificato: coincide con il `session_id` degli hook) |
| **Codex desktop** (`com.openai.codex`) | `codex://threads/<id>` | `~/.codex/sessions/AAAA/MM/GG/rollout-…-<id>.jsonl`, prima riga `session_meta` con `id`, `cwd`, `originator` | `session_id` = id del thread (da confermare) |
| **Agente in terminale** (Claude Code CLI, codex CLI, altri) | nessuno: si porta in primo piano la finestra o la scheda del terminale | — | `session_id` dell'hook, associato alla finestra al momento dell'aggancio |

Altri deep link utili di Claude desktop:
- `claude://code/needs-input`: apre le sessioni che aspettano l'utente;
- `claude://code/new?folder=<percorso>`: apre una nuova sessione in una cartella, utile per l'intento `newSession`.

Regole per l'indice delle sessioni:
- **Si legge e basta.** I file sono interni alle app, non documentati, e possono cambiare. Il lettore ignora i campi mancanti e, se il formato non è più riconosciuto, il canale ripiega sulla sola app (bundle id).
- **La mappa si costruisce dagli hook.** Quando arriva un evento, l'app cerca il `session_id` nell'indice, trova la sessione (`local_…` per Claude, id del thread per Codex) e quindi il canale e il deep link.
- **Ultima risorsa:** se un'app non offre deep link, la sessione si apre con un clic sulla voce della barra laterale via Accessibilità.

### 4.4 Stato degli agenti sui LED rossi

| LED rosso | Significato |
|---|---|
| fisso | canale selezionato |
| spento | canale non selezionato e inattivo |
| respiro lento | l'agente sta lavorando |
| **lampeggio** | **l'agente ti aspetta**: un permesso, una domanda, oppure ha finito |
| KITT (scorrimento) | registrazione in corso, come oggi |

Lo stato arriva dagli **hook** degli agenti, non dalla lettura dello schermo. Ogni hook chiama un piccolo comando dell'app, `fxmic-notify`, passandogli il JSON dell'evento. Il comando lo inoltra all'app, che trova il canale con l'id di sessione (§4.3).

| Stato del LED | Claude Code | Codex |
|---|---|---|
| lavora | `UserPromptSubmit` | `UserPromptSubmit` |
| ti aspetta: permesso | `PermissionRequest` (o `Notification` con `permission_prompt`) | `PermissionRequest` |
| ti aspetta: domanda | `Notification` con `elicitation_dialog` o `agent_needs_input` | — (da verificare) |
| ha finito | `Stop` | `Stop` |

Tutti e due gli agenti passano a ogni hook `session_id`, `cwd` e `hook_event_name`.

- **Altri harness:** lo stesso comando, se espongono hook. Senza hook il canale funziona ma non ha stato.
- **App classiche:** nessuno stato, il LED è solo fisso o spento.

**Installazione degli hook.** L'app la propone dalle Impostazioni, mostrando prima cosa scrive:
- Claude Code: `~/.claude/settings.json`, aggiungendo le voci accanto a quelle esistenti senza toccare gli hook già presenti;
- Codex: `~/.codex/hooks.json`. Codex chiede di approvare gli hook non gestiti prima di eseguirli. **Il `notify` già presente in `config.toml` non si tocca**, perché lo usa Computer Use di Codex.

## 5. Grigio e bianco

### 5.1 Grigio: le azioni sul canale
- **Tocco:** esegue lo slot Esegui, altrimenti Invio sul canale.
- **Doppio tocco:** annulla l'ultimo inserimento, con il metodo giusto per l'app (⌘Z nelle app, altri tasti nei terminali, secondo il profilo).
- **Pressione lunga:** Interrompi. Il profilo decide il tasto: Esc per Claude Code e Codex, nulla per le app classiche.
- **Premuto durante la dettatura:** comando (§6).

Il grigio deve restare affidabile anche quando la voce viene capita male: per questo le sue azioni non passano mai dall'LLM.

### 5.2 Bianco: prompt e skill, come oggi ma per canale
- Gli slot restano quelli del One-Pager 001 (fino a 15, LED bianchi in binario, nome sulla pillola), con i tre tipi **Esegui**, **Modello** e **LLM**.
- **Gli slot seguono il canale:** sono quelli del profilo dell'app del canale. Cambiando canale cambiano gli slot, quindi ogni canale ne ha pochi.
- **L'LLM parte solo con gli slot LLM.** Esegui (tasti, `/compact`) e Modello (`Usa la skill "review" su: {{testo}}`) sono sostituzioni di testo, istantanee.
- La selezione dello slot si ricorda **per canale** e torna a "nessuno slot" dopo l'uso, come oggi.

## 6. Comandi vocali: leva + grigio

### 6.1 Il gesto
- Mentre si tiene premuta la maniglia, **basta una pressione del grigio, in qualsiasi momento**: la frase diventa un comando. Non serve tenerlo premuto fino alla fine.
- Il grigio premuto durante la dettatura **non** fa partire al rilascio la sua azione normale (Invio).
- La pillola mostra "Comando" e i LED rossi usano un'animazione diversa da KITT, così si capisce subito che la frase non verrà scritta.

Il gesto esiste già (`markEditSelection` in `DictationController`); cambia il significato. La vecchia "modifica della selezione" diventa un caso particolare del comando (§6.2, livello 2).

### 6.2 Cosa può fare un comando
Il parlato non viene scritto. Va all'LLM, che risponde con un JSON di azioni da un **vocabolario chiuso**, poi convalidato. Si riusa il formato `{"actions":[…]}` della vecchia modalità Comando, estendendolo:

| Livello | Azioni | Esempi |
|---|---|---|
| 1. Testo e tasti *(esiste)* | `text`, `key` nel campo attivo | "cancella l'ultima frase", "vai a capo", "seleziona tutto" |
| 2. Selezione | `replaceSelection` con il testo trasformato, se c'è una selezione | "traducilo in inglese", "rendilo una lista" |
| 3. Canali e slot | `switchChannel(nome)`, `runSlot(nome)`, `intent(nome)` | "passa al progetto api", "lancia la review", "nuova sessione", "interrompi" |
| 4. Menu dell'app *(fase 2)* | `menu(percorso)`, scelto tra le voci di menu lette via Accessibilità | "esporta in PDF" in Word, "rispondi a tutti" in Mail |

**Gli intenti** sono azioni astratte che il profilo traduce in tasti: `interrupt`, `approve`, `approveAlways`, `reject`, `newSession`, `cycleAgentMode`. Un intento che il profilo non definisce mostra "non disponibile qui". Così un nuovo harness si supporta associando i suoi tasti agli intenti, senza toccare il codice.

**Il livello 4** rende i comandi generici per qualsiasi app senza configurazione, perché i menu sono un elenco finito che l'app stessa dichiara. Non è Computer Use: nessun clic su coordinate dello schermo.

### 6.3 Contesto passato all'LLM
Il contesto resta breve, per tenere bassa la latenza:
- app e nome del canale;
- stato dell'agente;
- testo selezionato, se c'è;
- nomi degli slot del canale e nomi dei canali;
- intenti disponibili nel profilo;
- voci di menu (solo dal livello 4, filtrate e troncate).

Il prompt di sistema e gli esempi diventano **neutri rispetto alla lingua**: oggi sono in italiano, mentre la frase può arrivare in qualsiasi lingua riconosciuta da Whisper.

### 6.4 Agente in attesa: risposta senza gesto
È l'unica regola automatica. Se il canale selezionato ha un agente **in attesa di una risposta** (permesso o domanda, segnalati dall'hook), la frase dettata viene trattata come **risposta** anche senza grigio:
- "sì", "no", "yes", "ok" vengono riconosciuti con un **confronto di testo**, senza LLM e quindi senza attesa;
- le frasi più articolate ("sì, sempre per questa sessione", "no, usa pnpm") passano all'LLM, che sceglie l'opzione o scrive la risposta.

### 6.5 Rispondere ai permessi tramite hook
Per i permessi non si simulano tasti nell'interfaccia: si risponde **attraverso l'hook `PermissionRequest`**, che sia Claude Code sia Codex supportano. È più solido, perché non dipende dall'aspetto della finestra né dalle scorciatoie dell'app.

Funzionamento:
1. L'agente sta per chiedere un permesso e chiama l'hook. `fxmic-notify` avvisa l'app, che fa lampeggiare il LED del canale e mostra sulla pillola cosa viene chiesto (strumento e comando, dai campi `tool_name` e `tool_input`).
2. L'hook **resta in attesa** della risposta dell'app per un tempo breve e configurabile (per esempio 20 s).
3. Se l'utente risponde a voce:
   - "sì" → l'hook restituisce `allow`;
   - "no" → `deny`, con il motivo dettato se c'è ("no, usa pnpm") che arriva all'agente come spiegazione;
   - "sì sempre" → `allow` più la regola permanente, se l'agente la supporta, altrimenti solo `allow`.
4. Se il tempo scade o l'utente risponde con il mouse, l'hook non decide e l'agente mostra la sua finestra di permesso normale: in Codex con il "defer" previsto, in Claude Code restituendo una risposta vuota.

Le domande (`elicitation_dialog`, `agent_needs_input`) non passano da `PermissionRequest`: lì la risposta si scrive nel campo dell'agente e si invia.

**Punto da chiarire nella prova:** con l'hook in attesa, Claude Code e Codex mostrano già la loro finestra di permesso o la mostrano solo alla fine dell'hook? Nel secondo caso l'attesa va tenuta più corta, per non nascondere la richiesta a chi non sta usando la voce.

La regola "nessun campo di testo attivo → comando" è stata **scartata**: nelle app di agenti il campo di inserimento è quasi sempre attivo, e nelle altre app il segnale è troppo incerto.

### 6.6 Sicurezza ed errori
- La lista dei tasti bloccati di `CommandParser.forbidden` resta: niente ⌘Q, ⌘W, ⌘Tab e simili.
- Se la risposta non è valida, o il comando è ambiguo, **non si esegue nulla** e la pillola lo dice.
- Dopo l'esecuzione la pillola mostra cosa è stato fatto, per esempio "✓ Lanciato: review", e tutto finisce in cronologia.
- Le voci di menu distruttive (Elimina, Esci, Chiudi) sono escluse dal livello 4.

## 7. LLM: locale ed esterno
- Il client attuale (`LLMClient`) usa già `/chat/completions` in formato OpenAI, ma non manda una chiave API e usa un solo endpoint per tutto.
- Si aggiunge una **chiave API facoltativa** (salvata nel Portachiavi) e la possibilità di scegliere l'endpoint **per uso**: comandi, slot LLM. Il locale resta il predefinito.
- Quando una frase esce dal Mac, la pillola mostra un **indicatore "esterno"**.
- **Ripiego:** se l'LLM non risponde, il comando non viene eseguito e compare un avviso; uno slot LLM scrive il testo grezzo.

## 8. Modifiche al modello dati (schema v3)
- `channels`: 4 elementi `{name, target: {bundleId, document?, cwd?, sessionId?}, slotIndex}`, salvati a livello globale e non per profilo.
- `Profile.interaction` viene sostituito da:
  - `intents`: mappa intento → azione (per esempio `interrupt: key escape`);
  - `commandHints`: suggerimenti per l'LLM (c'è già).
- `Profile.slots` resta com'è.
- `InteractionMode` sparisce. Le vecchie impostazioni `enabledModes` e `defaultMode` vengono ignorate. Il prompt "Migliorato" diventa, se presente, uno slot LLM chiamato "Migliora" nel profilo.
- `llm`: si aggiungono `apiKeyRef` e un `endpoints` opzionale per uso.
- Gesti: nuove azioni `nextChannel`, `previousChannel`, `bindChannel`, `interrupt`. `cycleMode` e `resetMode` restano per compatibilità ma non sono più assegnate.

## 9. Compatibilità
- Il primo avvio con lo schema v3 crea `config.json.bak` e converte il file come descritto in §8.
- Senza canali agganciati, l'app si comporta come oggi senza modalità: la dettatura va all'app in primo piano.

## 10. Verifiche
Dettagli in `logs/TEST_NOTES.md`, sezione "One-Pager 004 §10 checks (2026-10-22)".

| # | Verifica | Esito |
|---|---|---|
| 1 | Campo di testo e documento via Accessibilità (Claude desktop, Codex, VS Code, Terminale, Ghostty, Word, Mail; `AXManualAccessibility` per le app Electron) | **Aperta.** La prova va eseguita da un processo con il permesso Accessibilità (FXMic Bridge o un terminale autorizzato) |
| 2 | Hook di Claude Code nell'app desktop | **In parte.** La documentazione dice che scattano anche nell'app desktop; la mappa `cliSessionId` ↔ `session_id` è verificata. Manca la prova sul campo in una sessione nuova (gli hook non si ricaricano a sessione aperta) |
| 3 | Eventi di Codex | **Sì, sulla carta:** hook stabili in codex-cli 0.154, con `PermissionRequest` e `Stop`. Da provare nell'app desktop |
| 4 | Aprire una sessione precisa | **Risolta:** deep link in tutte e due le app (§4.3). Restano da vedere a occhio il passaggio tra due sessioni di Claude e l'apertura di un thread di Codex |
| 5 | Rispondere ai permessi | **Superata:** si risponde via hook (§6.5), non con i tasti. Resta da capire come si comporta la finestra di permesso mentre l'hook attende |
| 6 | Latenza del comando | **Superata:** qwen3.5:4b, 12 frasi in 4 lingue, mediana 644 ms, massimo 770 ms. Canali, slot e intenti corretti 9 volte su 10; testo e tasti richiedono esempi nel prompt per ogni livello |

## 11. Alternative considerate
- **Modalità sull'arancione (One-Pager 001):** scartate per i motivi del §1.
- **Modalità "Prompt" (riscrittura del parlato come prompt) e "Chiedi" (domanda con risposta sulla pillola):** scartate dall'utente.
- **Comandi riconosciuti dalla prima parola** ("comando…"): scartati, perché richiedono di ricordare una parola chiave.
- **LLM che decide a ogni frase se è testo o comando:** scartato per la latenza.
- **LLM solo quando nessun campo di testo è attivo:** scartato (§6.4).
- **Tocco del grigio per approvare:** non abbastanza solido; sostituito da §6.4, §6.5 e dagli intenti.
- **Rispondere ai permessi simulando i tasti dell'interfaccia:** scartato a favore dell'hook `PermissionRequest` (§6.5), che non dipende dall'aspetto delle app.
- **Selezionare la sessione cliccando nella barra laterale via Accessibilità:** resta solo come ultima risorsa, perché tutte e due le app hanno un deep link (§4.3).
- **Ritorno vocale, coda, cattura, formattatori letterali:** rimandati.

## 12. Rischi
1. **Indice delle sessioni e deep link non documentati** (§4.3): un aggiornamento di Claude o di Codex può cambiarli. Mitigazione: lettore tollerante e ripiego sulla sola app; una prova automatica del formato all'avvio, con un avviso nelle Impostazioni se non è più riconosciuto.
2. **Hook in attesa della risposta** (§6.5): se l'attesa nasconde la finestra di permesso, chi non usa la voce aspetta senza sapere perché. Mitigazione: attesa breve e configurabile, con la possibilità di disattivarla.
3. **Accessibilità delle app Electron**: potrebbe esporre poco o nulla senza `AXManualAccessibility`.
4. **Affidabilità dei comandi con il modello da 4B** al crescere del vocabolario: per questo si parte dai livelli 1–3 e il livello 4 arriva in fase 2.
5. **Hook non uniformi tra harness:** Claude Code e Codex sono coperti; altri harness potrebbero non avere stato.
6. **Portare in primo piano una finestra** a ogni dettatura può disturbare se si sta lavorando altrove. È voluto, ma va verificato nell'uso.

## 13. Piano
1. Chiudere le verifiche aperte del §10: Accessibilità, hook nell'app desktop di Claude e Codex, finestra di permesso con l'hook in attesa.
2. Schema v3, migrazione e test unitari.
3. Canali: aggancio, impronta, lettore dell'indice delle sessioni, deep link, messa in primo piano, LED di stato.
4. Hook: comando `fxmic-notify`, risposta ai permessi (§6.5) e installazione guidata per Claude Code e Codex.
5. Grigio e bianco con la nuova mappatura; slot per canale.
6. Comandi: gesto, livelli 1–3, risposta all'agente in attesa, prompt multilingue.
7. LLM esterno: chiave API ed endpoint per uso.
8. Livello 4 (menu dell'app).
9. Aggiornamento di `GESTURES.md`, del TDD e del sito, poi verifica sul dispositivo.

## 14. Stato dell'implementazione (rev. 3, 2026-10-23)

### 14.1 Implementato
| Parte | Commit | Note |
|---|---|---|
| Canali sull'arancione, aggancio, LED, schema v3 | `d9e04a8` | |
| Sessioni di Claude e Codex con gli adattatori (`SessionAdapter`) | `d9e04a8` | log + deep link, configurabili in `sessionAdapters` |
| Comando vocale (grigio mentre parli), intenti, grigio lungo = interrompi | `d9e04a8` | livelli 1–3 del §6.2 |
| Impostazioni: capitolo Canali, profili a pagine, test del comando vocale | `7c9c813`, `b157bff` | |
| **La voce va dove sei** e **svuota i canali** | `d439862` | cambia il §4, vedi 14.2 |
| Chat e progetti di Claude come canali | `2656f04` | indirizzo della pagina via Accessibilità |

### 14.2 Cosa è cambiato rispetto al design
- **Niente salto quando parli.** Il §4.1 prevedeva che parlando la finestra del canale selezionato venisse portata in primo piano. In uso era scomodo: lavorando in un'app non registrata la voce ti riportava al canale. Ora **decide la finestra che hai davanti**: se è un canale la voce va lì, altrimenti sei **libero** (LED rossi spenti) e la voce va dove hai il cursore. Solo l'arancione fa saltare. Il profilo segue sempre l'app davanti.
- **Niente posizione vuota.** L'arancione scorre solo tra i canali agganciati (da libero parte dal primo o dall'ultimo). La pressione lunga aggiunge la finestra al primo canale libero; con quattro canali sostituisce quello su cui sei.
- **Svuota i canali:** arancione tenuto **3 s** (gesto `veryLongPress`), dal menu con conferma e annulla, dalle Impostazioni con conferma.
- **Chat e progetti di Claude:** non hanno righe di log, quindi un canale ne salva l'indirizzo letto dalla pagina web (`webPattern`/`webLink` dell'adattatore) e ci torna con `claude://claude.ai/chat/…`. Senza questo, dalla vista Code non si poteva tornare a una chat.
- **Grigio lungo = interrompi** anche nei profili non di coding (prima: riscrive l'ultimo testo grezzo).

### 14.3 Non ancora fatto
- Hook `fxmic-notify`: LED di stato degli agenti (§4.4), risposta all'agente in attesa (§6.4) e ai permessi via hook (§6.5). Gli hook di prova del §10 sono ancora installati in `.claude/settings.local.json` e `~/.codex/hooks.json`.
- Modello esterno con chiave API ed endpoint per uso (§7) e livello 4 dei comandi (menu dell'app, §6.2).
- Traduzioni delle nuove scritte (oggi in inglese in tutte le lingue).
- Collegamento solo jack: provato con il jack con microfono del Mac, senza segnale (`logs/TEST_NOTES.md`); resta da provare un'interfaccia audio USB con ingresso di linea.

## 15. Vocabolario per README, sito e video

Le parole con cui si racconta il prodotto all'esterno, in inglese, uguali in README, sito, video e app.

| Termine | Significato | Da evitare |
|---|---|---|
| **channels** (orange) | fino a 4 posti dove va la voce: sessioni di Claude Code e Codex, chat e progetti di Claude, documenti, app | modes, interaction modes |
| **the voice goes where you are** | sulla finestra di un canale va a quel canale; altrove sei **free** e va dove hai il cursore, senza salti | "selected channel" come destinazione fissa |
| **free** | nessun canale davanti: LED rossi spenti | empty position |
| **skills & commands** (white) | fino a 15 per app: un comando che il grigio esegue, una skill/template o una riscrittura LLM applicata alla prossima dettatura | slots (solo nei dettagli tecnici), styles |
| **send · interrupt** (grey) | tocco = esegue il comando o Invio; pressione lunga = interrompi | rewrite the last text |
| **voice command** (grey while you talk) | la frase diventa azioni: testo, tasti, selezione, canali, skill, intenti; in qualsiasi lingua | enhanced, command mode, computer use |
| **hold orange for 3 s** | svuota i canali | — |
| **local by design** | trascrizione e modello sul Mac | — |

Messaggi chiave, in quest'ordine:
1. *Hold the handle, talk, release: the words land where your cursor is.*
2. *Four channels on the orange button: jump between Claude Code sessions, Claude chats, Codex threads and documents. Anywhere else the voice just goes where you are.*
3. *Grey while you talk turns a sentence into actions, in any language.*
4. *White picks a skill or a command; grey sends it.*
5. *Everything runs on your Mac.*

