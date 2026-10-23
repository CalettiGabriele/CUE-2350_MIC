# Gesti e comandi di CUE-2350 MIC

> Riferimento unico per i gesti di EP-2350 FX MIC e per le azioni collegate.
> Aggiornato il 2026-10-23: canali sull'arancione, skill e comandi sul bianco, comando vocale sul grigio ([One-Pager 004](design-docs/onepager-004-channels-and-commands.md)).
> **Lingua dell'interfaccia:** inglese per impostazione predefinita, modificabile in Impostazioni › General › Language (English, Italiano, Français, Español, Português, Deutsch, 中文, 日本語, Русский) o in `config.json` (`ui.language`).
> Canali, skill, intenti e gesti si configurano nelle Impostazioni (capitoli **Channels** e **Profiles**) oppure in `~/Library/Application Support/FXMicBridge/config.json`. Questo file descrive i **valori predefiniti**. Il codice di riferimento è `app/Sources/FXMicCore/Config.swift` (`Profile.defaults`) e `GestureRecognizer.swift` (`GestureSettings`).

## In breve

| Pulsante | Ruolo | Tocco | Doppio tocco | Pressione lunga | Altro |
|---|---|---|---|---|---|
| **Maniglia** | parla | — | a capo (⇧↩) | tieni premuto e parla | — |
| **Arancione** | **canali**: dove va la voce | canale successivo | canale precedente | aggiunge la finestra davanti | **tenuto 3 s: svuota i canali** |
| **Bianco** | **skill e comandi** | successivo | precedente | nessuno | — |
| **Grigio** | **invia e interrompi** | esegue il comando, altrimenti Invio | annulla l'ultimo inserimento | **interrompi** (Esc) | **premuto mentre parli: comando vocale** |

## Cosa passa da ciascun collegamento

| Collegamento | Cosa trasporta | Cosa abilita |
|---|---|---|
| **USB-C** (dati) | Console seriale MicroPython, più alimentazione | Tutti i gesti e i LED. L'app installa un agente solo in RAM (ADR-001). |
| **Jack 3,5 mm** | Solo audio analogico | Solo la voce, tramite una scheda audio USB con ingresso di linea (Impostazioni › Audio). **Nessun gesto** (proposta per i gesti via codici acustici: [One-Pager 002](design-docs/onepager-002-jack-only-transport.md)). Il jack con microfono del Mac, con un adattatore TRS→TRRS, è stato provato senza successo: il Mac riconosce il microfono ma non riceve segnale. |
| **Tastiera del Mac** | — | Push-to-talk di riserva: **Opzione destro** tenuto premuto. |

## La voce va dove sei

Quando tieni premuta la maniglia, l'app guarda la finestra che hai davanti:

- se è quella di un **canale**, la voce va a quel canale e il suo LED rosso è acceso;
- altrimenti sei **libero**: i LED rossi sono spenti e la voce va **dove hai il cursore**, in qualsiasi app, senza nessun salto e senza bisogno di registrare niente.

Il profilo, cioè le skill del bianco e gli intenti, segue sempre l'app che hai davanti. La pillola dice dove va la voce: "Recording · Claude · api" su un canale, "Recording · Free · Mail" altrove.

## I tre pulsanti

### Arancione: canali (LED rossi, uno per canale)
Un **canale** è un posto a cui vuoi tornare con un tocco: una sessione di Claude Code o di Codex, una chat o un progetto di Claude, un documento (per esempio un `TODO.md` in VS Code), una finestra o un'app intera. Fino a **4 canali**, ciascuno con un LED rosso.

- **Tocco:** salta al canale successivo (da libero, al primo) e ne porta la finestra in primo piano.
- **Doppio tocco:** salta al canale precedente (da libero, all'ultimo).
- **Pressione lunga:** aggiunge la finestra che hai davanti come canale. Prende il primo canale libero; se sono tutti e quattro occupati sostituisce quello su cui sei (o l'ultimo, se sei libero). Se la finestra è già un canale, lo aggiorna.
- **Tenuto premuto 3 secondi:** **svuota tutti i canali**. È volutamente lento per non azionarlo per errore. Dal menu › Channel si può annullare ("Restore the cleared channels"), finché non agganci altro.

Come l'app ritrova un canale:

| Canale | Come si riconosce | Come ci si torna |
|---|---|---|
| Sessione di Claude Code | id della sessione, letto dal log di Claude | `claude://code/continue?session=…` |
| Thread di Codex | id del thread, letto dal log di Codex | `codex://threads/…` |
| Chat o progetto di Claude | indirizzo della pagina, letto via Accessibilità | `claude://claude.ai/chat/…` (o `/project/…`) |
| Documento | `AXDocument` della finestra | porta in primo piano l'app e la finestra |
| Finestra | titolo della finestra | porta in primo piano l'app e la finestra |
| App intera | l'app (qualsiasi finestra) | porta in primo piano l'app |

Se una finestra appartiene a più canali vince il più specifico (una sessione o una chat prima di un documento, poi del titolo, poi dell'app intera). Altre app con più sessioni in una finestra si aggiungono con un adattatore in `config.json` (`sessionAdapters`). I canali si gestiscono anche dal menu › Channel e dalle Impostazioni › Channels (rinomina, ordine, rimozione, aggiunta di un'app intera, svuotamento con conferma).

### Bianco: skill e comandi (LED bianchi in binario)
Fino a **15 per profilo**. I 4 LED bianchi mostrano il numero in binario, con il LED in alto = 1, poi 2, 4, 8. **Tutti spenti = nessuno.** La pillola mostra sempre il nome. L'elenco segue l'app che hai davanti, quindi su un canale è quello dell'app del canale.

| Tipo | Cosa succede |
|---|---|
| **Command** | Il **grigio** lo esegue subito: tasti o testo, per esempio `/compact` + Invio. |
| **Skill / template** | La **prossima dettatura** viene inserita nel testo al posto di `{{text}}` (per esempio "Summarize: {{text}}" o il prompt di una skill). |
| **LLM rewrite** | La **prossima dettatura** viene trasformata dal modello con l'istruzione (per esempio "Rewrite as an email"). |

- **Tocco:** successivo (nessuno → 1 → 2 → … → nessuno). **Doppio tocco:** precedente. **Pressione lunga:** nessuno.
- **Dopo l'uso** la selezione torna a "nessuno".
- I **nomi** sono anche quello che dici nel comando vocale ("lancia la review").

### Grigio: invia, interrompi, comando vocale
- **Tocco:** esegue il comando selezionato; se non ce n'è uno preme **Invio**.
- **Doppio tocco:** annulla l'ultimo inserimento (⌘Z, entro 30 s, stessa app).
- **Pressione lunga:** **interrompi** (intento `interrupt` del profilo, per impostazione predefinita **Esc**).
- **Premuto una volta mentre tieni la maniglia e parli: comando vocale.** La frase non viene scritta: va al modello locale, che sceglie le azioni da un elenco chiuso. Funziona in qualsiasi lingua e senza parole chiave da ricordare. Azioni possibili:
  - **testo e tasti** nel campo attivo: "vai a capo", "cancella l'ultima parola", "elenco puntato", "scrivi buongiorno a tutti";
  - **selezione:** se c'è del testo selezionato, "traducilo in inglese", "rendilo più corto", "mettilo in elenco puntato" lo sostituiscono con la versione trasformata; "cancellalo" lo elimina;
  - **canali:** "passa al progetto api", "vai a Codex" (basta una parte del nome);
  - **skill e comandi:** "lancia la review", "fai il compact";
  - **intenti del profilo:** "fermati", "nuova sessione" (vedi *Intenti*).

  Se il comando non è chiaro non succede nulla e la pillola lo dice. Le scorciatoie pericolose (⌘Q, ⌘W…) restano bloccate. Con il modello locale predefinito ci vuole circa 1 s. Si può provare una frase senza eseguirla in Impostazioni › LLM › *Test a voice command*.

## Maniglia e accelerometro
| Gesto | Azione |
|---|---|
| Tieni premuta la maniglia, parla, rilascia | Dettatura: il testo va dove sei (vedi sopra), con la skill selezionata se ce n'è una |
| Grigio premuto mentre parli | Comando vocale |
| Doppio clic rapido sulla maniglia | Nuova riga (⇧↩) |
| Scuotimento breve | Annulla la dettatura in corso |
| Scuotimento forte per almeno 2 s | Cancella tutto il campo (⌘A ⌫; nei terminali Ctrl+E Ctrl+U) |

## Pillola di stato e icona

- **Pillola in alto:**
  - **MacBook (notch, stile Dynamic Island, senza bordo):**
    - a sinistra del notch il puntino di stato: rosso con effetto **radar** in registrazione, bianco pulsante in elaborazione;
    - a destra il **tempo registrato**;
    - sotto una riga con fase, destinazione e skill, per esempio "Recording · Claude · api · Summarize" o "Recording · Free · Mail".
  - **Altri schermi:** pillola nera sotto la barra dei menu con bordo chiaro sottile: [puntino] testo [tempo].
  - Le schede brevi (cambio di canale "Channel 2/3 · Codex", skill "Slot 3 · /review", "Voice command", "Written", errori) mostrano solo il testo. Comparsa e scomparsa con una dissolvenza.
- **Icona nella barra dei menu:** è **sempre quella scelta** (menu › Menu bar icon) e non cambia durante la registrazione, perché macOS mostra già il suo indicatore del microfono. Lo stato si legge nel tooltip e nella prima riga del menu.

## LED
| Stato | LED rossi | LED bianchi |
|---|---|---|
| Inattivo | Il canale su cui sei (un LED), oppure **tutti spenti se sei libero** | Skill in binario, oppure spenti |
| Registrazione | **KITT**: un LED che scorre su e giù | Invariati |
| Trascrizione ed elaborazione | Alternanza 1+3 / 2+4 | Invariati |
| Errore | Lampeggio dei 4 rossi per circa 1 s | — |

- **Mappa dei LED:** `device.ledMap` in `config.json` indica quale indice fisico corrisponde a [rosso 1…4, bianco 1…4]. Il valore predefinito `[0,1,2,3,4,5,6,7]` è stato verificato sul dispositivo il 2026-10-16. Impostazioni › Device › **Test LEDs** accende i LED uno alla volta in quest'ordine logico, così si capisce se la mappa è giusta.
- **Velocità delle animazioni:** si regola con `device.ledAnimationMs`, predefinito 120 ms.

## Profili predefiniti
| Profilo | App | Skill e comandi |
|---|---|---|
| **Claude** | App Claude desktop | New chat ⌘N · Stop response Esc · Summarize · Translate to English · Explain simply · Brainstorm |
| **Coding agent** | Terminale, iTerm2, Ghostty, VS Code, Warp | /compact · /clear · /review · Bug report · Commit message (LLM) |
| **General** | Tutte le altre | Email · Translate to English · Bullet list · Shorter (tutti LLM) |

## Intenti
Un **intento** è un'azione con un nome che il profilo traduce nell'app: così "fermati" vale Esc in Claude e un'altra scorciatoia altrove. Si definiscono per profilo in Impostazioni › Profiles › *Voice command* oppure in `config.json`, sotto `intents`. Quelli senza associazione rispondono "non disponibile qui".

| Intento | Predefinito |
|---|---|
| `interrupt` | tasto Esc (anche pressione lunga del grigio) |
| altri (per esempio `newSession`, `approve`) | da definire per profilo: `"intents": {"newSession": {"type": "key", "keys": ["cmd+n"]}}` |

## Azioni configurabili
| `type` | Effetto |
|---|---|
| `key` (`keys`: lista) | Invia combinazioni come `cmd+a`, `shift+return`, `escape` |
| `text` (`text`) | Scrive il testo; un `\n` finale preme anche Invio |
| `nextChannel` / `previousChannel` / `bindChannel` / `clearChannels` | Canali (arancione) |
| `nextSlot` / `previousSlot` / `clearSlot` | Skill e comandi (bianco) |
| `runSlot` | Esegue il comando selezionato, altrimenti Invio |
| `intent` (`name`) | Esegue l'intento del profilo |
| `editSelection` | Comando vocale (il nome è rimasto per compatibilità) |
| `undoLastInsertion`, `reinsertLast`, `cancel`, `none` | Annulla l'ultimo inserimento, riscrive l'ultimo testo, annulla la dettatura, niente |
| `cycleMode` / `resetMode` | Superate: le vecchie modalità di interazione, lette solo dai file di configurazione vecchi |

## Soglie dei gesti
| Parametro | Valore |
|---|---|
| `tapMaxMs` · `doubleTapMs` · `longPressMs` · `veryLongPressMs` | 450 · 300 · 600 · 3000 ms |
| `handleClickMaxMs` · `handleDoubleClickGapMs` | 280 · 400 ms |
| `shakeThreshold` · `shakeHoldMs` · `shakeHoldToleranceMs` | 0,5 · 2000 ms · 400 ms |
