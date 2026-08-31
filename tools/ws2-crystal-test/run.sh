#!/bin/zsh
# W4a (S14+S15 merged; docs/v2-release.md §9, 2026-08-31): the WS₂ crystal
# fixture. Pins the cited lattice (Schutte/de Boer/Jellinek 1987) against the
# closed-form hexagonal metric, the 6₃-screw extinctions, the c/a = 3.91 shell
# ORDER that magnesium's near-ideal hcp cannot exercise, and the current
# reference-shell selection (a measurement with an open item, not an
# endorsement). Three negative controls prove the fixture can see each wrong
# variant — the Kalikham z(S), the mp-224 DFT c, and a species swap.
#
# Sources come from tools/lib/sources.manifest and compile with the app's
# isolation flags (the S2 conventions). Analytic ground truth; no data files.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"

mac4dstem_sources "$REPO" qcalibration

xcrun swiftc -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  "${MAC4DSTEM_SOURCES[@]}" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit

"$WORK/harness"
