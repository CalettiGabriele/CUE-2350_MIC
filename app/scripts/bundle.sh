#!/bin/zsh
# Builds "CUE-2350 MIC.app" in app/dist with Command Line Tools only (no Xcode).
# Signing: macOS ties the Microphone/Accessibility grants to the code signature.
# With a stable identity (default name "CUE-2350 MIC Dev", or $SIGN_IDENTITY) the grant
# survives rebuilds. Without one the app is ad-hoc signed, its requirement is the binary
# hash, and Accessibility must be re-granted after every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/FXMicBridge"

APP="dist/CUE-2350 MIC.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FXMicBridge"

# App icon (drawn by the script) and the bundled fonts (Barlow, IBM Plex Mono: SIL OFL).
swift scripts/make_icons.swift "$APP/Contents/Resources"
ICON_PLIST="<key>CFBundleIconFile</key><string>AppIcon</string>"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<PLIST
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
  $ICON_PLIST
  <key>NSMicrophoneUsageDescription</key>
  <string>CUE-2350 MIC registra la voce mentre tieni premuta la maniglia, per trascriverla in locale.</string>
</dict>
</plist>
PLIST

IDENTITY=${SIGN_IDENTITY:-"CUE-2350 MIC Dev"}
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --sign "$IDENTITY" --identifier com.fxmicbridge.app "$APP"
  echo "Signed with stable identity: $IDENTITY"
else
  codesign --force --deep --sign - --identifier com.fxmicbridge.app "$APP"
  echo "Ad-hoc signed (no \"$IDENTITY\" identity): re-grant Accessibility after each rebuild"
fi
echo "Built: $PWD/$APP"
