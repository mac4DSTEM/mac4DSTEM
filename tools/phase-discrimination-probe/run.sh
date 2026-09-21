#!/bin/zsh
# Does the ACOM best-score argmax discriminate PHASE on a pattern containing
# two phases? See main.swift's header for the question, the scoring geometry
# that makes it a real risk, and the PRE-REGISTERED pass criterion.
#
# `diagnostic` deliberately: this is a MEASUREMENT that decides whether the
# template-matched classification route in docs/v3-features.md#precipitate-classification
# is viable at all. It becomes a gated invariant only if the measurement passes
# and the route is adopted.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-phase-discrimination.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" acom

for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

xcrun swiftc -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
  main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/probe" 2>/dev/null
cd "$WORK" && "$WORK/probe"
