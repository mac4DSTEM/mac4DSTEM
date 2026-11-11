#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$(dirname "$0")/../lib/release-arch.sh"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application certificate name}"

OUT="${1:-$ROOT/build/release}"
ARCHIVE="$OUT/mac4DSTEM.xcarchive"
APP="$ARCHIVE/Products/Applications/mac4DSTEM.app"
rm -rf "$ARCHIVE"
mkdir -p "$OUT"
# The download's build number is its version (#122): Sparkle compares the feed's sparkle:version with CFBundleVersion, and
# the project's CURRENT_PROJECT_VERSION does not move between releases (it is the App Store build's). The packages are
# cloned to build/SourcePackages so tools/release/appcast.sh finds Sparkle's sign_update at one path.
VERSION_SET="$(sed -n 's/^MARKETING_VERSION = \([0-9.]*\).*/\1/p' "$ROOT/Config/Version.xcconfig")"

xcodebuild archive \
  -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Release -destination "$MAC4DSTEM_RELEASE_DESTINATION" \
  -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
  "$MAC4DSTEM_ARCH_PIN" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CURRENT_PROJECT_VERSION="$VERSION_SET" \
  archive

# Measured on the product, not inferred from the setting above: the pin could
# be dropped, and a future "fix" that made Float16 compile on x86_64 would
# restore the universal binary v2.5.1 shipped without failing anything else.
assert_mac4dstem_bundle_arm64_only "$APP"

# The HDF5 helper (Contents/XPCServices/HDF5Helper.xpc) is nested code with its own copies of FormatoKit's libhdf5
# frameworks. The archive above signs it, as every target: CODE_SIGN_IDENTITY and --timestamp reach each target and each
# framework embedded with Code Sign On Copy, and its Release configuration turns the hardened runtime on. It is not
# signed a second time here, so a nested piece the archive signed wrongly fails below instead of being papered over.
# Each signed piece is checked: Developer ID, hardened runtime, secure timestamp; the helper sandboxed, without
# get-task-allow, arm64 only.
# Sparkle (#122), the download's updater. The package ships its helpers (the installer and downloader services, Autoupdate,
# Updater.app) signed by the Sparkle project; the archive copies the framework without signing inside it. Each helper is
# signed here with the Developer ID, the hardened runtime and a timestamp, inside out, as Sparkle's documentation says for a
# build that is not exported by Xcode; the downloader keeps its own entitlements. Then the app again, keeping its
# entitlements, because its seal covers the framework. The feed key must be the real one: the placeholder would leave the
# updater off in every copy.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "FAIL: the download has no Sparkle.framework (the updater, #122)" >&2; exit 1; }
KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$KEY" && "$KEY" != SET-BEFORE-RELEASE ]] \
  || { echo "FAIL: Info-Direct.plist has no public EdDSA key (SUPublicEDKey); tools/release/README.md says how to make it" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$VERSION_SET" ]] \
  || { echo "FAIL: the download's build number is not its version" >&2; exit 1; }
sign_nested() { codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$@"; }
for helper in "$SPARKLE"/Versions/B/XPCServices/Installer.xpc "$SPARKLE"/Versions/B/Autoupdate "$SPARKLE"/Versions/B/Updater.app; do
  [[ -e "$helper" ]] || { echo "FAIL: Sparkle has no ${helper#$SPARKLE/}" >&2; exit 1; }
  sign_nested "$helper"
done
[[ ! -e "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" ]] \
  || sign_nested --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign_nested "$SPARKLE"
sign_nested --preserve-metadata=entitlements,requirements,flags "$APP"

check_signed() {
  local details
  details="$(codesign -dvv "$1" 2>&1)"
  [[ "$details" == *"Authority=$DEVELOPER_ID_APPLICATION"* ]] || { echo "FAIL: $1 is not signed by $DEVELOPER_ID_APPLICATION" >&2; exit 1; }
  [[ "$details" == *"(runtime)"* ]] || { echo "FAIL: $1 is not signed with the hardened runtime" >&2; exit 1; }
  [[ "$details" == *"Timestamp="* ]] || { echo "FAIL: $1 has no secure timestamp" >&2; exit 1; }
}
check_signed "$APP"
check_signed "$SPARKLE"
for helper in "$SPARKLE"/Versions/B/XPCServices/*.xpc(N) "$SPARKLE"/Versions/B/Autoupdate "$SPARKLE"/Versions/B/Updater.app; do
  check_signed "$helper"
done
for extension in "$APP"/Contents/PlugIns/*.appex(N); do check_signed "$extension"; done
HELPER="$APP/Contents/XPCServices/HDF5Helper.xpc"
if [[ -d "$HELPER" ]]; then
  for framework in "$HELPER"/Contents/Frameworks/*.framework(N); do
    check_signed "$framework"
    assert_mac4dstem_arm64_only "$framework/${${framework:t}%.framework}"
  done
  check_signed "$HELPER"
  assert_mac4dstem_arm64_only "$HELPER/Contents/MacOS/HDF5Helper"
  codesign -d --entitlements :- "$HELPER" > "$OUT/helper-entitlements.plist" 2>/dev/null
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$OUT/helper-entitlements.plist" >/dev/null 2>&1; then
    echo "FAIL: the HDF5 helper contains get-task-allow" >&2; exit 1
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$OUT/helper-entitlements.plist" 2>/dev/null)" == true ]] \
    || { echo "FAIL: the HDF5 helper is not sandboxed" >&2; exit 1; }
  codesign --verify --strict --verbose=2 "$HELPER"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
    "$OUT/entitlements.plist" >/dev/null 2>&1; then
  echo "FAIL: distribution app contains get-task-allow" >&2; exit 1
fi
# The sandboxed installer is reached through the download's one exception (mac4DSTEM-Direct.entitlements).
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name' "$OUT/entitlements.plist" \
  | grep -q -- '-spki' || { echo "FAIL: the download cannot reach Sparkle's installer (mach-lookup exception)" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ditto -c -k --keepParent "$APP" "$OUT/mac4DSTEM-$VERSION-pre-notarization.zip"
echo "$APP"
