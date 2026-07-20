#!/bin/zsh
# Visible, on-screen QC playthrough: drives the real mac4DSTEM app through
# calibrate -> orientation map -> virtual DF for every .h5 in
# References/training_dataset, via the mac4DSTEMUITests XCUITest target.
#
# This is NOT part of tools/run-tests.sh — it opens and drives real app
# windows on your screen and can take a while for multi-gigabyte datasets,
# so it only runs when you invoke it directly.
#
# First run requires Accessibility permission for the process driving the
# test (Xcode, or this terminal if run headlessly) — System Settings >
# Privacy & Security > Accessibility. Same requirement as
# tools/ui-smoke-test, which uses the same underlying automation surface.
#
# Optional: pass one or more filename substrings to run only matching
# datacubes, e.g. `tools/ui-qc-playthrough/run.sh sim_Au` for just one file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

# A file, not an env var: xcodebuild's UI-test runner process does not
# reliably inherit env vars exported by this shell.
FILTER_FILE="$ROOT/.ui-qc-filter"
if (( $# > 0 )); then
  filter="$(IFS=,; echo "$*")"
  echo "$filter" > "$FILTER_FILE"
  echo "Running only datacubes matching: $filter"
else
  rm -f "$FILTER_FILE"
fi

# Persistent DerivedData (gitignored) so iterating on the test rebuilds
# incrementally instead of recompiling the whole app every run.
DERIVED="${MAC4DSTEM_UI_QC_DERIVED:-$ROOT/build/ui-qc-DerivedData}"
mkdir -p "$DERIVED"

echo "Building the QC playthrough…"
xcodebuild build-for-testing -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:mac4DSTEMUITests \
  CODE_SIGNING_ALLOWED=NO

# CODE_SIGNING_ALLOWED=NO leaves every product fully unsigned. A unit-test
# bundle loads in-process into the already-signed host app, so that's fine,
# but a UI test launches its own separate Runner.app — an unsigned one fails
# to even launch (Gatekeeper reports it as "damaged"). Ad-hoc signing is
# enough for local automation; matches tools/ui-smoke-test/run.sh's same
# workaround.
find "$DERIVED/Build/Products/Debug" -maxdepth 1 -name "*.app" -print0 \
  | xargs -0 -I{} codesign --force --deep --sign - "{}"

echo "Running the QC playthrough — the app will open real windows on screen."
xcodebuild test-without-building -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:mac4DSTEMUITests
