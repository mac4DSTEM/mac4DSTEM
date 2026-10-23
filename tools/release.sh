#!/bin/zsh
# Builds the mac4DSTEM download in one run: the Developer ID archive, the notarized and stapled app, then the signed,
# notarized and stapled DMG. Paul runs it on the Mac with the certificate; it pushes nothing and uploads nothing.
#
#   tools/release.sh
#
# Needs the "Developer ID Application" certificate in the login keychain, a notarytool keychain profile (default
# macem-notary; override with NOTARY_PROFILE) and dmgbuild in build/dmg-venv (make-dmg.sh says how to create it).
# Output: build/release/<stamp>/mac4DSTEM-<version>.dmg and a copy named mac4DSTEM.dmg for the
# releases/latest/download/mac4DSTEM.dmg link. The steps are tools/release/{build-developer-id,notarize,make-dmg}.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Paul Lobpreis (3B8SMSSAX4)}"
export NOTARY_PROFILE="${NOTARY_PROFILE:-macem-notary}"
OUT="$ROOT/build/release/$(date +%Y%m%d-%H%M%S)"   # a new folder per run, so a rerun never deletes an earlier archive

[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "The working tree is not clean; commit first so the build has a commit." >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "$DEVELOPER_ID_APPLICATION" || { echo "No certificate \"$DEVELOPER_ID_APPLICATION\" in the keychain." >&2; exit 1; }
[[ -x "$ROOT/build/dmg-venv/bin/dmgbuild" ]] || { echo "No dmgbuild; run: python3 -m venv build/dmg-venv && build/dmg-venv/bin/pip install dmgbuild==1.6.1" >&2; exit 1; }
mkdir -p "$OUT"

echo "== Archive ($(git -C "$ROOT" rev-parse --short HEAD))"
"$ROOT/tools/release/build-developer-id.sh" "$OUT" > "$OUT/archive.log" 2>&1 || { tail -30 "$OUT/archive.log"; exit 1; }
APP="$OUT/mac4DSTEM.xcarchive/Products/Applications/mac4DSTEM.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "mac4DSTEM $VERSION"

echo "== Notarize the app"
"$ROOT/tools/release/notarize.sh" "$APP" "$OUT/mac4DSTEM-$VERSION.zip"

echo "== DMG"
DMG="$OUT/mac4DSTEM-$VERSION.dmg"
"$ROOT/tools/release/make-dmg.sh" "$APP" "$DMG"

echo "== Notarize the DMG"
"$ROOT/tools/release/notarize.sh" "$DMG"
cp "$DMG" "$OUT/mac4DSTEM.dmg"

echo
echo "Done: $DMG"
echo "Also: $OUT/mac4DSTEM.dmg (for releases/latest/download/mac4DSTEM.dmg)"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Size: $(stat -f%z "$DMG") bytes"
