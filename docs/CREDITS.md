# ((C)) credits

*The colophon of chapter 8: who made this, what it stands on, and what it is not.*

<br>

## ((C.1)) made by

**Gabriele Caletti** — designed and built CUE-2350 MIC, from the mic's RAM-only agent to the island
on your screen, because the FX-MIC deserved a second life as a remote for talking to your agent.

- GitHub: [@CalettiGabriele](https://github.com/CalettiGabriele)
- LinkedIn: [Gabriele Caletti](https://www.linkedin.com/in/gabriele-caletti-a952301b6)
- Repository: [CalettiGabriele/CUE-2350_MIC](https://github.com/CalettiGabriele/CUE-2350_MIC)

Issues and pull requests are welcome. By contributing you agree that your work is released under
the same MIT license.

<br>

## ((C.2)) built with

| what | by | used for | license |
|---|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Argmax | speech-to-text, on your Mac | MIT |
| [Whisper](https://github.com/openai/whisper) models | OpenAI | the speech models WhisperKit runs | MIT |
| [Ollama](https://ollama.com) | Ollama | default local server for the voice command and LLM slots | MIT |
| [Barlow](https://github.com/jpt/barlow) | The Barlow Project Authors | titles and display type | SIL OFL 1.1 |
| [IBM Plex Mono](https://github.com/IBM/plex) | IBM Corp. | chrome: labels, numerals, status | SIL OFL 1.1 |

Each project keeps its own license; check them before redistributing. The fonts ship with the app
(`app/Resources/Fonts`, see its [NOTICE](../app/Resources/Fonts/NOTICE.md)).

<br>

## ((C.3)) what the MIT license covers

The source code, the documentation and the illustrations in this repository are released under the
[MIT license](../LICENSE). It does **not** cover:

- **The fonts above**, which keep their own license.
- **The teaser video's music and sound effects** (`videos/fxmic-bridge-teaser`): they come from
  third-party libraries (HeyGen's music library, Openverse) and keep the terms of their sources.
- **Anyone's trademarks**: see below.

<br>

## ((C.4)) not affiliated

CUE-2350 MIC is an independent, unofficial project. It is **not affiliated with, endorsed by or
sponsored by teenage engineering**. "teenage engineering", "EP-2350" and "FX-MIC" are used only to
say which hardware this app works with.

- No logo, photograph, illustration or firmware file from teenage engineering is used or
  distributed here. The mic in the app and in the README is **redrawn from scratch** as a style
  homage, and the "chapter 8" idea is a tribute to the look of the mic's user guide.
- The app never writes to the mic's flash, ROM or FX MIC DISK. It talks to the mic through a small
  agent that lives only in its RAM and disappears when you quit the app or switch the mic off.
- Thank you, teenage engineering, for making an object worth building this for.

If you represent teenage engineering and would like something changed, please open an issue or write
to the author through GitHub: it will be taken care of promptly.
