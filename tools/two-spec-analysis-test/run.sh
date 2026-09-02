#!/bin/zsh
# v2 S2 (docs/v2-release.md §8): the two-spec analysis fixture — the evidence
# for the release claim's word "unchanged". An analysis run on a reduced view
# must reproduce the full-extent run restricted to the overlap. See the header
# of main.swift for the four invariances and for why the comparison is `==`.
#
# Two firsts, both deliberate:
#   - the source list comes from tools/lib/sources.manifest, not from a
#     hand-written list in this file (docs/development-process.md §1);
#   - the harness compiles with the APP's actor-isolation flags, closing the
#     blind spot recorded on 2026-08-18 where every tools/ harness validated
#     different isolation semantics from the app.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/python.sh"
resolve_mac4dstem_python "$REPO"
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"

# The bundled dylibs' signatures don't validate for ad-hoc-built tools; use
# ad-hoc-signed copies in the temp dir instead of touching the repo files.
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

"$PYTHON_BIN" reference.py "$WORK"

# MetalEngine.makeDefaultLibrary() loads default.metallib from Bundle.main, and
# both the virtual detector and the resident cube allocate through it. Build the
# app's real shader sources, then run the harness from that directory.
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do
  name="${source:t:r}"
  xcrun -sdk macosx metal -c "$source" -o "$WORK/$name.air"
done
xcrun -sdk macosx metallib "$WORK"/*.air -o "$WORK/default.metallib"

mac4dstem_sources "$REPO" readers calibration analysis

xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_ISOLATION_FLAGS[@]}" \
  "${MAC4DSTEM_SOURCES[@]}" \
  main.swift \
  -framework Accelerate -framework Metal -framework MetalKit

codesign -f -s - "$WORK/harness" 2>/dev/null

# H5Reader's last dlopen fallback is the plain name "libhdf5.dylib"; run from
# the temp dir so it resolves to the signed copy.
cd "$WORK"
./harness "$WORK"
