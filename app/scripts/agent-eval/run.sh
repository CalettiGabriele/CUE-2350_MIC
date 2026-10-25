#!/bin/zsh
# Runs the voice-command evaluation set against the model in config.json (TDD voice command
# agent §3.7) and saves the report in logs/agent-eval/. Extra arguments go to the CLI, e.g.
#   scripts/agent-eval/run.sh --repeat 3
#   scripts/agent-eval/run.sh --filter selection --model qwen3.5:9b
set -euo pipefail
cd "$(dirname "$0")/../.."
ENGINE=legacy
for ((i = 1; i < $#; i++)); do [[ ${@[i]} == --engine ]] && ENGINE=${@[i+1]}; done
OUT="../logs/agent-eval/$(date +%Y-%m-%d-%H%M)-$ENGINE.json"
swift run -c release AgentEval --corpus scripts/agent-eval/corpus.json --out "$OUT" "$@"
