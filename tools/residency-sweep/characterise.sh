#!/bin/zsh
# Resident vs streamed, characterised (2026-09-30). NOT a gate: needs multi-GB local files.
#
#   tools/residency-sweep/characterise.sh <out.tsv> <repeats> <file> <rows> [<rows> ...]
#
# For every row count, `repeats` times: drop the file's cached pages, run the
# streamed cell; drop them again, run the resident cell (cold preload); then a
# second resident cell with the file still cached (warm preload). One process
# per cell, every sample appended to <out.tsv> with the page-cache fraction it
# started from, footprint, swap and pressure. Predictions are written before
# the run (docs/archive/v4/residency-characterisation-2026-09-30/).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-residency-char.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <out.tsv> <repeats> <file> <rows> [<rows> ...]" >&2
  exit 64
fi
OUT="${1:A}"; REPEATS="$2"; DATASET="${3:A}"; shift 3
PASSES="${RESIDENCY_PASSES:-3}"

for lib in libhdf5 libsz.2 libaec.0; do
  cp "$ROOT/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
for source in "$ROOT"/mac4DSTEM/Shaders/*.metal; do
  xcrun -sdk macosx metal -c "$source" -o "$WORK/${source:t:r}.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" readers analysis calibration
xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/residency-sweep/main.swift" \
  -framework Accelerate -framework Metal -framework MetalKit || exit 70
codesign -f -s - "$WORK/harness" 2>/dev/null

cd "$WORK"
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
cell() {  # cell <mode> <rows>; a refused allocation (exit 2) is a result, not an abort
  ./harness "$DATASET" --characterise --mode "$1" --rows "$2" --passes "$PASSES" --out "$OUT"
  local exit_code=$?
  echo "# cell $1 rows $2 exit $exit_code  $(sysctl -n vm.swapusage)"
}
for rows in "$@"; do
  for repeat in $(seq 1 "$REPEATS"); do
    echo "# rows $rows repeat $repeat"
    ./harness "$DATASET" --characterise --mode evict
    cell streamed "$rows"
    ./harness "$DATASET" --characterise --mode evict
    cell resident "$rows"
    cell resident "$rows"
  done
done
