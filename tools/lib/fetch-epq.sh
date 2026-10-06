#!/bin/zsh
# NIST EPQ data lock for the v5.0 EDX quantification tables (2026-10-05).
#
# mac4DSTEM/Resources/Spectroscopy/*.csv listed below are byte copies of the files at the
# pinned EPQ commit (public domain in the US, 17 USC 105; the notice in EPQ's LicenseFile.txt
# must stay in NOTICE). This script re-fetches them into a scratch dir and checks every
# sha256, so the bundled copies are reproducible, not trusted.
# Usage: tools/lib/fetch-epq.sh [verify|update]
set -euo pipefail

EPQ_COMMIT="249dd3f805545bae1e1b2254fd7fd1cd4dc3d8f2"   # usnistgov/EPQ master, 2026-09-10
EPQ_DIR="src/gov/nist/microanalysis/EPQLibrary"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/mac4DSTEM/Resources/Spectroscopy"
# upstream path (under EPQ_DIR)  |  bundled name  |  sha256
FILES=(
  "FFastMAC.csv|FFastMAC.csv|c45cabbb451eada4ade3b64ef4d24acba45bfc08f3d93cd43412a8086a4c6409"
  "LineWeights.csv|LineWeights.csv|e8bb14e683ef19c2b2f039d5696f3a40ed2a296d3cdfdd6c60514821dfe20e5f"
  "SalvatXion/SalvatXionA.csv|SalvatXionA.csv|9102543bf6029eea78991aa8fab23ddedfb33255e62144af4e6c6fb1a1f5e093"
  "SalvatXion/SalvatXionB.csv|SalvatXionB.csv|7c777ac065117c46102f73d3ca1c3da8e4d0235b254e60c410b82c87cfdf5796"
  "SalvatXion/xionUis.csv|xionUis.csv|69df1ce59fc440cf6f66e1b7c3e2f188258497ae51622d62f283d38bf9b3cf4f"
  "Krause1979.csv|Krause1979.csv|e596dfc7b77443b16017d53d6a15276bc8baf2141eda8ebca4c3054e0ed6b9f4"
)
mode="${1:-verify}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sums=()
for entry in "${FILES[@]}"; do
  up="${entry%%|*}"; rest="${entry#*|}"; name="${rest%%|*}"; sum="${rest##*|}"
  curl -fsSL "https://raw.githubusercontent.com/usnistgov/EPQ/$EPQ_COMMIT/$EPQ_DIR/$up" -o "$tmp/$name"
  sums+=("$sum  $name")
done
( cd "$tmp" && printf '%s\n' "${sums[@]}" | shasum -a 256 -c - )
if [[ "$mode" == update ]]; then mkdir -p "$DEST"; for entry in "${FILES[@]}"; do rest="${entry#*|}"; cp "$tmp/${rest%%|*}" "$DEST/"; done; fi
( cd "$DEST" && printf '%s\n' "${sums[@]}" | shasum -a 256 -c - )
echo "fetch-epq: bundled copies match EPQ $EPQ_COMMIT"
