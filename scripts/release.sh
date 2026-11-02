#!/usr/bin/env bash
# Builds a Developer ID signed, notarized Kadraj DMG and a Sparkle appcast for it, then publishes
# both as a GitHub release. The app's SUFeedURL points at the latest release's appcast.xml.
#   NOTARY_PROFILE="..." notarytool keychain profile (default: kadraj-notary)
#   SPARKLE_ACCOUNT="..." Keychain account of the Sparkle EdDSA key (default: kadraj)
#   SIGN_IDENTITY="..."  codesigning identity (default: first "Developer ID Application" identity)
#   SKIP_PUBLISH=1       build and notarize the DMG without tagging or releasing
# Needs dmgbuild (pipx install dmgbuild) to lay out the DMG window.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-kadraj-notary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-kadraj}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
if ! command -v dmgbuild >/dev/null; then
  echo "dmgbuild not found; install it with: pipx install dmgbuild" >&2
  exit 1
fi
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application identity found." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
TAG="v$VERSION"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

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
rm -f "$DMG"
swift scripts/make-dmg-background.swift build/dmg-background.tiff
dmgbuild -s scripts/dmg-settings.py -D app=build/Kadraj.app -D background=build/dmg-background.tiff Kadraj "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# Sparkle appcast with a single item: the release being made. Its notes list the commits since
# the previous release.
SIGNATURE="$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account "$SPARKLE_ACCOUNT" "$DMG")"
PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
NOTES="$(git log --format=%s ${PREVIOUS_TAG:+"$PREVIOUS_TAG..HEAD"} |
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s|.*|<li>&</li>|')"
APPCAST="build/appcast.xml"
cat >"$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Kadraj</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Kadraj $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<ul>$NOTES</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/Kadraj-$VERSION.dmg"
                 type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$APPCAST"

echo "Built $DMG and $APPCAST"
[ -n "${SKIP_PUBLISH:-}" ] && exit 0

git tag -a "$TAG" -m "Kadraj $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$APPCAST" --title "Kadraj $VERSION" --generate-notes
