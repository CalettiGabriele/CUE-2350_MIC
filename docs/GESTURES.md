# Gesti e comandi di FXMic Bridge

> Riferimento unico per i gesti di EP-2350 FX MIC e per le azioni collegate.
> Versione dell'app: 0.3.0 (One-Pager 001), aggiornato il 2026-10-16.
> **Lingua dell'interfaccia:** inglese per impostazione predefinita, modificabile in Impostazioni › Generale › Lingua (English, Italiano, Français, Español, Português, Deutsch, 中文, 日本語, Русский) o in `config.json` (`ui.language`).
> Tutto si configura **per profilo** in Impostazioni › Profili (oppure in `~/Library/Application Support/FXMicBridge/config.json`). Questo file descrive i **valori predefiniti**. Il codice di riferimento è `app/Sources/FXMicCore/Config.swift` (`Profile.defaults`) e `GestureRecognizer.swift` (`GestureSettings`).

## Cosa passa da ciascun collegamento

| Collegamento | Cosa trasporta | Cosa abilita |
|---|---|---|
| **USB-C** (dati) | Console seriale MicroPython, più alimentazione | Tutti i gesti e i LED. L'app installa un agente solo in RAM (ADR-001). |
| **Jack 3,5 mm** | Solo audio analogico | Solo la voce, tramite una scheda audio USB (Impostazioni › Audio). **Nessun gesto** (proposta per i gesti via codici acustici: [One-Pager 002](design-docs/onepager-002-jack-only-transport.md)). |
| **Tastiera del Mac** | — | Push-to-talk di riserva: **Opzione destro** tenuto premuto. |

## I tre pulsanti

### Arancione: canali (LED rossi, uno per canale)
Un **canale** è una finestra, un documento o una sessione di un agente (per esempio una sessione di Claude, un `TODO.md` in VS Code, una bozza di Mail) a cui vuoi poter tornare con un tocco. Fino a **4 canali**, ciascuno con un LED rosso.

**La voce va dove sei.** Quando parli, l'app guarda la finestra che hai davanti: se è quella di un canale, la voce va a quel canale (il LED rosso corrispondente è acceso); altrimenti sei **libero**: tutti i LED rossi sono spenti e la voce va dove hai il cursore, in qualsiasi app, **senza nessun salto** e senza bisogno di registrare niente. Il profilo e le skill del bianco seguono sempre l'app che hai davanti.

- **Tocco:** salta al canale successivo (da libero, al primo) e ne porta la finestra in primo piano.
- **Doppio tocco:** salta al canale precedente (da libero, all'ultimo).
- **Pressione lunga:** aggiunge la finestra che hai davanti come canale. Prende il primo canale libero; se sono tutti e quattro occupati sostituisce quello su cui sei (o l'ultimo, se sei libero). Se la finestra è già un canale, lo aggiorna.
- **Tenuto premuto 3 secondi:** **svuota tutti i canali**. È volutamente lento per non azionarlo per errore; dal menu › Canale si può annullare ("Ripristina i canali cancellati").

La finestra si ritrova per sessione (Claude e Codex), per documento (`AXDocument`) o per titolo; per un canale che è un'app intera vale qualsiasi finestra di quell'app. I canali si gestiscono anche dal menu › Canale (arancione) e dalle Impostazioni › Canali, dove si può anche svuotarli con una conferma. Le modalità di interazione (Dettato, Migliorato, Comando, Computer Use) non sono più selezionabili: la dettatura è sempre grezza, il comando vocale arriva con il grigio ([One-Pager 004](design-docs/onepager-004-channels-and-commands.md)).

### Bianco: slot di comandi e skill (LED bianchi in binario)
Fino a **15 slot per profilo**. I 4 LED bianchi mostrano il numero dello slot in binario, con il LED in alto = 1, poi 2, 4, 8. **Tutti spenti = nessuno slot.** L'isola mostra sempre il nome dello slot.

| Tipo di slot | Cosa succede |
|---|---|
| **Esegui** | Il **grigio** lancia subito l'azione: tasti, testo come `/compact` + Invio, e così via. |
| **Modello** | La **prossima dettatura** viene inserita nel testo dello slot al posto di `{{testo}}` (per esempio "Riassumi: {{testo}}"). |
| **LLM** | La **prossima dettatura** viene trasformata dall'LLM con l'istruzione dello slot (per esempio "Riscrivi come email"). |

- **Tocco:** slot successivo (nessuno → 1 → 2 → … → nessuno).
- **Doppio tocco:** slot precedente.
- **Pressione lunga:** nessuno slot.
- **Dopo l'uso** la selezione torna a "nessuno slot".
- **In modalità Comando** gli slot Modello e LLM vengono ignorati.

### Grigio: azioni e comandi vocali
- **Tocco:** esegue lo slot "Esegui" selezionato; se non c'è nessuno slot preme **Invio**.
- **Doppio tocco:** annulla l'ultimo inserimento (⌘Z, entro 30 s, stessa app).
- **Pressione lunga:** **interrompi** (intento `interrupt` del profilo, per impostazione predefinita **Esc**).
- **Premuto una volta mentre tieni la maniglia e parli: comando vocale.** La frase non viene scritta: va al modello locale, che sceglie le azioni da un elenco chiuso. Funziona in qualsiasi lingua e senza parole chiave da ricordare. Azioni possibili:
  - **testo e tasti** nel campo attivo: "vai a capo", "cancella l'ultima parola", "elenco puntato", "scrivi buongiorno a tutti";
  - **selezione:** se c'è del testo selezionato, "traducilo in inglese", "rendilo più corto", "mettilo in elenco puntato" lo sostituiscono con la versione trasformata; "cancellalo" lo elimina;
  - **canali:** "passa al progetto api", "vai a Codex" (basta una parte del nome);
  - **slot:** "lancia la review", "fai il compact";
  - **intenti del profilo:** "fermati", "nuova sessione" (vedi *Intenti*).
  
  Se il comando non è chiaro non succede nulla e la pillola lo dice. Le scorciatoie pericolose (⌘Q, ⌘W…) restano bloccate. Il modello locale impiega circa 1 s.

## Maniglia e accelerometro
| Gesto | Azione |
|---|---|
| Tieni premuta la maniglia, parla, rilascia | Dettatura, elaborata secondo la modalità e lo slot attivi |
| Doppio clic rapido sulla maniglia | Nuova riga (⇧↩) |
| Scuotimento breve | Annulla la dettatura in corso |
| Scuotimento forte per almeno 2 s | Cancella tutto (⌘A ⌫; nei terminali Ctrl+E Ctrl+U) |

## Pillola di stato e icona

- **Pillola in alto:**
  - **MacBook (notch, stile Dynamic Island, senza bordo):**
    - a sinistra del notch il puntino di stato: rosso con effetto **radar** in registrazione, bianco pulsante in elaborazione;
    - a destra il **tempo registrato**;
    - sotto una riga, per esempio "Registrazione · Migliorato · Riassumi".
  - **Altri schermi:** pillola nera sotto la barra dei menu con bordo chiaro sottile: [puntino] testo [tempo].
  - Gli avvisi (cambio di modalità o slot, "Scritto", errori) mostrano solo il testo. Comparsa e scomparsa con una dissolvenza.
- **Icona nella barra dei menu:** è **sempre quella scelta** (menu › Icona barra dei menu) e non cambia durante la registrazione, perché macOS mostra già il suo indicatore del microfono. Lo stato si legge nel tooltip e nella prima riga del menu.

## LED
| Stato | LED rossi | LED bianchi |
|---|---|---|
| Inattivo | Modalità corrente (un LED) | Slot in binario, oppure spenti |
| Registrazione | **KITT**: un LED che scorre su e giù | Invariati |
| Trascrizione ed elaborazione | Alternanza 1+3 / 2+4 | Invariati |
| Errore | Lampeggio dei 4 rossi per circa 1 s | — |

- **Mappa dei LED:** `device.ledMap` in `config.json` indica quale indice fisico corrisponde a [rosso 1…4, bianco 1…4]. Il valore predefinito `[0,1,2,3,4,5,6,7]` è stato verificato sul dispositivo il 2026-10-16. Impostazioni › Dispositivo › **Prova LED** accende i LED uno alla volta in quest'ordine logico, così si capisce se la mappa è giusta.
- **Velocità delle animazioni:** si regola con `device.ledAnimationMs`, predefinito 120 ms.

## Profili predefiniti
| Profilo | App | Slot |
|---|---|---|
| **Claude** | App Claude desktop | Nuova chat ⌘N · Interrompi Esc · Riassumi · Traduci in inglese · Spiega semplice · Brainstorming |
| **Agente di coding** | Terminale, iTerm2, Ghostty, VS Code, Warp | /compact · /clear · /review · Bug report · Commit message (LLM) |
| **Generale** | Tutte le altre | Email · Traduci EN · Elenco puntato · Più breve (tutti LLM) |

## Intenti
Un **intento** è un'azione con un nome che il profilo traduce nell'app: così "fermati" vale Esc in Claude e un'altra scorciatoia altrove. Si definiscono per profilo in `config.json`, sotto `intents`. Quelli senza associazione rispondono "non disponibile qui".

| Intento | Predefinito |
|---|---|
| `interrupt` | tasto Esc (anche pressione lunga del grigio) |
| altri (per esempio `newSession`, `approve`) | da definire per profilo: `"intents": {"newSession": {"type": "key", "keys": ["cmd+n"]}}` |

## Azioni configurabili
| `type` | Effetto |
|---|---|
| `key` (`keys`: lista) | Invia combinazioni come `cmd+a`, `shift+return`, `escape` |
| `text` (`text`) | Scrive il testo; un `\n` finale preme anche Invio |
| `cycleMode` / `resetMode` | Modalità successiva / predefinita |
| `nextSlot` / `previousSlot` / `clearSlot` | Navigazione degli slot |
| `runSlot` | Esegue lo slot "Esegui", altrimenti Invio |
| `nextChannel` / `previousChannel` / `bindChannel` | Canali (arancione) |
| `intent` (`name`) | Esegue l'intento del profilo |
| `undoLastInsertion`, `reinsertLast`, `cancel`, `editSelection` (comando vocale), `none` | Come in precedenza |

## Soglie dei gesti
| Parametro | Valore |
|---|---|
| `tapMaxMs` · `doubleTapMs` · `longPressMs` | 450 · 300 · 600 ms |
| `handleClickMaxMs` · `handleDoubleClickGapMs` | 280 · 400 ms |
| `shakeThreshold` · `shakeHoldMs` · `shakeHoldToleranceMs` | 0,5 · 2000 ms · 400 ms |
