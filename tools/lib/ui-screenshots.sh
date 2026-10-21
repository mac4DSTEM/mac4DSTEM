#!/bin/zsh
# Exports the screenshot attachments of a UI test result bundle (Xcode 16+): `ui-screenshots.sh <ui.xcresult> <output dir>`.
# Writes the PNGs and a manifest.json naming test, step and file; prunes screenshot folders older than seven days beside it.
set -euo pipefail
bundle="${1:?usage: ui-screenshots.sh <ui.xcresult> <output dir>}"
out="${2:?usage: ui-screenshots.sh <ui.xcresult> <output dir>}"
mkdir -p "$out"
xcrun xcresulttool export attachments --path "$bundle" --output-path "$out"
find "$(dirname "$out")" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
echo "ui-screenshots: $(ls "$out" | wc -l | tr -d ' ') files in $out"
