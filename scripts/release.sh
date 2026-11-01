#!/usr/bin/env bash
# Builds a Developer ID signed, notarized Kadraj DMG and publishes it as a GitHub release.
#   NOTARY_PROFILE="..." notarytool keychain profile (default: kadraj-notary)
#   SIGN_IDENTITY="..."  codesigning identity (default: first "Developer ID Application" identity)
#   SKIP_PUBLISH=1       build and notarize the DMG without tagging or releasing
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-kadraj-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application identity found." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"

if [ -z "${SKIP_PUBLISH:-}" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is not clean; commit your changes first." >&2
    exit 1
  fi
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag $TAG already exists; bump CFBundleShortVersionString first." >&2
    exit 1
  fi
fi

SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh

DMG="build/Kadraj-$VERSION.dmg"
STAGING="build/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Kadraj.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Kadraj" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "Built $DMG"
[ -n "${SKIP_PUBLISH:-}" ] && exit 0

git tag -a "$TAG" -m "Kadraj $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --title "Kadraj $VERSION" --generate-notes
