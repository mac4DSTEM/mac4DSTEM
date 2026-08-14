#!/bin/zsh
# Clean Release packaging audit: embedded HDF5 closure, signatures,
# sandbox/bookmark entitlements, and a bundle-only HDF5 read smoke test.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

xcodebuild \
  -project "$REPO/mac4DSTEM.xcodeproj" \
  -scheme mac4DSTEM \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$WORK/DerivedData" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build -quiet

APP="$WORK/DerivedData/Build/Products/Release/mac4DSTEM.app"
FRAMEWORKS="$APP/Contents/Frameworks"
EXECUTABLE="$APP/Contents/MacOS/mac4DSTEM"
INFO="$APP/Contents/Info.plist"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" = \
  "com.mac4dstem.mac4DSTEM"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" = "1.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")" = "1"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")" = "14.0"
test -f "$APP/Contents/Resources/AppIcon.icns"

for library in libhdf5.dylib libsz.2.dylib libaec.0.dylib; do
  test -f "$FRAMEWORKS/$library"
  codesign --verify --strict "$FRAMEWORKS/$library"
  if otool -L "$FRAMEWORKS/$library" | grep -Eq '/opt/homebrew|/usr/local'; then
    echo "FAIL: $library retains a machine-local dependency" >&2
    exit 1
  fi
done
otool -L "$FRAMEWORKS/libhdf5.dylib" | grep -q '@loader_path/libsz.2.dylib'
otool -L "$FRAMEWORKS/libhdf5.dylib" | grep -q '@loader_path/libaec.0.dylib'
if otool -L "$EXECUTABLE" | grep -Eq '/opt/homebrew|/usr/local'; then
  echo "FAIL: app executable retains a machine-local dependency" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" > "$WORK/entitlements.plist" 2>/dev/null
for entitlement in \
  com.apple.security.app-sandbox \
  com.apple.security.files.user-selected.read-write \
  com.apple.security.files.bookmarks.app-scope; do
  test "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$WORK/entitlements.plist")" = true
done
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' \
    "$WORK/entitlements.plist" >/dev/null 2>&1; then
  echo "FAIL: Release app contains get-task-allow" >&2
  exit 1
fi

cc -Wall -Wextra -Werror hdf5_smoke.c -o "$WORK/hdf5_smoke"
env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
  "$WORK/hdf5_smoke" \
  "$FRAMEWORKS/libhdf5.dylib" \
  "$REPO/tools/calibration-test/real_py4dstem.h5"

echo "PASS: hardened sandbox entitlements and nested signatures"
echo "PASS: v1 identity, version, macOS 14 floor, and app icon"
echo "PASS: no Homebrew/local dylib dependency in the Release product"
echo "package-test: all passed"
