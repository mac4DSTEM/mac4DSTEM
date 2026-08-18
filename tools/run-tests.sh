#!/bin/zsh
# One discoverable entry point. Cross-language harnesses stay independent of
# XCTest because they validate Python/EMD/package boundaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# Free-space preflight. On 2026-08-06 three consecutive full-suite runs produced
# three *different* failure sets, none related to the code, all caused by a full
# disk, and they were nearly diagnosed as real regressions (docs/v2-scope.md
# §6.6). Measured per-run cost is small — DerivedData 0.2 GB (2026-08-18), plus
# the ~300 MB system log archive `xcodebuild test` writes to /var/tmp per run —
# so the floors below are deliberately margin, not measurement: the failure mode
# is a near-full disk producing varied spurious failures, not a clean ENOSPC.
require_free_space() {
  # NB: `dir`, not `path` — in zsh `path` is tied to $PATH, and declaring it
  # local blanks PATH inside the function (df/awk vanish; caught 2026-08-18).
  local need="$1" what="$2" dir have
  for dir in "$ROOT" "${TMPDIR:-/tmp}"; do
    have="$(df -Pg "$dir" | awk 'NR==2 {print $4}')"
    if [[ -z "$have" ]] || (( have < need )); then
      echo "run-tests.sh: need ${need} GB free for ${what}, have ${have:-?} GB on ${dir}" >&2
      echo "  Free space and re-run; a near-full disk fakes code regressions." >&2
      exit 69
    fi
  done
}

unit_tests() (
  # Never let an unsigned test build replace the app that Xcode launches from
  # its normal DerivedData directory. HDF5 is loaded lazily, so overwriting a
  # running app can otherwise give the process and bundled dylib different code
  # identities and make macOS reject the library.
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-unit-tests.XXXXXX")"
  trap 'rm -rf "$work"' EXIT

  # -only-testing scopes this to the fast unit-test target. Without it,
  # adding mac4DSTEMUITests (tools/ui-qc-playthrough) would silently pull a
  # slow, screen-driving UI playthrough into every normal test run.
  LLVM_PROFILE_FILE="$work/default-%p.profraw" \
    xcodebuild test -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$work/DerivedData" \
      -only-testing:mac4DSTEMTests \
      CODE_SIGNING_ALLOWED=NO -quiet
)

run_harnesses() {
  for name in "$@"; do
    local started=$(date +%s)
    echo "==> $name"
    "$ROOT/tools/$name/run.sh"
    local finished=$(date +%s)
    echo "<== $name ($((finished - started)) s)"
  done
}

scientific=(
  calibration-test calibration-readiness-test virtual-detector-test
  virtual-detector-residency
  disk-detection-test disk-correlation-parity peak-overlay-test fit-overlay-test
  acom-orientation-test acom-matching-test parity-metric-test cif-symmetry-test
  idpc-test cancellation-test
  bragg-export-test sidecar-result-test strain-test ellipse-calibration-test
  dm4-robustness-test vendor-reader-test load-spec-test load-spec-calibration
  preprocess-crop-bin-test load-spec-roundtrip sidecar-error-detail-test
  preprocessing-export-test parallax-preprocessing-test parallax-alignment-test
  parallax-aberration-test parallax-subpixel-test parallax-depth-test
  singleslice-ptychography-test result-presentation-test
  scientific-bundle-test
)
campaign=(
  parallax-preprocessing-test parallax-alignment-test parallax-aberration-test
  parallax-subpixel-test parallax-depth-test singleslice-ptychography-test
  sidecar-result-test result-presentation-test
)

case "${1:-unit}" in
  unit) require_free_space 8 "the xcodebuild unit suite"; unit_tests ;;
  benchmark) require_free_space 4 "the performance baseline"; "$ROOT/tools/performance-baseline/run.sh" ;;
  campaign) require_free_space 8 "the campaign suite"; unit_tests; run_harnesses "${campaign[@]}" ;;
  scientific) require_free_space 4 "the science harnesses"; run_harnesses "${scientific[@]}" ;;
  all) require_free_space 8 "the full suite"; unit_tests; run_harnesses "${scientific[@]}" real-data-acceptance package-test ;;
  *) echo "Usage: tools/run-tests.sh [unit|benchmark|campaign|scientific|all]" >&2; exit 64 ;;
esac
