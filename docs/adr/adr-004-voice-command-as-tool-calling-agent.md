# ADR-004: The voice command becomes a tool-calling agent on the OpenAI-compatible API

**Date:** 2026-10-24
**Status:** Accepted (2026-10-24)
**References:** [TDD v1 — voice command agent](../design-docs/tdd-v1-voice-command-agent.md), [One-Pager 004 §6–§7](../design-docs/onepager-004-channels-and-commands.md)

## Context
Today the voice command (grey pressed while the handle is held) is **one call to the model**. The
model gets a long prompt with the context (app, channels, skills, intents, selection) and answers
with a JSON of actions, `{"actions":[…]}`. That format is our own, explained in the prompt.
`CommandParser` validates it and the app runs it. The model never sees what happened afterwards.

This is enough for levels 1–3 of One-Pager 004 (text, keys, selection, channels, skills, intents).
It cannot do what the user wants next:
- formatting part of a text ("make *urgent* bold") means **finding** the word first;
- clicking a button, closing a window or choosing a menu item means **reading** what is on screen;
- tasks with several steps need the result of each step before the next one;
- a wrong action cannot be noticed and corrected.

A router in front (one fast call deciding "simple" or "complex") was considered and **rejected by
the user**. When the router is wrong the whole answer is wrong, and it cannot recover. The user
prefers a slower answer that checks itself.

Constraints:
- local by default (Ollama, `qwen3.5:4b`);
- external providers must work too (OpenAI, Anthropic, others) through the **OpenAI standard**;
- users add their own tools from Settings, and later connect MCP servers;
- the app is Swift only, with no extra runtime.

## Decision
We decided to turn the voice command into an **agent loop built in Swift** on the standard
OpenAI `/chat/completions` API with `tools`:

1. **Every** voice command goes to the agent, with no router. The model calls tools and the app
   runs them. Each tool result goes back to the model, until it calls `finish` or the budget runs
   out (8 steps / 30 s by default). The model may call an action and `finish` in the same answer,
   so a simple command still takes one call.
2. Actions are **tools in a registry**. Each tool has a name, a description, a JSON Schema for its
   input and a risk level. The shape is the same as an MCP tool (`name`, `description`,
   `inputSchema`), so MCP servers can be added later as one more tool source without changing the
   loop.
3. Provider access goes through a `ChatProvider` protocol. The only implementation is an
   OpenAI-compatible client with an optional API key, stored in the Keychain. Ollama, LM Studio,
   OpenAI, Anthropic (`https://api.anthropic.com/v1/`) and OpenRouter are presets of the same
   client. Differences between providers, such as `temperature` or `reasoning_effort`, are flags
   on the preset, not code paths.
4. **One model** is chosen for everything (the agent and the LLM skills).
5. We use **no third-party agent framework or SDK**. The loop is small. What matters is the tools
   and the safety rules, and we want to own both.

## Consequences

**Positive**
- New capabilities are added as **tools**, not by rewriting a prompt. Users add their own:
  macros of keys and text, and Shortcuts.app shortcuts.
- The agent can see and correct its own mistakes: after acting it can read the field again and
  undo or retry.
- The same code works with local and remote models. Changing provider is a Settings choice.
- MCP is ready by design: same tool shape, same risk and confirmation rules.
- Native tool calling replaces the hand-made JSON and the code that dug it out of free text.

**Negative**
- **Latency** grows when the model chooses to check its work. A step costs about 0.6–0.8 s with
  the local 4B model, so a command with checking takes about 1.5–2 s instead of about 0.7 s.
- A 4B model is less reliable at choosing among many tools and over many steps. Tool groups that
  can be switched off, an evaluation set and the option of a larger or remote model make up for
  it.
- **More data leaves the Mac** with a remote provider: the agent sends what it reads on screen
  (field text, UI elements), not just the sentence. Settings and the pill must say so.
- Text read on screen goes into the model's context, so a page can try to steer the agent
  (prompt injection). Confirmation for risky tools and the blocked-key list are the mitigation.
- Anthropic's OpenAI-compatible layer is meant for testing, not for production. It ignores
  `strict` and has no prompt caching. A native Messages API adapter behind `ChatProvider` stays
  possible.
- We maintain the agent loop ourselves: budget, cancellation, confirmation and the trace.
