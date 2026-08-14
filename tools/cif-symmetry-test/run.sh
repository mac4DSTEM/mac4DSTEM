#!/bin/zsh
# CIFImport point-group admission: the cell metric proposes a family, the
# atom positions have to confirm it.
#
# Guards the specific regression this fixture was written for — a trigonal
# structure in the conventional hexagonal setting (a = b, γ = 120°, 3-fold
# only) being admitted as `.hexagonal`, which hands it a 12-operator
# fundamental zone and an IPF key it does not have. Pure algebra over
# fractional coordinates, no dataset dependency, so it is cheap to gate.
#
# Both directions matter: the fixture also pins that diamond silicon and HCP
# magnesium — shipped built-in models whose defining rotation carries a
# translation — are still admitted.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

SRC="$REPO/mac4DSTEM/Core"
xcrun swiftc -O -parse-as-library -o "$WORK/harness" \
  "$SRC/Data/DiffractionPattern.swift" \
  "$SRC/Analysis/OrientationResult.swift" \
  "$SRC/Crystal/ScatteringFactors.swift" \
  "$SRC/Crystal/Crystal.swift" \
  "$SRC/Crystal/CrystalModel.swift" \
  "$SRC/Crystal/CIFImport.swift" \
  main.swift \
  -framework Accelerate

"$WORK/harness"
