#!/bin/zsh
# Run by the user after each rebuild while the app is ad-hoc signed:
# quits the app (restoring the mic), resets its Accessibility grant (bound to the binary hash)
# and relaunches it so macOS asks for the permission again.
# Not needed anymore once the "FXMic Bridge Dev" signing identity exists (see bundle.sh).
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)/dist/FXMic Bridge.app"

osascript -e 'quit app "FXMic Bridge"' 2>/dev/null || true
sleep 2
tccutil reset Accessibility com.fxmicbridge.app
open "$APP"
echo "Riavviata: concedi il permesso Accessibilità quando macOS lo chiede."
