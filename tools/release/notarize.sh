#!/bin/zsh
set -euo pipefail
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"
export DEVELOPER_DIR

APP="${1:?usage: notarize.sh path/to/mac4DSTEM.app [output.zip]}"
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
