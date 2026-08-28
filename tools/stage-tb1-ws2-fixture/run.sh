#!/bin/zsh
# Re-stage TB1 sitting 2's WS2 sidecar fixture.
#
# WHY THIS EXISTS AS A SCRIPT. The fixture is a machine-local file under the
# gitignored References/, and it has already gone missing once: on 2026-08-27
# TB1 sitting 2 found it gone, which blocked Track B row F1.26 and left
# TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes permanently
# skipped. A fixture nobody can rebuild is a fixture that will vanish again, so
# the RECIPE lives in the repo even though the artefact cannot.
#
# WHAT IT MAKES. A session sidecar beside polycrystal_2D_WS2.h5 recording a
# 200x200 scan crop. WS2's scan is 128x128, so LoadView(source:specification:)
# throws, AppState arms gates.sidecarRestoreFailure = .doesNotFit, and the
# session-rewrite gates close. That is the state F1.26 reads on screen.
#
# WHY IT IS SYNTHESISED RATHER THAN DRIVEN. No cube in the training set is
# 200x200 or larger in scan (Si_SiGe is 50x200, sim_Au 100x84, WS2 128x128), so
# no amount of driving the app can produce a specification WS2 cannot fit. The
# base file is a real sidecar the app wrote; only the specification attribute
# and the minimum-reader marker are synthesised.
#
# NOT a gating harness - it needs gitignored multi-GB data, so it is deliberately
# absent from tools/run-tests.sh.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
T="$REPO/References/training_dataset"
SOURCE="$T/downsample_Si_SiGe_exp.mac4dstem.h5"
TARGET="$T/polycrystal_2D_WS2.mac4dstem.h5"

[[ -f "$T/polycrystal_2D_WS2.h5" ]] || { print -u2 "missing $T/polycrystal_2D_WS2.h5"; exit 1; }
[[ -f "$SOURCE" ]] || { print -u2 "missing a real sidecar to base it on: $SOURCE"; exit 1; }
whence h5cc >/dev/null || { print -u2 "h5cc not found (brew install hdf5)"; exit 1; }

if [[ -e "$TARGET" ]]; then
  print "$TARGET already exists — remove it first if you want it rebuilt."
  exit 0
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$SOURCE" "$TARGET"
h5cc -o "$WORK/stage" stage.c
"$WORK/stage" "$TARGET"

print "staged $TARGET"
print "verify: tools/run-tests.sh unit — TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes"
print "        should PASS rather than skip (388 passed / 3 skipped as of 2026-08-28)."
