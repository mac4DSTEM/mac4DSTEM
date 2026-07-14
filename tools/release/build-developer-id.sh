#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application certificate name}"
export DEVELOPER_DIR

OUT="${1:-$ROOT/build/release}"
ARCHIVE="$OUT/mac4DSTEM.xcarchive"
APP="$ARCHIVE/Products/Applications/mac4DSTEM.app"
rm -rf "$ARCHIVE"
mkdir -p "$OUT"

xcodebuild archive \
  -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
    "$OUT/entitlements.plist" >/dev/null 2>&1; then
  echo "FAIL: distribution app contains get-task-allow" >&2; exit 1
fi
ditto -c -k --keepParent "$APP" "$OUT/mac4DSTEM-1.0-pre-notarization.zip"
echo "$APP"
