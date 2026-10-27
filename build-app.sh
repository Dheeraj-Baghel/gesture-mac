#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build a proper app bundle so macOS associates camera / Accessibility access
# with Gesture Mac, not the terminal or the IDE. Local ad-hoc signing is not
# Developer ID signing / notarization; this bundle is for this Mac only.
CONFIGURATION="${CONFIGURATION:-release}"
swift build --disable-sandbox -c "$CONFIGURATION" --product GestureMac
BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
APP="$PWD/artifacts/macos/Gesture Mac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GestureMac" "$APP/Contents/MacOS/GestureMac"
cp Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.gesturemac.app "$APP"
codesign --verify --deep --strict "$APP"
printf '\nBuilt: %s\n' "$APP"
if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
