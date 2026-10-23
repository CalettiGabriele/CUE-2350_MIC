// Visible FAQ on the home page and the FAQPage structured data, from one source.
// Facts come from the project README and docs/GESTURES.md; keep them in step.
export const FAQ: { q: string; a: string }[] = [
  {
    q: 'What is CUE-2350 MIC?',
    a: 'A free, open-source macOS menu-bar app that turns the EP-2350 FX-MIC into a voice and gesture remote for your Mac and your coding agent. Hold the handle, talk, release: the words are written where your cursor is.',
  },
  {
    q: 'What hardware and software do I need?',
    a: 'A Mac with Apple silicon on macOS 14 or later, an EP-2350 FX-MIC (sometimes written EP2350 or FX MIC) and a USB-C data cable. For voice commands and LLM rewrites, a local model server such as Ollama.',
  },
  {
    q: 'Does it work with Claude Code and other coding agents?',
    a: 'Yes. It types into any text field, so it works with Claude Code, Codex and any other agent, in the terminal or in their desktop apps. The white button’s skills and commands follow the app in front: /compact, /clear and /review in the terminal, “rewrite as email” everywhere else.',
  },
  {
    q: 'What are channels?',
    a: 'Up to four places you keep going back to, on the orange button, one red LED each: a Claude Code session, a Claude chat or project, a Codex thread, a document or an app. Tap orange to jump to the next one; long-press to add the window in front. On any other app you are free: the words go where your cursor is, with no jump. Hold orange for 3 seconds to clear all four.',
  },
  {
    q: 'What is a voice command?',
    a: 'Press grey once while you talk and the sentence is not written: a local model turns it into actions — keys, a rewrite of the selected text (“translate it into English”), a jump to a channel (“go to Codex”), a skill (“run the review”). It works in any language, with nothing to memorise, and does nothing if the request is not clear.',
  },
  {
    q: 'Is my voice sent to the cloud?',
    a: 'No. Speech-to-text runs on your Mac with WhisperKit, and the optional language model runs on your Mac too. Audio is never saved. Nothing leaves your computer unless you point the language model at a remote server yourself.',
  },
  {
    q: 'Does it change the microphone’s firmware?',
    a: 'No. The app talks to the mic through a tiny agent that lives only in its RAM. Quit the app or switch the mic off and it is factory-fresh again.',
  },
  {
    q: 'Can I use it without the FX-MIC?',
    a: 'Yes, as a fallback: hold the right Option key and talk.',
  },
  {
    q: 'Is it free? Which license?',
    a: 'Yes. CUE-2350 MIC is open source under the MIT license. The source code and the setup guide are on GitHub.',
  },
  {
    q: 'Is it affiliated with teenage engineering?',
    a: 'No. It is an independent, unofficial project. “EP-2350” and “FX-MIC” are used only to say which hardware it works with.',
  },
];
