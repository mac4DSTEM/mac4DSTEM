#!/bin/zsh
set -euo pipefail
# reference.py writes synthetic EMPAD (raw+xml) and MIB (repeated-header, big-endian U16) fixture
# files; the Swift harness runs Core/Data/VendorRawReaders.swift's EMPADReader and MIBReader against
# them, checking shape/dtype discovery, pattern and scan-tile reads, footer/header handling, and that
# an ambiguous raw-only EMPAD file is refused with actionable guidance. No py4DSTEM comparison; these
# are hand-built vendor fixtures. Run with no arguments: tools/vendor-reader-test/run.sh. Listed in
# the scientific array of tools/run-tests.sh, so it runs under tools/run-tests.sh scientific (and
# all). Pass condition: fail() prints FAIL: ... and exits 1 on any mismatch; final line
# vendor-reader-test: all passed.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-vendor-reader-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
python3 "$ROOT/tools/vendor-reader-test/reference.py" "$WORK"
. "$ROOT/tools/lib/sources.manifest"
mac4dstem_sources "$ROOT" readers
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library \
  "${MAC4DSTEM_SOURCES[@]}" "$ROOT/tools/vendor-reader-test/main.swift" \
  -o "$WORK/vendor-reader-test" -framework Accelerate
"$WORK/vendor-reader-test" "$WORK"
