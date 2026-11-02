#!/usr/bin/env bash
# Builds Kadraj.app into ./build.
#   CONFIG=debug|release (default: release)
#   SIGN_IDENTITY="..." codesigning identity (default: first "Developer ID Application", then "Apple Development"
#                       identity, else ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Kadraj.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Kadraj" "$APP/Contents/MacOS/Kadraj"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity keeps the Screen Recording permission across rebuilds. Preferring the
# release identity lets local builds and published releases share the same permission.
IDENTITIES="$(security find-identity -v -p codesigning)"
IDENTITY="${SIGN_IDENTITY:-$(awk -F'"' '/Developer ID Application/ { print $2; exit }' <<<"$IDENTITIES")}"
IDENTITY="${IDENTITY:-$(awk -F'"' '/Apple Development/ { print $2; exit }' <<<"$IDENTITIES")}"
# Notarization requires a secure timestamp on Developer ID signatures.
TIMESTAMP="--timestamp=none"
[[ "$IDENTITY" == "Developer ID Application"* ]] && TIMESTAMP="--timestamp"
codesign --force --options runtime "$TIMESTAMP" --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
