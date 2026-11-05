#!/bin/zsh
# The App Store flavour of the release (mac4DSTEM#121): archive with automatic signing, export a signed installer
# package with ExportOptions-AppStore.plist, then check what is inside it. Uploads nothing; tools/release.sh --store
# --upload does that as its own step.
#
#   tools/release/build-app-store.sh <out-dir>
#
# Needs Xcode signed in to Paul's Apple ID (team 3B8SMSSAX4): -allowProvisioningUpdates lets Xcode create the
# "Apple Distribution" and "Mac Installer Distribution" certificates and the App Store profiles on first use.
# STORE_BUILD_NUMBER overrides CURRENT_PROJECT_VERSION when a version has to be uploaded a second time (App Store
# Connect refuses a build number it has seen for that version).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$(dirname "$0")/../lib/release-arch.sh"

OUT="${1:?usage: build-app-store.sh <out-dir>}"
TEAM="${DEVELOPMENT_TEAM:-3B8SMSSAX4}"
ARCHIVE="$OUT/mac4DSTEM-store.xcarchive"
EXPORT="$OUT/store"
mkdir -p "$OUT"
rm -rf "$ARCHIVE" "$EXPORT"

BUILD_ARGS=()
[[ -n "${STORE_BUILD_NUMBER:-}" ]] && BUILD_ARGS+=("CURRENT_PROJECT_VERSION=$STORE_BUILD_NUMBER")

# MACEM_STORE_BUILD=YES is the one switch the store build flips: the Sparkle updater (#122) compiles only when it is
# not set, because the App Store refuses an app that updates itself.
xcodebuild archive \
  -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Release -destination "$MAC4DSTEM_RELEASE_DESTINATION" \
  -archivePath "$ARCHIVE" \
  "$MAC4DSTEM_ARCH_PIN" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" \
  MACEM_STORE_BUILD=YES \
  "${BUILD_ARGS[@]}"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/tools/release/ExportOptions-AppStore.plist" \
  -allowProvisioningUpdates

PKG="$(print -l "$EXPORT"/*.pkg(N) | head -1)"
[[ -f "$PKG" ]] || { echo "FAIL: the export wrote no .pkg to $EXPORT" >&2; exit 1; }

# What App Review checks first, checked here on the product, not on the settings.
pkgutil --check-signature "$PKG" | grep -q "Installer Distribution\|3rd Party Mac Developer Installer" \
  || { echo "FAIL: $PKG is not signed with an installer distribution certificate" >&2; exit 1; }
APP="$ARCHIVE/Products/Applications/mac4DSTEM.app"
assert_mac4dstem_bundle_arm64_only "$APP"
codesign -d --entitlements :- "$APP" > "$OUT/store-entitlements.plist" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$OUT/store-entitlements.plist" 2>/dev/null)" == true ]] \
  || { echo "FAIL: the store app is not sandboxed" >&2; exit 1; }
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$OUT/store-entitlements.plist" >/dev/null 2>&1; then
  echo "FAIL: the store app contains get-task-allow" >&2; exit 1
fi
for bundle in "$APP" "$APP"/Contents/PlugIns/*.appex(N) "$APP"/Contents/XPCServices/*.xpc(N); do
  [[ -f "$bundle/Contents/Resources/PrivacyInfo.xcprivacy" ]] || { echo "FAIL: no privacy manifest in ${bundle:t}" >&2; exit 1; }
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP/Contents/Info.plist" 2>/dev/null)" == false ]] \
  || { echo "FAIL: Info.plist does not answer the export-compliance question" >&2; exit 1; }
[[ ! -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || { echo "FAIL: Sparkle is in the store build" >&2; exit 1; }

echo "$PKG"
