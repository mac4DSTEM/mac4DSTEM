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
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-cif-symmetry-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" crystal
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" main.swift \
  -framework Accelerate

"$WORK/harness"
