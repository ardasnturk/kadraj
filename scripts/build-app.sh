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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Kadraj" "$APP/Contents/MacOS/Kadraj"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
sign() { codesign --force --options runtime "$TIMESTAMP" --sign "${IDENTITY:--}" "$@"; }

# Sparkle's helpers are signed inside out, as its documentation describes; the downloader keeps
# its entitlements.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
