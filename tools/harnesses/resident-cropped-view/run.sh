#!/bin/zsh
# Gate B, 2026-08-28: the resident fast path on a CROPPED + BINNED view, where
# `descriptor.rx` is NOT the source scan width and a resident "scan row" is not
# a whole source scan row.
#
# WHY THIS EXISTS AS A SEPARATE HARNESS. `tools/harnesses/virtual-detector-residency`
# builds every array at full extent, where `descriptor.rx == source.rx`, so it
# is structurally blind to this class: mutating `FourDArray.swift`'s pattern
# slice from `descriptor.rx` to `view.source.rx` leaves all 27 of its
# assertions GREEN. This harness goes red at view (1, 0). Demonstrated by the
# Gate B second reader, 2026-08-28, and adopted here from its probe.
#
# Ground truth is computed by explicit source-coordinate arithmetic, NOT through
# `LoadView`'s `fromFullCube` helpers, so a shared convention error between the
# reader and the view cannot cancel — the L3 self-consistency trap that
# `virtual-detector-residency` documents in its own pattern loop.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-resident-cropped-view.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" analysis calibration
xcrun swiftc -package-name mac4DSTEM -o "$WORK/harness" main.swift \
  "${MAC4DSTEM_SOURCES[@]}" \
  -framework Accelerate -framework Metal -framework MetalKit

mac4dstem_copy_bundles "$WORK"   # MacEMUI_ShellMetal.bundle: MetalEngine's Metal library
cd "$WORK"
./harness
