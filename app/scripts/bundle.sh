#!/bin/zsh
# Builds "FXMic Bridge.app" in app/dist with Command Line Tools only (no Xcode).
# Signing: macOS ties the Microphone/Accessibility grants to the code signature.
# With a stable identity (default name "FXMic Bridge Dev", or $SIGN_IDENTITY) the grant
# survives rebuilds. Without one the app is ad-hoc signed, its requirement is the binary
# hash, and Accessibility must be re-granted after every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/FXMicBridge"

APP="dist/FXMic Bridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FXMicBridge"

# Optional logo (not committed: trademark of its owner, for personal use only).
LOGO="Resources/logo.svg"
ICON_PLIST=""
if [[ -f "$LOGO" ]]; then
  swift scripts/make_icons.swift "$LOGO" "$APP/Contents/Resources"
  cp "$LOGO" "$APP/Contents/Resources/MenuIcon.svg"
  ICON_PLIST="<key>CFBundleIconFile</key><string>AppIcon</string>"
  echo "Icons from $LOGO"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.fxmicbridge.app</string>
  <key>CFBundleName</key><string>FXMic Bridge</string>
  <key>CFBundleDisplayName</key><string>FXMic Bridge</string>
  <key>CFBundleExecutable</key><string>FXMicBridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  $ICON_PLIST
  <key>NSMicrophoneUsageDescription</key>
  <string>FXMic Bridge registra la voce mentre tieni premuta la maniglia, per trascriverla in locale.</string>
</dict>
</plist>
PLIST

IDENTITY=${SIGN_IDENTITY:-"FXMic Bridge Dev"}
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --sign "$IDENTITY" --identifier com.fxmicbridge.app "$APP"
  echo "Signed with stable identity: $IDENTITY"
else
  codesign --force --deep --sign - --identifier com.fxmicbridge.app "$APP"
  echo "Ad-hoc signed (no \"$IDENTITY\" identity): re-grant Accessibility after each rebuild"
fi
echo "Built: $PWD/$APP"
