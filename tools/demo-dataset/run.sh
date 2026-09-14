#!/bin/zsh
# tools/demo-dataset/run.sh — builds the synthetic two-phase AlMgSi 4D-STEM
# demo cube (demo-dataset-brief.md): three Al grains ([001]/[011]/[111]), one
# strained stripe, and beta" precipitates (end-on + needle), with a KNOWN
# truth map, exercising virtual detectors, disk detection, ACOM, strain
# mapping and vector-matched phase mapping all at once.
#
# WHY THIS LIVES HERE AND NOT IN AN EXISTING tools/ DIRECTORY: every other
# harness in this repo CONSUMES a datacube (detects disks in one, fits an
# origin against one, matches vectors against one); none of them WRITES one.
# tools/crystal-structures prints crystal geometry, tools/phase-vector-matching
# exercises the matcher's own invariants on synthetic vectors it builds
# in-process, and tools/datacube-discovery-test's reference.py stamps tiny
# flat-index cubes to test WHICH node H5Reader finds, never what a real
# pattern looks like. Generating a full, physically-plausible datacube from
# the app's own crystal geometry — the thing this tool does — has no existing
# home; a new one is the smaller cost than bending one of those to fit.
#
# DIAGNOSTIC, not gated (tools/run-tests.sh inventory's `diagnostic` list):
# it needs a machine-local Python (numpy/scipy/h5py/Pillow) and the Swift
# toolchain to build export_reflections.swift, takes real wall-clock time,
# and writes a multi-hundred-MB file under References/ (gitignored) — not
# something `scientific`/`all` can run on every commit.
#
# Sources: NOT through tools/lib/sources.manifest. export_reflections.swift
# takes only Crystal.swift + ScatteringFactors.swift, both self-contained
# (no other Core dependents) — not a group sources.manifest defines, and the
# brief's own compile line already names the two files explicitly. (The
# verification pass that checked this dataset against the app's own reader,
# detector and matcher — see the session report — used the manifest's
# `phasevectors readers` group, as tools/phase-map-probe does; it was a
# one-off scratch probe, not part of this generator, so it is not shipped
# here.)
#
# Usage: run.sh [output-dir]   (default: References/demo-dataset)
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
OUT_DIR="${1:-$REPO/References/demo-dataset}"
mkdir -p "$OUT_DIR"

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
if ! "$PYTHON_BIN" -c 'import h5py, PIL' >/dev/null 2>&1; then
  echo "demo-dataset needs h5py and Pillow on top of numpy/scipy. Set PYTHON=/path/to/python." >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-demo-dataset.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "== building export_reflections =="
xcrun swiftc -O -package-name mac4DSTEM -o "$WORK/export" export_reflections.swift \
  "$REPO/mac4DSTEM/Core/Crystal/Crystal.swift" \
  "$REPO/mac4DSTEM/Core/Crystal/ScatteringFactors.swift"
codesign -f -s - "$WORK/export" 2>/dev/null || true

echo "== computing reflection geometry (Al x3 zone axes, beta\" x2 zone axes) =="
"$WORK/export" > "$OUT_DIR/reflections.json"

echo "== rendering the cube (100x100 scan, 128x128 detector) =="
"$PYTHON_BIN" make_demo.py --reflections "$OUT_DIR/reflections.json" --out-dir "$OUT_DIR" --seed 42

echo "== done: $OUT_DIR =="
ls -la "$OUT_DIR"
