#!/bin/zsh
# Use the selected Xcode or Command Line Tools toolchain. CLT's Swift Testing
# needs explicit search paths and has an incomplete Foundation overlay.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVELOPER_ROOT=${DEVELOPER_DIR:-$(xcode-select -p)}
if [[ "$DEVELOPER_ROOT" == *.app ]]; then
  DEVELOPER_ROOT="$DEVELOPER_ROOT/Contents/Developer"
fi
DEVELOPER_ROOT=${DEVELOPER_ROOT:A}

if [[ -d "$DEVELOPER_ROOT/SDKs" && ! -d "$DEVELOPER_ROOT/Platforms/MacOSX.platform" ]]; then
  F="$DEVELOPER_ROOT/Library/Developer/Frameworks"
  L="$DEVELOPER_ROOT/Library/Developer/usr/lib"
  xcrun swift test \
    -Xswiftc -F -Xswiftc "$F" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" \
    "$@"
else
  xcrun swift test "$@"
fi
