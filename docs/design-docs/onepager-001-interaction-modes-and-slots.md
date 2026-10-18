# One-Pager 001 — Modalità di interazione (arancione), slot di comandi (bianco) e LED di stato

> Data: 2026-10-16 · Stato: **Approvato e implementato (app 0.3.0)**, la mappa dei LED è da verificare sul dispositivo · Riferimenti: TDD v1 §3.2–3.3, `docs/GESTURES.md`

## Problema
L'uso attuale di arancione e bianco (Modalità × Stile, mostrati come barre di LED) non convince:
- i LED indicano solo un numero e non permettono di capire cosa è attivo;
- gli Stili servono poco;
- manca la possibilità di **lanciare comandi e skill**, che era l'obiettivo iniziale;
- serve **massima personalizzazione** da parte dell'utente.

Mancano anche un feedback sul mic durante la registrazione e un'azione al posto della semplice selezione di prompt. Lo strumento più usato è l'**app Claude desktop**.

## Proposta

### 1. Arancione = modalità di interazione (4 modalità, un LED rosso ciascuna)
| LED rosso | Modalità | Cosa succede alla dettatura |
|---|---|---|
| 1 | **Dettato** | Trascrizione grezza, come l'attuale Raw. Nessun LLM. |
| 2 | **Migliorato** | Trascrizione più LLM con il prompt di miglioramento del profilo (punteggiatura, chiarezza…). |
| 3 | **Comando** | Ciò che dici diventa un'**azione** e non un testo. Per esempio "fai un elenco puntato" inserisce "- ", "vai a capo" invia ⇧↩, "cancella l'ultima frase" invia i tasti relativi. L'LLM restituisce azioni strutturate da un vocabolario chiuso: testo, tasti, ripeti, seleziona. |
| 4 | **Computer Use** | Riservata: un agente AI usa il Mac al tuo posto. **Non implementata ora**: selezionarla mostra "non ancora disponibile". |

- **Tocco:** passa alla modalità successiva.
- **Pressione lunga:** torna a Dettato.
- **Per profilo:** si sceglie quali modalità sono attive (per esempio Comando solo dove serve) e qual è la predefinita.

### 2. Bianco = slot di comandi e skill (fino a 15 per app, codificati in binario sui 4 LED)
Ogni combinazione dei 4 LED bianchi è uno slot: spenti = nessuno slot, poi 1…15 in binario. **L'isola mostra sempre il nome dello slot**, perché la codifica binaria a occhio non si legge.
- **Navigazione:** tocco = slot successivo, doppio tocco = precedente, pressione lunga = nessuno slot.
- **Due tipi di slot, scelti slot per slot:**
  - **Esegui:** il grigio invia subito testo, tasti o una sequenza. Per esempio "Nuova chat" (⌘N), "Interrompi" (Esc), un testo come `/compact` con Invio, o il testo che lancia una skill.
  - **Modello:** la prossima dettatura viene inserita nel modello, per esempio `Usa la skill "riassunto" su: {{testo}}` oppure `Traduci in inglese: {{testo}}`.
- **Dopo l'uso:** la selezione torna a "nessuno slot", e i LED bianchi si spengono.
- **Grigio:** tocco = esegue lo slot selezionato; se non c'è nessuno slot, Invio come ora.

### 3. LED di stato
| Stato | LED rossi | LED bianchi |
|---|---|---|
| Inattivo | Modalità corrente (1 LED) | Slot corrente (binario) o spenti |
| Registrazione | **"KITT"**: un LED che scorre avanti e indietro, circa 8 passi al secondo | Invariati |
| Elaborazione LLM | Lampeggio alternato 1+3 / 2+4 *(proposta)* | Invariati |
| Errore | 3 lampeggi di tutti i rossi *(proposta)* | — |

## Design (sintesi)
- **LED in modalità manuale.** Si usa `ui.led_control(0)` con `ui.led_level(i, livello)`, e l'app pilota singolarmente gli 8 LED. Le barre di `ui.leds()` non bastano più. Le animazioni vengono generate dal Mac (timer a circa 8 Hz, pochi byte per passo) oppure da una funzione dell'agente in RAM, per non intasare la seriale. **Prerequisito:** mappare quale indice da 0 a 7 corrisponde a quale LED fisico, con un test guidato dal pulsante grigio di circa 1 minuto.
- **Configurazione (schema v2).** Per profilo:
  - `interaction`: modalità abilitate, predefinita, prompt di miglioramento e suggerimenti per Comando;
  - `slots`: fino a 15 elementi `{name, kind: run|template, action | template}`.
  
  Gli Stili non sono più usati, e i vecchi `modes`/`styles` vengono letti e convertiti automaticamente (il primo prompt diventa quello di "Migliorato").
- **Modalità Comando:**
  - risposta JSON con `{"actions":[{"type":"text","text":"- "}, {"type":"key","keys":["shift+return"]}]}`, validata;
  - sono ammessi solo i tasti dell'elenco consentito, senza ⌘Q, ⌘W o simili;
  - se la risposta non è valida non viene eseguito nulla e compare un avviso;
  - il profilo può aggiungere suggerimenti specifici, per esempio "in Claude desktop il campo accetta Markdown".
- **Editor nelle Impostazioni:** scheda Profili con le sezioni "Modalità" e "Slot", con riordino, test dello slot e importazione/esportazione.
- **Profilo predefinito per Claude desktop** (`com.anthropic.claudefordesktop`), con slot di esempio:
  - Esegui: Nuova chat ⌘N, Interrompi Esc;
  - Modello: "Riassumi: {{testo}}", "Traduci in inglese: {{testo}}", "Spiegami come a un principiante: {{testo}}".

## Alternative considerate
- **Barre come ora:** scartate su tua indicazione (si accende solo il LED dello slot).
- **Solo 4 slot, uno per LED:** scartato a favore delle 15 combinazioni, al costo di affidarsi all'isola per leggere il nome.
- **Selezione a voce dello slot** ("slot traduci"): rimandata come estensione.
- **Menu sull'isola con scorrimento per inclinazione:** rimandato; potrà convivere con la navigazione a tocchi.

## Rischi e punti aperti
1. **15 slot da scorrere a tocchi** sono tanti: andare dall'1 al 15 richiede 15 tocchi. Mitigazioni:
   - doppio tocco per tornare indietro;
   - pressione lunga per azzerare;
   - eventuale scorrimento rapido tenendo premuto. **Da confermare.**
2. **Mappa e luminosità dei LED** ancora sconosciute: serve il test guidato. Se la luminosità non è regolabile, l'animazione di elaborazione resta un lampeggio on/off.
3. **Affidabilità della modalità Comando:** dipende dal modello locale (qwen3.5:4b). Si parte con un vocabolario piccolo e un'anteprima nelle Impostazioni.
4. **Computer Use:** richiede un agente esterno (per esempio Claude con computer use). Va valutato a parte (sicurezza, permessi, costi). Per ora è un segnaposto.
5. **Compatibilità:** i `config.json` esistenti vengono migrati; il backup `config.json.bak` viene creato al primo salvataggio.

## Piano
1. Test di mappatura dei LED (interattivo, circa 1 minuto).
2. Schema v2, migrazione e test unitari.
3. LED manuali: modalità, slot binari, animazioni KITT, elaborazione ed errore.
4. Arancione → modalità (Dettato, Migliorato, Comando; Computer Use come segnaposto).
5. Bianco → slot Esegui/Modello, grigio = esegui.
6. Editor nelle Impostazioni e profilo Claude desktop di esempio.
7. Aggiornamento di `GESTURES.md` e del TDD, poi verifica sul dispositivo.
