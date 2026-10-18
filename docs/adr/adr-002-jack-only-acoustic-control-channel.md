# ADR-002: Canale di controllo acustico a 12–19 kHz, con gesti riconosciuti sul mic

**Data:** 2026-10-16 (rev. 2)
**Stato:** Proposto, subordinato ai test T4 e T5 del One-Pager 002

## Contesto
ADR-001 porta eventi e LED sulla seriale USB. L'utente vuole poter usare FX MIC collegato al Mac **solo con il jack 3,5 mm**, che trasporta un unico segnale audio dal mic al Mac: deve portare sia la voce sia i comandi.

Con il firmware di fabbrica solo il grigio emette un suono, mentre arancione e bianco sono muti. Con il firmware FXMic (ADR-003) il mic può invece far suonare un campione a ogni gesto.

Whisper lavora a 16 kHz e scarta tutto sopra 8 kHz. Ogni codice dura circa 180 ms: se il mic inviasse pressioni e rilasci grezzi, il Mac li riceverebbe in ritardo e accodati, e doppi tocchi e pressioni lunghe non si riconoscerebbero più.

## Decisione
Abbiamo deciso che nel collegamento solo jack:
- **i gesti vengono riconosciuti sul mic** dal firmware FXMic, con le stesse regole e soglie di `GestureRecognizer`, copiate al momento dell'installazione;
- ogni gesto (e un battito periodico con la versione) viene inviato come **messaggio acustico** di 3 simboli a due toni nella banda **12–19 kHz**, scelti fra 4 simboli caricati nelle posizioni campione del mic;
- **lo stato resta sul Mac** (modalità, slot, profili): il mic non tiene stato, quindi un messaggio perso equivale a un tasto non premuto;
- il Mac registra di continuo a 48 kHz, decodifica i messaggi e passa la voce a Whisper senza filtri aggiuntivi;
- un unico codebook versionato genera i WAV dei simboli, la configurazione del firmware e la tabella del decoder;
- il trasporto si sceglie in automatico (USB se c'è la seriale, jack se arriva il battito) oppure a mano (`device.transport`).

## Conseguenze

**Positive**
- Tutte le funzioni dei gesti e della dettatura restano disponibili col solo jack; si perdono solo i LED pilotati dal Mac.
- I codici sono fuori dalla banda di Whisper e la loro struttura (preambolo, due toni, parità) non si può ottenere con la voce.
- Il Mac riusa profili, modalità, slot, LLM e isola senza modifiche, tramite un adattatore dai messaggi alle azioni.

**Negative**
- Canale in una sola direzione: modalità, slot, elaborazione ed errori non si vedono sui LED, ma solo nell'isola.
- Circa 180 ms di latenza in più per comando, e le soglie dei gesti richiedono di reinstallare il firmware quando cambiano.
- Registrazione sempre attiva sul Mac in modalità jack: consumo continuo e indicatore del microfono di macOS sempre acceso.
- Dipende dalla risposta in frequenza della catena audio del mic e della scheda audio, ancora da misurare (T5).
