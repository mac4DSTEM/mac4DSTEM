#!/bin/zsh
# One discoverable entry point. Cross-language harnesses stay independent of
# XCTest because they validate Python/EMD/package boundaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

unit_tests() (
  # Never let an unsigned test build replace the app that Xcode launches from
  # its normal DerivedData directory. HDF5 is loaded lazily, so overwriting a
  # running app can otherwise give the process and bundled dylib different code
  # identities and make macOS reject the library.
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-unit-tests.XXXXXX")"
  trap 'rm -rf "$work"' EXIT

  LLVM_PROFILE_FILE="$work/default-%p.profraw" \
    xcodebuild test -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$work/DerivedData" \
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
  disk-detection-test peak-overlay-test acom-orientation-test acom-matching-test
  idpc-test cancellation-test
  bragg-export-test sidecar-result-test strain-test ellipse-calibration-test
  vendor-reader-test
  preprocessing-export-test parallax-preprocessing-test parallax-alignment-test
  parallax-aberration-test parallax-subpixel-test parallax-depth-test
  singleslice-ptychography-test result-presentation-test
)
campaign=(
  parallax-preprocessing-test parallax-alignment-test parallax-aberration-test
  parallax-subpixel-test parallax-depth-test singleslice-ptychography-test
  sidecar-result-test result-presentation-test
)

case "${1:-unit}" in
  unit) unit_tests ;;
  benchmark) "$ROOT/tools/performance-baseline/run.sh" ;;
  campaign) unit_tests; run_harnesses "${campaign[@]}" ;;
  scientific) run_harnesses "${scientific[@]}" ;;
  all) unit_tests; run_harnesses "${scientific[@]}" real-data-acceptance package-test ;;
  *) echo "Usage: tools/run-tests.sh [unit|benchmark|campaign|scientific|all]" >&2; exit 64 ;;
esac
