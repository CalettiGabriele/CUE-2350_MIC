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

### Arancione: modalità di interazione (LED rossi, uno per modalità)
| LED rosso | Modalità | La dettatura… |
|---|---|---|
| 1 | **Dettato** | viene scritta così com'è. |
| 2 | **Migliorato** | passa dall'LLM locale con l'istruzione "Migliorato" del profilo. |
| 3 | **Comando** | diventa un'azione: "fai un elenco puntato", "vai a capo", "cancella l'ultima parola"…. L'LLM restituisce tasti e testo da un elenco chiuso; scorciatoie pericolose come ⌘Q e ⌘W sono bloccate. |
| 4 | **Computer Use** | *non ancora disponibile*: la dettatura finisce solo in cronologia. |

**Tocco:** modalità successiva (solo quelle abilitate nel profilo). **Pressione lunga:** torna alla modalità predefinita del profilo.

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

### Grigio
- **Tocco:** esegue lo slot "Esegui" selezionato; se non c'è nessuno slot preme **Invio**.
- **Doppio tocco:** annulla l'ultimo inserimento (⌘Z, entro 30 s, stessa app).
- **Pressione lunga:** riscrive l'ultimo testo grezzo; nei terminali preme **Esc**.
- **Premuto durante la dettatura:** **modifica della selezione**, cioè l'istruzione dettata viene applicata al testo selezionato.

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

## Azioni configurabili
| `type` | Effetto |
|---|---|
| `key` (`keys`: lista) | Invia combinazioni come `cmd+a`, `shift+return`, `escape` |
| `text` (`text`) | Scrive il testo; un `\n` finale preme anche Invio |
| `cycleMode` / `resetMode` | Modalità successiva / predefinita |
| `nextSlot` / `previousSlot` / `clearSlot` | Navigazione degli slot |
| `runSlot` | Esegue lo slot "Esegui", altrimenti Invio |
| `undoLastInsertion`, `reinsertLast`, `cancel`, `editSelection`, `none` | Come in precedenza |

## Soglie dei gesti
| Parametro | Valore |
|---|---|
| `tapMaxMs` · `doubleTapMs` · `longPressMs` | 450 · 300 · 600 ms |
| `handleClickMaxMs` · `handleDoubleClickGapMs` | 280 · 400 ms |
| `shakeThreshold` · `shakeHoldMs` · `shakeHoldToleranceMs` | 0,5 · 2000 ms · 400 ms |
