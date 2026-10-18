# ADR-003: Firmware FXMic persistente nella partizione ROMFS tramite `/rom/json.py`

**Data:** 2026-10-16
**Stato:** Proposto. Fattibilità verificata sul dispositivo (T2, T3, T4 superati il 2026-10-16); resta da rifare la via di fuga (T1).

## Contesto
Per usare FX MIC solo con il jack, il mic deve emettere un codice acustico a ogni gesto (ADR-002). Serve quindi codice nostro sul dispositivo, attivo a ogni accensione e senza USB.

ADR-001 vietava modifiche permanenti. Ora l'utente chiede esplicitamente un'installazione permanente, purché sia reversibile dalle Impostazioni dell'app.

I test del 2026-10-16 (`logs/TEST_NOTES.md`) hanno mostrato quattro cose:
- la partizione `/rom` (ROMFS, 128 KB) si riscrive e si verifica via REPL USB in 6–10 s, e si rimonta senza riavvio;
- il firmware 1.0.9 all'avvio esegue sempre il modulo integrato `teenage`. `/rom/main.py`, `/rom/boot.py` e `boot.py`/`main.py`/`teenage.py` sul disco **non** vengono eseguiti;
- `teenage` esegue `import json` come seconda istruzione, e un `json.py` in `/rom` prende il posto del modulo integrato: **viene eseguito a ogni accensione**;
- un ciclo avviato da lì riceve gli eventi dei pulsanti e lascia sempre interrompibile la console (Ctrl-C).

Alternative valutate:
- firmware UF2 ricostruito: mancano i sorgenti dei moduli audio di Teenage Engineering;
- agente in RAM caricato via USB a ogni accensione: costringe a collegare la USB ogni volta;
- file sul disco FX MIC DISK: non vengono eseguiti, e il disco si è dimostrato fragile.

## Decisione
Abbiamo deciso di installare, **solo su richiesta esplicita dalle Impostazioni**, un firmware FXMic composto da file aggiunti alla partizione ROMFS (`json.py`, `fxmic.py`, `fxmic_cfg.py`, `fxmic_factory.mpy`), lasciando invariati i file di fabbrica.
- `json.py` è l'aggancio di avvio. Registra il `json` integrato, avvia FXMic e interrompe il codice di fabbrica con un'eccezione dedicata, così il callback resta a FXMic (T2).
- L'app scrive la ROMFS solo dopo aver controllato la versione del firmware, l'impronta della partizione e la memoria libera. Salva la partizione di fabbrica del dispositivo prima della prima scrittura, rilegge tutta la partizione per verificarla e non usa mai il riavvio software.
- "Ripristina fabbrica" riscrive l'immagine salvata (impronta 264e54d4…f1a1c4 per la 1.0.9).
- I 4 simboli audio stanno in `/fat/.fxmic/`, perché `spl.load_wav` accetta solo file FAT (T4). Li scrive il Mac durante l'installazione e li rimuove il ripristino; il firmware FXMic non scrive mai sul disco.
- La via di fuga è l'arancione tenuto premuto nei primi 3 secondi dopo l'accensione: FXMic esegue allora la logica di fabbrica precompilata. La lettura dei pulsanti nell'istante dell'avvio non funziona (T1).

## Conseguenze

**Positive**
- Il mic funziona solo col jack a ogni accensione, senza USB, e il codice gira sul mic stesso: gesti e LED locali.
- Si torna alla fabbrica in pochi secondi dall'app, oppure temporaneamente con l'arancione all'accensione.
- I file di fabbrica restano intatti e non si riflasha il firmware; sul disco si aggiunge solo la cartella nascosta `.fxmic`.

**Negative**
- Dipende da un dettaglio interno del firmware 1.0.9: l'ordine degli import di `teenage` e il fatto che ROMFS preceda i moduli integrati. Un aggiornamento ufficiale può romperlo; l'app rifiuta le versioni sconosciute.
- Heap di soli 64 KB e niente `gc`: il firmware deve essere minimale, e le scritture vanno fatte a blocchi piccoli e subito dopo un'accensione.
- Con FXMic attivo il mic perde l'uso autonomo come microfono a effetti: campioni e `config.json` di fabbrica non sono usati.
- Rischio di firmware non avviabile in caso di bug: mitigato dalla via di fuga con l'arancione, dalla console sempre interrompibile e, in ultima istanza, da BOOTSEL con il file UF2 ufficiale, ancora da procurare.
