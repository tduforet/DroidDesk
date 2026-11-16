#!/bin/bash
# Builds a Release DroidDesk.app and packs it into dist/DroidDesk-<version>.dmg.
#
# By default the app is ad-hoc signed and not notarized, so macOS asks for a confirmation on the first launch.
#
# To sign with a Developer ID certificate and notarize, set these in the environment or in a
# .release.env file at the root of the repository (Git ignores it, see .release.env.example):
#   SIGN_IDENTITY   the certificate's SHA-1 fingerprint, or its full name
#   TEAM_ID         your Apple Developer team ID
#   NOTARY_PROFILE  the keychain profile made with `xcrun notarytool store-credentials`
#
# Usage: Scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .release.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.release.env
  set +a
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "error: NOTARY_PROFILE needs SIGN_IDENTITY, since only a Developer ID signature can be notarized" >&2
  exit 1
fi

DERIVED=".derivedData"
APP="$DERIVED/Build/Products/Release/DroidDesk.app"
NAME="DroidDesk"

# Submits a file to Apple's notary service and waits for the verdict. Stops the script unless it is accepted.
notarize() {
  local file="$1" json status id
  echo "    submitting $(basename "$file"), this takes a few minutes"
  json=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --output-format json --wait) || true
  status=$(printf '%s' "$json" | plutil -extract status raw -o - - 2>/dev/null || echo "unknown")
  if [ "$status" != "Accepted" ]; then
    id=$(printf '%s' "$json" | plutil -extract id raw -o - - 2>/dev/null || true)
    echo "error: Apple did not accept $(basename "$file") (status: $status)" >&2
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  fi
  echo "    accepted"
}

BUILD_ARGS=()
if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing with the Developer ID identity from the environment"
  BUILD_ARGS+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual
               ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp"
               CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)  # without this Xcode adds get-task-allow, which Apple refuses
  if [ -n "$TEAM_ID" ]; then BUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID"); fi
else
  echo "==> No SIGN_IDENTITY: the app will be ad-hoc signed and not notarized"
fi

echo "==> Building the Release app"
xcodebuild -project DroidDesk.xcodeproj -scheme DroidDesk -configuration Release \
  -derivedDataPath "$DERIVED" clean build ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} | tail -n 3

[ -d "$APP" ] || { echo "error: $APP was not built" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/$NAME-$VERSION.dmg"
mkdir -p dist
rm -f "$DMG" "$DMG.sha256"

echo "==> Checking the app signature"
codesign --verify --deep --strict "$APP"
if [ -n "$SIGN_IDENTITY" ]; then
  DETAILS=$(codesign -dvv "$APP" 2>&1)
  printf '%s' "$DETAILS" | grep -q "Authority=Developer ID Application" \
    || { echo "error: the app is not signed with a Developer ID Application certificate" >&2; exit 1; }
  printf '%s' "$DETAILS" | grep -q "flags=.*runtime" \
    || { echo "error: the hardened runtime is off, Apple would refuse the app" >&2; exit 1; }
fi

WORK=$(mktemp -d)
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$APP" "$WORK/$NAME.zip"
  notarize "$WORK/$NAME.zip"
  xcrun stapler staple "$APP" >/dev/null
  xcrun stapler validate "$APP" >/dev/null
fi

echo "==> Packing $DMG"
mkdir "$WORK/staging"
ditto "$APP" "$WORK/staging/$NAME.app"
ln -s /Applications "$WORK/staging/Applications"
hdiutil create -volname "$NAME" -srcfolder "$WORK/staging" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG" >/dev/null
  xcrun stapler validate "$DMG" >/dev/null
fi

echo "==> Verifying the disk image"
hdiutil verify "$DMG" >/dev/null
MOUNT=$(mktemp -d)
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -quiet
[ -d "$MOUNT/$NAME.app" ] || { echo "error: $NAME.app is missing from the disk image" >&2; exit 1; }
[ -L "$MOUNT/Applications" ] || { echo "error: the Applications shortcut is missing" >&2; exit 1; }
codesign --verify --deep --strict "$MOUNT/$NAME.app"
if [ -n "$NOTARY_PROFILE" ]; then
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo
if [ -n "$NOTARY_PROFILE" ]; then echo "Built and notarized $DMG ($(du -h "$DMG" | cut -f1))"
else echo "Built $DMG ($(du -h "$DMG" | cut -f1))"; fi
cat "$DMG.sha256"
