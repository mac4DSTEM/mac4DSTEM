#!/bin/zsh
set -eu

# Checks Core/Data/ResultPresentation.swift's ScientificSeriesGeometry (point/
# scale mapping, non-finite gap handling, nearest-index selection) and
# SessionResultPresentation/SessionControlRehydration (sampling labels,
# provenance strings, parsing malformed/legacy/unsupported session
# provenance). No py4DSTEM comparison; this is mac4DSTEM's own result-display
# logic. Run with no arguments: tools/result-presentation-test/run.sh. Listed
# in both the `scientific` and `campaign` arrays of tools/run-tests.sh (and
# `all`). Pass condition: require() prints "FAIL: ..." and exits 1 on any
# failed check; final line "result presentation: geometry, metadata, and
# rehydration cases passed".

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-result-presentation.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" presentation
xcrun swiftc -package-name mac4DSTEM \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/result-presentation-test/main.swift" \
  -o "$TMP/result-presentation-test" -framework Accelerate
"$TMP/result-presentation-test"
