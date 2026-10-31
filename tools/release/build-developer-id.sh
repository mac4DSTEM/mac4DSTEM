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

xcodebuild archive \
  -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Release -destination "$MAC4DSTEM_RELEASE_DESTINATION" \
  -archivePath "$ARCHIVE" \
  "$MAC4DSTEM_ARCH_PIN" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
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
check_signed() {
  local details
  details="$(codesign -dvv "$1" 2>&1)"
  [[ "$details" == *"Authority=$DEVELOPER_ID_APPLICATION"* ]] || { echo "FAIL: $1 is not signed by $DEVELOPER_ID_APPLICATION" >&2; exit 1; }
  [[ "$details" == *"(runtime)"* ]] || { echo "FAIL: $1 is not signed with the hardened runtime" >&2; exit 1; }
  [[ "$details" == *"Timestamp="* ]] || { echo "FAIL: $1 has no secure timestamp" >&2; exit 1; }
}
check_signed "$APP"
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
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ditto -c -k --keepParent "$APP" "$OUT/mac4DSTEM-$VERSION-pre-notarization.zip"
echo "$APP"
