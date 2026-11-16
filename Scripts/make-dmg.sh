#!/bin/bash
# Builds a Release DroidDesk.app and packs it into dist/DroidDesk-<version>.dmg.
#
# The app is ad-hoc signed and not notarized, so macOS asks for a confirmation on the first launch.
# Usage: Scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED=".derivedData"
APP="$DERIVED/Build/Products/Release/DroidDesk.app"
NAME="DroidDesk"

echo "==> Building the Release app"
xcodebuild -project DroidDesk.xcodeproj -scheme DroidDesk -configuration Release \
  -derivedDataPath "$DERIVED" clean build | tail -n 3

[ -d "$APP" ] || { echo "error: $APP was not built" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/$NAME-$VERSION.dmg"
mkdir -p dist
rm -f "$DMG" "$DMG.sha256"

echo "==> Checking the app signature"
codesign --verify --deep --strict "$APP"

echo "==> Packing $DMG"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

echo "==> Verifying the disk image"
hdiutil verify "$DMG" >/dev/null
MOUNT=$(mktemp -d)
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGING" "$MOUNT"' EXIT
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -quiet
[ -d "$MOUNT/$NAME.app" ] || { echo "error: $NAME.app is missing from the disk image" >&2; exit 1; }
[ -L "$MOUNT/Applications" ] || { echo "error: the Applications shortcut is missing" >&2; exit 1; }
codesign --verify --deep --strict "$MOUNT/$NAME.app"

(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
cat "$DMG.sha256"
