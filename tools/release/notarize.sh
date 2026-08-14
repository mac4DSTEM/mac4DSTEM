#!/bin/zsh
set -euo pipefail
. "$(dirname "$0")/../lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"

TARGET="${1:?usage: notarize.sh path/to/mac4DSTEM.app [output.zip]  |  path/to/mac4DSTEM.dmg}"

# A .dmg is submitted as-is and stapled in place; an .app has to be zipped for
# submission, and the ticket is stapled to the bundle rather than to the zip.
# Both paths end in an spctl assessment, because a stapled ticket that
# Gatekeeper still rejects is exactly the failure users would hit first.
if [[ "$TARGET" == *.dmg ]]; then
  xcrun notarytool submit "$TARGET" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$TARGET"
  xcrun stapler validate "$TARGET"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$TARGET"
  echo
  echo "Notarized: $TARGET"
  echo "SHA256:    $(shasum -a 256 "$TARGET" | cut -d' ' -f1)"
  exit 0
fi

APP="$TARGET"
OUT="${2:-${APP:h}/mac4DSTEM-1.0.zip}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ditto -c -k --keepParent "$APP" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
ditto -c -k --keepParent "$APP" "$OUT"
echo "$OUT"
