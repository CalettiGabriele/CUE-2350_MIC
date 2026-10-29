#!/bin/zsh
# Build, sign and atomically publish CUE-2350 MIC.app, or separate preparation
# from signing when keychain access must happen in an interactive session.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "Usage: $0 [debug|release] | --prepare [debug|release] | --finalize <prepared-app>" >&2
  echo "Set BUNDLE_OUTPUT_DIR to change app/dist; set SIGN_IDENTITY=- for ad-hoc signing." >&2
}

MODE=build
CONFIG=release
PREPARED=""
case ${1:-} in
  --prepare)
    MODE=prepare
    shift
    if (( $# )); then CONFIG=$1; shift; fi
    ;;
  --finalize)
    MODE=finalize
    shift
    if (( $# != 1 )); then usage; exit 2; fi
    PREPARED=$1
    shift
    ;;
  -*) usage; exit 2 ;;
  '') ;;
  *) CONFIG=$1; shift ;;
esac
if (( $# )) || { [[ "$MODE" != finalize ]] && [[ "$CONFIG" != debug && "$CONFIG" != release ]]; }; then
  usage
  exit 2
fi

OUTPUT_DIR=${BUNDLE_OUTPUT_DIR:-"$PWD/dist"}
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=${OUTPUT_DIR:A}
DEST="$OUTPUT_DIR/CUE-2350 MIC.app"
STAGE_DIR=""
cleanup() {
  if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
    rm -rf -- "$STAGE_DIR"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ "$MODE" == finalize ]]; then
  APP=${PREPARED:A}
  CANDIDATE=${APP:h}
  if [[ ${APP:t} != 'CUE-2350 MIC.app' || ${CANDIDATE:h} != "$OUTPUT_DIR" || ${CANDIDATE:t} != .cue-bundle.* || ! -d "$APP" || -L "$PREPARED" ]]; then
    echo "Prepared app must be a bundle created by --prepare inside $OUTPUT_DIR." >&2
    exit 2
  fi
  STAGE_DIR=$CANDIDATE
else
  STAGE_DIR=$(mktemp -d "$OUTPUT_DIR/.cue-bundle.XXXXXXXX")
  APP="$STAGE_DIR/CUE-2350 MIC.app"
  echo "Building $CONFIG bundle (no signing yet)..."
  xcrun swift build -c "$CONFIG"
  BIN="$(xcrun swift build -c "$CONFIG" --show-bin-path)/FXMicBridge"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN" "$APP/Contents/MacOS/FXMicBridge"
  xcrun swift scripts/make_icons.swift "$APP/Contents/Resources"
  cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.fxmicbridge.app</string>
  <key>CFBundleName</key><string>CUE-2350 MIC</string>
  <key>CFBundleDisplayName</key><string>CUE-2350 MIC</string>
  <key>CFBundleExecutable</key><string>FXMicBridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>CUE-2350 MIC mette in pausa Spotify o Musica mentre tieni premuta la maniglia e la riprende dopo.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>CUE-2350 MIC registra la voce mentre tieni premuta la maniglia, per trascriverla in locale.</string>
</dict>
</plist>
PLIST
  if [[ "$MODE" == prepare ]]; then
    echo "Prepared unsigned app: $APP"
    echo "To sign and publish in an interactive session, run:"
    printf '  BUNDLE_OUTPUT_DIR=%q %q --finalize %q\n' "$OUTPUT_DIR" "$PWD/scripts/bundle.sh" "$APP"
    STAGE_DIR="" # Keep the prepared bundle for the separate finalize command.
    exit 0
  fi
fi

if (( ${+SIGN_IDENTITY} )); then
  IDENTITY=$SIGN_IDENTITY
  if [[ -z "$IDENTITY" ]]; then
    echo "SIGN_IDENTITY is empty; specify a signing identity or '-' for ad-hoc signing." >&2
    exit 2
  fi
else
  IDENTITY='CUE-2350 MIC Dev'
  # Local self-signed identities can be usable even when system trust marks them untrusted.
  if IDENTITIES=$(security find-identity -p codesigning 2>/dev/null) && [[ "$IDENTITIES" == *'"CUE-2350 MIC Dev"'* ]]; then
    :
  else
    IDENTITY=-
    echo 'Default signing identity unavailable; using ad-hoc signing.'
  fi
fi

echo "Signing staged app with identity: $IDENTITY"
echo 'Keychain access may require approval in this interactive session.'
codesign --force --deep --sign "$IDENTITY" --identifier com.fxmicbridge.app "$APP"
echo 'Verifying staged signature...'
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -n "$(find "$APP" -name '*.cstemp' -print -quit)" ]]; then
  echo 'Signing left a .cstemp artifact; refusing to publish the staged app.' >&2
  exit 1
fi
echo 'Publishing verified bundle atomically...'
xcrun swift scripts/publish_bundle.swift "$APP" "$DEST"
if [[ "$IDENTITY" == '-' ]]; then
  echo 'Ad-hoc signed: re-grant Accessibility after each rebuild.'
fi
echo "Built: $DEST"
