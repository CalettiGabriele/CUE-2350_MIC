# ADR-001: Controllare l'EP-2350 con un agente installato in RAM tramite il REPL seriale

**Data:** 2026-10-15
**Stato:** Accettato per il collegamento USB-C. Il vincolo "niente di permanente sul mic" è superato da [ADR-003](adr-003-persistent-fxmic-firmware-via-romfs-json-hook.md) solo per l'installazione esplicita del firmware FXMic; con FXMic installato il ripristino dell'agente usa `fxmic.resume()` invece di `python_callback`.

## Contesto
FXMic Bridge deve ricevere da FX-MIC gli eventi di pulsanti, maniglia e accelerometro, e pilotarne i LED. Un vincolo esplicito è che il dispositivo resti sempre ripristinabile allo stato di fabbrica.

I test esplorativi (`logs/TEST_NOTES.md`) hanno mostrato tre cose:
- il firmware 1.0.9 espone via USB una console MicroPython libera mentre il mic funziona;
- tutta la logica dei pulsanti sta in `/rom/main.py` e riceve gli eventi con `ui.callback(python_callback)`;
- un callback sostitutivo installato in RAM riceve tutti gli eventi, inoltra il resto al codice di fabbrica e si rimuove in modo pulito.

Le altre opzioni hanno costi maggiori:
- un firmware personalizzato richiede di riflashare il mic;
- `config.json` e i campioni richiedono di scrivere su FX MIC DISK e non generano eventi verso il Mac;
- riconoscere codici audio dal jack funziona in una sola direzione e consuma gli slot dei campioni.

## Decisione
Abbiamo deciso di controllare il mic installando, a ogni connessione, un piccolo agente Python **solo in RAM** tramite la paste mode del REPL. L'agente:
- intercetta `ui.callback`;
- nasconde al codice di fabbrica i pulsanti quando l'app li gestisce;
- risponde a un polling per maniglia e accelerometro;
- accetta una lista chiusa di comandi, come `ui.leds` e `fx.load_preset`.

L'app non scrive mai sul flash, sulla ROM o su FX MIC DISK. Il ripristino è esplicito, con `ui.callback(python_callback)` alla chiusura dell'app, e comunque garantito dallo spegnimento del mic. Le versioni del firmware fuori dalla lista di compatibilità funzionano in sola lettura.

## Conseguenze

**Positive**
- Nessun rischio di danneggiare il dispositivo: basta spegnerlo e riaccenderlo per tornare allo stato di fabbrica.
- Eventi a bassa latenza (circa 4 ms tra un evento e l'altro) e controllo dei LED in entrambe le direzioni.
- Non serve alcuno strumento di flash né conoscere il firmware oltre all'API Python pubblica.

**Negative**
- Dipende dai nomi interni del firmware (`python_callback`, `fx_pos`, `sam_pos`, moduli `ui`, `fx`), che un aggiornamento ufficiale potrebbe cambiare.
- L'agente va reinstallato a ogni accensione o connessione, e la porta seriale non può essere condivisa con altri programmi.
- L'audio non passa da questo canale: serve una sorgente separata (jack con scheda audio, o il mic del Mac) fino all'eventuale spike M4.
