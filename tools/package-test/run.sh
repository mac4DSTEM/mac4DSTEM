#!/bin/zsh
# Builds the packages with `swift build`; tools/lib/sources.manifest has nothing to supply.
# Clean Release packaging audit: embedded HDF5 closure, signatures,
# sandbox/bookmark entitlements, and a bundle-only HDF5 read smoke test.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-package-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Sourced via $REPO, not $(dirname "$0"): this script cd's to its own directory
# above, so a $0-relative path would resolve against the wrong directory.
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/release-arch.sh"

# The destination and the architecture pin come from release-arch.sh so that
# this audit builds the way build-developer-id.sh builds. It did NOT until
# 2026-09-11: it used 'platform=macOS', the concrete machine, which filters the
# architectures itself, while the archive uses a generic destination and does
# not. That difference is the whole reason `run-tests.sh all` was green on
# 2026-09-11 an hour before the release archive failed to compile at all, and
# the reason v2.5.1 shipped universal. A gate that does not build the way the
# release builds is not covering the release.
xcodebuild \
  -project "$REPO/mac4DSTEM.xcodeproj" \
  -scheme mac4DSTEM \
  -configuration Release \
  -destination "$MAC4DSTEM_RELEASE_DESTINATION" \
  -derivedDataPath "$WORK/DerivedData" \
  "$MAC4DSTEM_ARCH_PIN" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build -quiet

APP="$WORK/DerivedData/Build/Products/Release/mac4DSTEM.app"
FRAMEWORKS="$APP/Contents/Frameworks"
EXECUTABLE="$APP/Contents/MacOS/mac4DSTEM"
INFO="$APP/Contents/Info.plist"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" = \
  "com.mac4dstem.mac4DSTEM"
# The version and build come from the project, not a literal here: a literal
# encoded the 1.0 contract, then the 2.0 one, and went red at every bump
# (2026-09-03: the 2.5 bump found it asserting 2.0 / 1). The audit's claim is
# that the bundle carries what the project declares, and only that.
MARKETING="$(grep -m1 'MARKETING_VERSION = ' "$REPO/mac4DSTEM.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')"
BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$REPO/mac4DSTEM.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')"
test -n "$MARKETING" && test -n "$BUILD"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" = "$MARKETING"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")" = "$BUILD"
# DERIVED, not literal (2026-09-04). This assertion was hardcoded 26.0 and had
# already been wrong once: S19 raised the target in every configuration
# (aeaeacc, 2026-08-28) without updating it, leaving the harness red on main —
# unnoticed because `all` aborted earlier at real-data-acceptance. A literal
# here re-breaks at every floor change, which is the same mistake the version
# assertion above made and had fixed. What this gate is for is that the SHIPPED
# bundle agrees with the project, not that the floor is any particular number.
FLOOR="$(grep -m1 'MACOSX_DEPLOYMENT_TARGET = ' "$REPO/mac4DSTEM.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")" = "$FLOOR"
# Derived from Info.plist rather than hardcoded: the compiled icon is named
# after ASSETCATALOG_COMPILER_APPICON_NAME, so it moved from AppIcon.icns to
# mac4DSTEM.icns when the icon became an Icon Composer .icon. Asserting the
# literal name checked the build setting, not the thing we care about — that
# the app ships the icon its own Info.plist claims.
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO")"
test -n "$ICON_NAME"
test -f "$APP/Contents/Resources/$ICON_NAME.icns"
# The program's OWN licence, not just its dependencies' (2026-09-11). The bundle
# shipped `Licenses/` — HDF5 and libaec — and the README that points at
# `LICENSE` and `NOTICE`, while neither was in the project at all: a GPL-3.0
# binary conveyed with no copy of the GPL and two dead relative links. Asserted
# non-empty because an empty file would satisfy `-f`.
for document in LICENSE NOTICE; do
  test -s "$APP/Contents/Resources/$document" \
    || { echo "FAIL: bundle is missing $document" >&2; exit 1; }
done
grep -q 'GNU GENERAL PUBLIC LICENSE' "$APP/Contents/Resources/LICENSE"

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
# Asserted on the built Mach-Os, not on the build setting: a change that made
# Float16 compile on x86_64 would turn the red build above green and ship the
# universal binary anyway. lipo is the only thing that cannot be talked round.
assert_mac4dstem_bundle_arm64_only "$APP"

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
echo "PASS: identity, version $MARKETING ($BUILD) and macOS $FLOOR floor as the project declares, and app icon"
echo "PASS: the GPL text and NOTICE ship inside the bundle"
echo "PASS: no Homebrew/local dylib dependency in the Release product"
echo "PASS: executable and embedded libraries are arm64 alone, built the way the archive builds"
echo "package-test: all passed"
