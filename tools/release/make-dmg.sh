#!/bin/zsh
# Build the drag-to-Applications disk image that users actually download.
#
# Takes a *stapled* mac4DSTEM.app and produces a signed, compressed DMG. The
# image is signed here but NOT notarized here — run notarize.sh on the result,
# so the download itself carries a stapled ticket and first launch works with
# no network. Stapling the app alone is not enough: Gatekeeper assesses the
# thing the user actually opened.
#
# The window layout is written directly into the image's .DS_Store by dmgbuild
# rather than by driving the Finder with AppleScript. The AppleScript route is
# the common recipe and it does not survive automation: it needs the Automation
# (TCC) grant for whatever shell invokes it, and without a human at the screen
# to approve the prompt it hangs and then fails with -1712. That is exactly what
# happened here on 2026-08-14, and it would fail the same way on any build
# machine. dmgbuild needs no GUI, no Finder, and no permissions.
#
# The background lives at tools/release/dmg-background.png, derived from the
# website's OG artwork (website/assets/og.jpg). It deliberately carries no
# version number so it does not go stale between releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application certificate name}"

APP="${1:?usage: make-dmg.sh path/to/mac4DSTEM.app [output.dmg]}"
[ -d "$APP" ] || { echo "No such app bundle: $APP" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# The compiled icon is named after ASSETCATALOG_COMPILER_APPICON_NAME, so read
# it from Info.plist instead of hardcoding: it changed from AppIcon.icns to
# mac4DSTEM.icns when the icon moved to an Icon Composer .icon.
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")"
BADGE="$APP/Contents/Resources/$ICON_NAME.icns"
[ -f "$BADGE" ] || { echo "No icon at $BADGE — the app did not ship the icon its Info.plist names." >&2; exit 1; }
OUT="${2:-$ROOT/build/release/mac4DSTEM-$VERSION.dmg}"
BACKGROUND="$ROOT/tools/release/dmg-background.png"
[ -f "$BACKGROUND" ] || { echo "Missing background: $BACKGROUND" >&2; exit 1; }

# Build-time only, kept out of the scientific Python environment on purpose.
# Lives under build/ (gitignored); recreate with:
#   python3 -m venv build/dmg-venv && build/dmg-venv/bin/pip install dmgbuild==1.6.1
DMGBUILD="$ROOT/build/dmg-venv/bin/dmgbuild"
if [ ! -x "$DMGBUILD" ]; then
  echo "dmgbuild not found at $DMGBUILD" >&2
  echo "Create it with:" >&2
  echo "  python3 -m venv build/dmg-venv && build/dmg-venv/bin/pip install dmgbuild==1.6.1" >&2
  exit 1
fi

# Refuse to ship an unstapled app. Without this the DMG builds happily and the
# failure only surfaces on a stranger's Mac, which is the worst place to find it.
if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "App is not stapled — run notarize.sh on it first." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Window is 600x400pt; the background is 1200x800px so it renders at @2x.
cat > "$WORK/settings.py" <<SETTINGS
import os.path
app = os.environ["DMG_APP"]
application = os.path.basename(app)

files = [app]
symlinks = {"Applications": "/Applications"}
badge_icon = os.environ["DMG_BADGE_ICON"]

background = os.environ["DMG_BACKGROUND"]
window_rect = ((200, 120), (600, 400))
icon_size = 128
text_size = 13
icon_locations = {
    application: (150, 260),
    "Applications": (450, 260),
}

format = "UDZO"
compression_level = 9
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
SETTINGS

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

DMG_APP="$APP" DMG_BACKGROUND="$BACKGROUND" DMG_BADGE_ICON="$BADGE" \
  "$DMGBUILD" -s "$WORK/settings.py" "mac4DSTEM $VERSION" "$OUT"

codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$OUT"
codesign --verify --strict --verbose=2 "$OUT"

echo
echo "Built:  $OUT"
echo "SHA256: $(shasum -a 256 "$OUT" | cut -d' ' -f1)"
echo
echo "Next:   tools/release/notarize.sh \"$OUT\""
