#!/bin/zsh
# Runs the unit tests with Command Line Tools only (no Xcode).
# The CLT ship Swift Testing outside the default search path, and its
# _Testing_Foundation cross-import overlay is incomplete, so it is disabled.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test \
  -Xswiftc -F -Xswiftc $F \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L \
  "$@"
