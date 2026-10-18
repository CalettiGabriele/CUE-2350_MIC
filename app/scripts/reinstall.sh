#!/bin/zsh
# Run by the user after each rebuild while the app is ad-hoc signed:
# quits the app (restoring the mic), resets its Accessibility grant (bound to the binary hash)
# and relaunches it so macOS asks for the permission again.
# Not needed anymore once the "CUE-2350 MIC Dev" signing identity exists (see bundle.sh).
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)/dist/CUE-2350 MIC.app"

# By bundle id, so it also quits builds made under the old name (FXMic Bridge).
osascript -e 'quit app id "com.fxmicbridge.app"' 2>/dev/null || true
sleep 2
tccutil reset Accessibility com.fxmicbridge.app
open "$APP"
echo "Riavviata: concedi il permesso Accessibilità quando macOS lo chiede."
