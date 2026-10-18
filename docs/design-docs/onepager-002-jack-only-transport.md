# One-Pager 002 — Collegamento solo jack: firmware FXMic installabile e codici acustici

> Data: 2026-10-16 (rev. 2, dopo i test ROMFS) · Stato: **Bozza, in attesa di revisione** · Nessun codice dell'app implementato
> Riferimenti: ADR-001, ADR-002, ADR-003, TDD v1 §3.6, `docs/GESTURES.md`, `logs/TEST_NOTES.md` (sezioni "ROMFS feasibility probe" e seguenti), `backup/rom/`

## 1. Obiettivo
Usare FX MIC collegato al Mac **solo con il jack 3,5 mm** e mantenere tutte le funzioni attuali. Si accetta di perdere solo i LED pilotati dal Mac.

Ogni pulsante e ogni gesto emette un **suono codificato**, impossibile da produrre con la voce, che l'app riconosce come comando. Lo stato (modalità corrente, slot selezionato) lo tiene l'app, come oggi.

Requisiti dell'utente:
- dalle **Impostazioni** si installa il firmware FXMic sul mic e si torna al firmware di fabbrica, via USB-C, in modo semplice e reversibile;
- l'app passa da sola dalla modalità USB-C alla modalità jack in base a cosa è collegato, e la scelta si può anche forzare a mano.

## 2. Cosa hanno dimostrato i test (2026-10-16)
| Domanda | Esito | Dettaglio |
|---|---|---|
| La partizione `/rom` è riscrivibile via USB? | **Sì** | ROMFS da 128 KB (32 blocchi da 4 KB); cancellazione + scrittura + rilettura completa verificata con SHA-256, 6–10 s. `/rom` si rimonta senza riavvio. |
| Modificare `/rom/main.py` cambia il comportamento? | No | All'avvio il firmware esegue la copia di fabbrica **integrata** (`teenage`); `/rom/main.py` è solo leggibile. |
| `boot.py` / `main.py` in `/rom` o sul disco vengono eseguiti? | No | Provati `/rom/boot.py`, `/fat/boot.py`, `/fat/main.py`, `/fat/teenage.py`. |
| Esiste un punto di avvio permanente? | **Sì: `/rom/json.py`** | Il codice di fabbrica fa `import json` come seconda istruzione; un `json.py` in `/rom` prende il posto del modulo integrato e viene eseguito a **ogni accensione**. |
| Il nostro codice può girare senza bloccare il mic? | **Sì** | Un ciclo avviato da `json.py` riceve tutti i pulsanti; Ctrl-C via USB lo interrompe sempre e la console torna libera. |
| Il firmware manda eventi periodici? | **Sì** (T3) | Con il nostro callback registrato arrivano di continuo messaggi di tipo 3, circa ogni 16 ms (12–26 ms a riposo), più i tipi 16–20 (ADC). Il callback fa da timer: niente ciclo in primo piano, la console resta libera. |
| Il nostro codice prende il controllo all'avvio? | **Sì** (T2) | `json.py` avvia FXMic e interrompe il codice di fabbrica con un'eccezione: callback nostro, tutti i pulsanti ricevuti, disco montato, primo LED rosso acceso. |
| I simboli si caricano da `/rom`? | **No** (T4) | `spl.load_wav` rifiuta i file ROMFS e `BytesIO`; accetta i file FAT (≈0,5 ms ciascuno). I simboli vanno in `/fat/.fxmic/`, scritti dal Mac. |
| La via di fuga "arancione premuto all'accensione" funziona? | **No** (T1) | Quando `json.py` parte i pulsanti non risultano ancora premuti. Il ritorno alla logica di fabbrica eseguendo `/rom/main.py` invece funziona. |
| Limiti di memoria | 64 KB di heap | Senza modulo `gc`. Trasferimenti a blocchi di 256 B, niente strutture che crescono nei callback. |

Lezioni da rispettare:
- **mai il riavvio software (Ctrl-D):** il modulo di avvio `_boot_fat` va in errore e il disco non viene montato;
- **mai scrivere sul disco FX MIC DISK dal mic** mentre può essere montato sul Mac: il disco si è già danneggiato una volta (riparato dal backup);
- scrivere `/rom` solo con memoria sufficiente, cioè subito dopo un'accensione.

## 3. Soluzione

### 3.1 Il firmware FXMic (sul mic)
È un piccolo programma MicroPython che vive nella partizione `/rom`, accanto ai file di fabbrica, che restano intatti:

| File in `/rom` | Ruolo |
|---|---|
| `README.md`, `main.py` | invariati, quelli di fabbrica |
| `json.py` | **aggancio di avvio**: rimette a disposizione il `json` integrato, controlla la via di fuga, avvia `fxmic` |
| `fxmic.py` | logica: riconoscimento dei gesti, invio dei codici, LED locali, battito |
| `fxmic_cfg.py` | soglie dei gesti e versione del codebook, generate dall'app al momento dell'installazione |
| `fxmic_factory.mpy` | copia precompilata di `main.py`, per tornare alla logica di fabbrica senza compilare 6,6 KB al volo (34 KB di heap) |

I 4 simboli acustici (`s0.wav` … `s3.wav`, circa 60 ms, 48 kHz, 16 bit mono) stanno invece **sul disco**, in `/fat/.fxmic/`, perché `spl.load_wav` accetta solo file FAT (T4). Li scrive il Mac durante l'installazione e li cancella col ripristino; il mic li legge soltanto.

**Avvio.** All'accensione il codice di fabbrica importa `json`: parte il nostro `json.py`.
- `json.py` registra il `json` integrato in `sys.modules`, avvia `fxmic` e interrompe il codice di fabbrica con un'eccezione dedicata, così questo non sovrascrive il callback (verificato in T2).
- `fxmic` carica i 4 simboli da `/fat/.fxmic/`, imposta il preset pulito per la voce, accende il primo LED rosso e registra il proprio callback. Gli eventi periodici (circa ogni 16 ms) gli fanno da timer.
- **Via di fuga:** se l'**arancione resta premuto nei primi 3 secondi** dopo l'accensione con la leva, `fxmic` si ferma ed esegue la logica di fabbrica (`fxmic_factory`) fino allo spegnimento. La lettura dell'arancione nell'istante dell'avvio non funziona (T1).

**Cosa fa a regime.**
- **Riconosce i gesti sul mic** con le stesse regole e soglie di `GestureRecognizer` (copiate in `fxmic_cfg.py`): tocco, doppio tocco e pressione lunga di arancione, bianco e grigio; inizio e fine della maniglia; doppio clic della maniglia; scuotimento breve e lungo (2 s); grigio premuto a maniglia premuta.

  Va fatto sul mic perché ogni codice dura circa 180 ms: se il Mac ricevesse pressioni e rilasci separati, i tempi tra un evento e l'altro si allungherebbero e i doppi tocchi non si riconoscerebbero più.
- **Invia un codice per ogni gesto.** Nessuno stato sul mic: il Mac tiene modalità e slot, quindi un codice perso equivale a un tasto non premuto, senza disallineamenti.
- **Battito** ogni 5 s a riposo, che contiene la versione del firmware. Serve al Mac per sapere che il mic è collegato via jack e acceso.
- **LED locali**, facoltativi:
  - KITT mentre la maniglia è premuta;
  - un breve lampeggio a ogni codice inviato, come conferma.

  Modalità e slot non si possono mostrare sui LED, perché lo stato è sul Mac e il jack non porta dati verso il mic.

### 3.2 Il canale acustico (ADR-002)
- Banda 12–19 kHz, sopra quella usata da Whisper (16 kHz di campionamento, quindi tutto sopra 8 kHz viene scartato): nessun disturbo alla trascrizione.
- 4 simboli a due toni. Un messaggio è composto da 3 simboli (circa 180 ms): fino a 64 messaggi, ne servono circa 20. Il primo simbolo fa da sincronismo, gli altri due identificano il messaggio, più un controllo di parità.
- Il Mac registra di continuo dall'ingresso scelto (48 kHz), decodifica i codici e taglia la voce tra "maniglia premuta" e "maniglia rilasciata". Il pre-roll viene da solo.
- Frequenze, durate e soglie si fissano in J1, con la scheda audio.

### 3.3 L'app (Mac)
**Impostazioni › Dispositivo › Firmware del mic** (richiede la USB-C dati):

| Elemento | Comportamento |
|---|---|
| Stato | **Fabbrica** (impronta 264e54d4…), **FXMic vX.Y**, oppure **Sconosciuto** (impronta mostrata, nessuna scrittura consentita) |
| **Installa FXMic** | Vedi la procedura sotto |
| **Ripristina fabbrica** | Scrive l'immagine di fabbrica salvata, verifica e rimonta. Chiede uno spegnimento e riaccensione, perché il codice di fabbrica integrato riparta da zero. |
| Aggiorna | Quando la versione installata è più vecchia di quella inclusa nell'app, o quando cambiano le soglie dei gesti |

Procedura di **Installa FXMic**:
1. controlla firmware 1.0.9, impronta della partizione nota e memoria libera (blocco libero più grande ≥ 2 KB; altrimenti chiede di spegnere e riaccendere);
2. **la prima volta** copia la partizione attuale in `~/Library/Application Support/FXMicBridge/firmware/factory-1.0.9.bin` e ne verifica l'impronta;
3. costruisce l'immagine (file di fabbrica + file FXMic), la scrive a blocchi di 256 B, rilegge tutta la partizione e confronta l'impronta, poi rimonta `/rom`;
4. chiede di spegnere e riaccendere il mic per attivare il firmware.

**Collegamento: Automatico / Solo USB-C / Solo jack** (Impostazioni › Dispositivo):

| Situazione | Automatico |
|---|---|
| Porta seriale del mic presente | **USB-C**, come oggi. Se è installato FXMic, l'app lo mette in pausa e installa il suo agente in RAM (LED pilotati dal Mac compresi). |
| USB-C staccata, battito presente sull'ingresso audio | **Jack**: arriva il battito o un codice valido |
| Né l'una né l'altro | "Mic non collegato"; resta la dettatura di riserva con Opzione destro |

- **Solo USB-C:** ignora i codici acustici.
- **Solo jack:** non apre la porta seriale, utile con un caricatore o se si vuole provare il jack con il cavo collegato.

**Passaggio da USB a jack senza riaccendere.** Quando l'app chiude la sessione USB, il suo agente riavvia FXMic. Se il cavo viene staccato all'improvviso, l'agente se ne accorge perché il Mac smette di interrogarlo: dopo 3 s senza richieste riavvia FXMic da solo. Il tempo è misurato con gli eventi periodici del firmware (test T3 e T6).

**Feedback senza LED.** In jack l'isola sul notch resta l'unico feedback per modalità, slot, elaborazione ed errori. Già oggi mostra tutto.

## 4. Cosa si conserva in jack (con FXMic installato)
| Funzione | Jack | Note |
|---|---|---|
| Dettatura push-to-talk | ✅ | inizio e fine dai codici della maniglia; la voce passa dallo stesso cavo |
| Doppio clic della maniglia → nuova riga | ✅ | riconosciuto sul mic |
| Scuotimento breve → annulla, lungo → cancella tutto | ✅ | riconosciuto sul mic |
| Arancione: modalità successiva, pressione lunga → predefinita | ✅ | stato sul Mac |
| Bianco: slot successivo/precedente/nessuno, fino a 15 | ✅ | stato sul Mac |
| Grigio: tocco, doppio tocco, pressione lunga, durante la dettatura | ✅ | |
| Modalità, slot, profili per app, LLM, isola, cronologia | ✅ | invariati, solo sul Mac |
| LED di modalità, slot, elaborazione ed errore | ❌ | accettato; restano KITT e lampeggio di conferma gestiti dal mic |
| Latenza dei comandi | ⚠️ | circa 180 ms in più per il codice, più la finestra del doppio tocco come oggi |

## 5. Modifiche al modello dati
`config.json` schema 3, solo aggiunte con valori predefiniti:
```json
"device": {
  "transport": "auto",
  "jack": { "codebook": "fxmic-v1", "heartbeatSec": 5, "detectionThresholdDb": 20 },
  "firmware": { "install": "fxmic", "factoryBackup": "firmware/factory-1.0.9.bin" }
}
```
- `transport`: `auto` (predefinito), `usb`, `jack`.
- Le soglie dei gesti restano in `GestureSettings` e vengono copiate in `fxmic_cfg.py` a ogni installazione o aggiornamento.

## 6. Nuovi contratti
- **Codebook `fxmic-v1`:** simboli, preambolo e tabella messaggio → gesto. È un unico file nel repository (`firmware/fxmic/codebook.json`), da cui si generano sia i WAV e `fxmic_cfg.py` sia la tabella del decoder sul Mac.
- **Messaggi (circa 20):** `hello(version)`, `heartbeat`, `handleDown`, `handleUp`, `handleDoubleClick`, `tap|doubleTap|longPress` × arancione/bianco/grigio, `greyDuringPTT`, `shakeShort`, `shakeHold`.
- **API del firmware via REPL** (solo in USB): `fxmic.version()`, `fxmic.pause()`, `fxmic.resume()`.
- **Agente USB:** il ripristino non presuppone più `python_callback`. Con FXMic installato si ripristina con `fxmic.resume()`, con il firmware di fabbrica come oggi.
- **App:**
  - astrazione `DeviceTransport` con `UsbSerialTransport` (l'attuale `DeviceService`) e `JackTransport` (decoder in `FXMicCore`, testabile con WAV sintetici);
  - un selettore automatico tra i due trasporti;
  - `FirmwareManager`, che fa lettura, verifica, scrittura e rimontaggio della ROMFS.

## 7. Compatibilità all'indietro
- **Senza FXMic installato:** nulla cambia; USB-C funziona come oggi.
- **Con FXMic installato:**
  - il mic non funziona più come microfono a effetti autonomo: i campioni di fabbrica sono sostituiti in RAM dai simboli e `config.json` sul disco viene ignorato. Basta l'arancione tenuto premuto all'accensione o "Ripristina fabbrica";
  - sul disco FX MIC DISK l'app aggiunge solo la cartella nascosta `.fxmic` con i 4 simboli, scritta dal Mac e rimossa dal ripristino. Il mic non scrive mai sul disco.
- **Ultima risorsa:** reinstallare il firmware ufficiale con la modalità BOOTSEL dell'RP2350, che non si può cancellare. Resta da procurarsi il file UF2 1.0.9 e da verificare se ripristina anche `/rom` (test T9).

## 8. Test rimasti
| ID | Test | Serve | Criterio di uscita |
|---|---|---|---|
| T1 | Via di fuga. Prima versione (arancione letto all'avvio) **fallita**; il ritorno alla fabbrica via `/rom/main.py` è verificato. Da ripetere con la finestra di 3 s | USB | 3 prove su 3; senza arancione FXMic parte |
| T2 | Avvio: **superato** in 2 accensioni su 2. Resta da ripetere fino a 10 su 10 con il firmware vero | USB | callback di FXMic attivo dopo 10 accensioni su 10 |
| T3 | Eventi periodici: **superato**, circa 16 ms (12–26 ms a riposo, fino a 119 ms durante l'avvio) | USB | — |
| T4 | Simboli: da `/rom` **no**, da `/fat/.fxmic/` **sì** (≈0,5 ms ciascuno); `spl.trigger` non blocca (0,05–0,2 ms). Continuità della sequenza da verificare sul jack in T5 | USB / scheda audio | sequenza senza vuoti > 5 ms |
| T5 | J0 + J1 con scheda audio: banda passante, livelli, riconoscimento, falsi positivi, codici durante il parlato | scheda audio | ≥ 99 % su 200 gesti; 0 falsi positivi in 30 min di voce, musica e rumore |
| T6 | Coesistenza USB: pausa e ripresa, agente adattato, ripresa automatica dopo il distacco del cavo | USB | jack attivo entro 5 s dal distacco, 5 prove su 5 |
| T7 | Installa e ripristina dall'app, fino in fondo, compreso il controllo della memoria | USB | 5 cicli completi con impronta verificata |
| T8 | Batteria: risparmio energetico dopo 5 min e spegnimento dopo 20 con FXMic attivo; il Mac rileva l'assenza del battito | jack | stato "in standby" mostrato entro 10 s |
| T9 | Recupero estremo: file UF2 ufficiale, cosa ripristina BOOTSEL | — | procedura documentata |

Stato al 2026-10-16: T2, T3 superati; T4 superato con i simboli sul disco; T1 da ripetere con la nuova via di fuga durante l'implementazione. T5 e T8 quando arriva la scheda audio; T6 e T7 durante l'implementazione.

## 9. Rischi
- **Aggiornamento ufficiale del firmware:** potrebbe cambiare l'ordine degli import o togliere ROMFS. L'app riconosce le versioni e rifiuta di scrivere su quelle sconosciute.
- **Memoria (64 KB):** il firmware FXMic deve restare piccolo, con buffer fissi e nessuna allocazione nei callback.
- **Falsi positivi** da toni acuti esterni: preambolo, parità e soglie, misurati in T5.
- **Autonomia a batterie:** con FXMic attivo potrebbe ridursi. Si misura in T8.

---
**ADR collegati:** ADR-003 (firmware persistente in `/rom/json.py`), ADR-002 (canale acustico con gesti riconosciuti sul mic), ADR-001 (agente in RAM, che resta per la modalità USB).
