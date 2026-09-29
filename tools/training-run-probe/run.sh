#!/bin/zsh
# tools/training-run-probe — C5 (headless half), 2026-09-29. A DIAGNOSTIC: never gates, not in tools/run-tests.sh.
# Runs the app's OWN training pipeline (mac4DSTEM/Training) on the owner's real labels with no AppState, then measures
# the minimum held-out N (C3 pre-registration §4). See main.swift's header for what each part does.
#
#   tools/training-run-probe/run.sh [labels.json] [scratch dir]
#     labels.json  default tools/disk-detector/labels/bullseye-2026-09-28.json (its "cube" must exist under References/)
#     scratch dir  default $TMPDIR/training-run-probe; holds scores.json; candidate packages are deleted after use
#   TR_PROBE_RESAMPLE=<scores.json> tools/training-run-probe/run.sh      §4 only, from a saved scores.json (still builds)
#
# Builds DSTEMCore as a static module (the `core` group of tools/lib/sources.manifest, with the package's settings) and
# compiles Training/*.swift + main.swift as one module against it, so `package` access works as in the app. The bundled
# model is COPIED beside the binary and only ever read. Needs the Neural Engine, about 1.1 GB for training, and >= 1.5 GB
# free on / (polls 60 s, at most 10 minutes, for a build or low space to clear). One heavy job at a time on the 8 GB Mac.
# Exit 69 = no space, 66 = labels or cube missing.
set -euo pipefail
cd "$(dirname "$0")"; REPO="$(cd ../.. && pwd)"

LABELS="${1:-$REPO/tools/disk-detector/labels/bullseye-2026-09-28.json}"; LABELS="${LABELS:A}"
OUT="${2:-${TMPDIR:-/tmp}/training-run-probe}"; mkdir -p "$OUT"; OUT="${OUT:A}"
[[ -f "$LABELS" ]] || { echo "run.sh: no labels file $LABELS" >&2; exit 66; }
CUBE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['cube'])" "$LABELS")"
[[ -f "$CUBE" ]] || { echo "run.sh: the labels' cube is absent: $CUBE" >&2; exit 66; }

preflight() {
  local tries=0 free_mb
  while (( tries <= 10 )); do
    free_mb=$(df -m / | awk 'NR==2{print $4}')
    if (( free_mb >= 1536 )) && ! pgrep -x xcodebuild >/dev/null && ! pgrep -x swift-frontend >/dev/null; then
      echo "preflight ($1): ${free_mb} MB free on /, no xcodebuild / swift-frontend"; return 0
    fi
    echo "preflight ($1): ${free_mb} MB free (need 1536) or a build is running; waiting 60 s (${tries}/10)" >&2
    sleep 60; tries=$((tries + 1))
  done
  echo "run.sh: preflight did not clear in 10 minutes" >&2; exit 69
}

W="$(mktemp -d "${TMPDIR:-/tmp}/tr-probe-build.XXXXXX")"; trap 'rm -rf "${W:?}"' EXIT
. "$REPO/tools/lib/developer-dir.sh"; resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" core

preflight build
for lib in libhdf5 libsz.2 libaec.0; do cp "$REPO/$lib.dylib" "$W/"; codesign -f -s - "$W/$lib.dylib" 2>/dev/null; done
for source in "$REPO"/mac4DSTEM/Shaders/*.metal; do xcrun -sdk macosx metal -c "$source" -o "$W/${source:t:r}.air"; done
xcrun -sdk macosx metallib "$W"/*.air -o "$W/default.metallib"; rm -f "${W:?}"/*.air
cp -R "$REPO/Models/DiskDetector/disk-detector-heatmap-256.mlpackage" "$W/"; chmod -R u+w "$W/disk-detector-heatmap-256.mlpackage"

# the package's settings (Package.swift): Swift 5, MainActor default isolation, four upcoming features, -Xcc for LAPACK
FLAGS=(-package-name mac4DSTEM -O -swift-version 5 -default-isolation MainActor
  -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances
  -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility
  -Xcc -DACCELERATE_NEW_LAPACK)
echo "compiling DSTEMCore ..."
xcrun swiftc "${FLAGS[@]}" -parse-as-library -module-name DSTEMCore -emit-module -emit-module-path "$W/DSTEMCore.swiftmodule" \
  -emit-library -static -o "$W/libDSTEMCore.a" "${MAC4DSTEM_SOURCES[@]}"
echo "compiling Training + probe ..."
xcrun swiftc "${FLAGS[@]}" -parse-as-library -module-name TrainingRunProbe -I "$W" -L "$W" -lDSTEMCore \
  -o "$W/probe" "$REPO"/mac4DSTEM/Training/*.swift main.swift \
  -framework Accelerate -framework Metal -framework MetalKit -framework CoreML -framework MetalPerformanceShadersGraph
codesign -f -s - "$W/probe" 2>/dev/null
rm -f "${W:?}/libDSTEMCore.a"

cd "$W"
if [[ -n "${TR_PROBE_RESAMPLE:-}" ]]; then ./probe resample "${TR_PROBE_RESAMPLE:A}"; exit $?; fi
preflight run
MAC4DSTEM_HDF5_PATH="$W/libhdf5.dylib" ./probe run "$LABELS" "$OUT"
