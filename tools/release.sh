#!/bin/zsh
# Builds the mac4DSTEM download in one run: the Developer ID archive, the notarized and stapled app, then the signed,
# notarized and stapled DMG. Paul runs it on the Mac with the certificate; it pushes nothing and uploads nothing.
#
#   tools/release.sh                    the Developer ID DMG (the GitHub download)
#   tools/release.sh --store            the App Store package from the same tag (tools/release/build-app-store.sh)
#   tools/release.sh --store --upload   the same, then validate and upload it to App Store Connect
#
# The store flavour needs Xcode signed in to the team's Apple ID, and for validate/upload an App Store Connect API key:
# ASC_KEY_ID and ASC_ISSUER_ID set, the .p8 in ~/.appstoreconnect/private_keys/. Without the key it builds and checks
# the package and stops. Output: build/release/<stamp>/store/mac4DSTEM.pkg.
#
# Needs the "Developer ID Application" certificate in the login keychain, a notarytool keychain profile (default
# macem-notary; override with NOTARY_PROFILE) and dmgbuild in build/dmg-venv (make-dmg.sh says how to create it).
# Output: build/release/<stamp>/mac4DSTEM-<version>.dmg and a copy named mac4DSTEM.dmg for the
# releases/latest/download/mac4DSTEM.dmg link. The steps are tools/release/{build-developer-id,notarize,make-dmg}.sh.
set -euo pipefail

STORE=0 UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --store) STORE=1 ;;
    --upload) UPLOAD=1 ;;
    *) echo "usage: tools/release.sh [--store [--upload]]" >&2; exit 2 ;;
  esac
done
(( UPLOAD == 0 || STORE == 1 )) || { echo "--upload goes with --store" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Paul Lobpreis (3B8SMSSAX4)}"
export NOTARY_PROFILE="${NOTARY_PROFILE:-macem-notary}"
OUT="$ROOT/build/release/$(date +%Y%m%d-%H%M%S)"   # a new folder per run, so a rerun never deletes an earlier archive

[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "The working tree is not clean; commit first so the build has a commit." >&2; exit 1; }
if (( STORE == 0 )); then
  security find-identity -v -p codesigning | grep -q "$DEVELOPER_ID_APPLICATION" || { echo "No certificate \"$DEVELOPER_ID_APPLICATION\" in the keychain." >&2; exit 1; }
  [[ -x "$ROOT/build/dmg-venv/bin/dmgbuild" ]] || { echo "No dmgbuild; run: python3 -m venv build/dmg-venv && build/dmg-venv/bin/pip install dmgbuild==1.6.1" >&2; exit 1; }
fi
# A download is built from a release tag, and the app must carry that tag's version (Config/Version.xcconfig, which
# release-please bumps): checked here before the archive and again on the built app.
TAG="$(git -C "$ROOT" describe --exact-match --tags HEAD 2>/dev/null)" || { echo "HEAD is not a release tag; check out the tag to build (git worktree add … vX.Y.Z)." >&2; exit 1; }
EXPECTED="${TAG#v}"
SET="$(sed -n 's/^MARKETING_VERSION = \([0-9.]*\).*/\1/p' "$ROOT/Config/Version.xcconfig")"
[[ "$SET" == "$EXPECTED" ]] || { echo "Config/Version.xcconfig says $SET but the tag is $TAG." >&2; exit 1; }
mkdir -p "$OUT"

if (( STORE == 1 )); then
  echo "== App Store archive and export ($(git -C "$ROOT" rev-parse --short HEAD))"
  "$ROOT/tools/release/build-app-store.sh" "$OUT" > "$OUT/store.log" 2>&1 || { tail -30 "$OUT/store.log"; exit 1; }
  PKG="$(tail -1 "$OUT/store.log")"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OUT/mac4DSTEM-store.xcarchive/Products/Applications/mac4DSTEM.app/Contents/Info.plist")"
  [[ "$VERSION" == "$EXPECTED" ]] || { echo "The built app says $VERSION but the tag is $TAG." >&2; exit 1; }
  echo "mac4DSTEM $VERSION: $PKG"
  if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
    echo "No App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID): built and checked, not validated or uploaded."
    exit 0
  fi
  echo "== Validate with App Store Connect"
  xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  if (( UPLOAD == 1 )); then
    echo "== Upload to App Store Connect"
    xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "Uploaded. The build shows in App Store Connect > TestFlight after processing (minutes to an hour)."
  fi
  exit 0
fi

echo "== Archive ($(git -C "$ROOT" rev-parse --short HEAD))"
"$ROOT/tools/release/build-developer-id.sh" "$OUT" > "$OUT/archive.log" 2>&1 || { tail -30 "$OUT/archive.log"; exit 1; }
APP="$OUT/mac4DSTEM.xcarchive/Products/Applications/mac4DSTEM.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" == "$EXPECTED" ]] || { echo "The built app says $VERSION but the tag is $TAG." >&2; exit 1; }
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
