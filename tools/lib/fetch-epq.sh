#!/bin/zsh
# NIST EPQ data lock for the v5.0 EDX quantification tables (2026-10-05).
#
# mac4DSTEM/Resources/Spectroscopy/{FFastMAC,LineWeights}.csv are byte copies of
# the files below at the pinned EPQ commit (public domain in the US, 17 USC 105;
# the notice in EPQ's LicenseFile.txt must stay in NOTICE). This script re-fetches
# them into a scratch dir and checks both sha256 sums, so the bundled copies are
# reproducible, not trusted. Usage: tools/lib/fetch-epq.sh [verify|update]
set -euo pipefail

EPQ_COMMIT="249dd3f805545bae1e1b2254fd7fd1cd4dc3d8f2"   # usnistgov/EPQ master, 2026-09-10
EPQ_DIR="src/gov/nist/microanalysis/EPQLibrary"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/mac4DSTEM/Resources/Spectroscopy"
SUMS=(
  "c45cabbb451eada4ade3b64ef4d24acba45bfc08f3d93cd43412a8086a4c6409  FFastMAC.csv"
  "e8bb14e683ef19c2b2f039d5696f3a40ed2a296d3cdfdd6c60514821dfe20e5f  LineWeights.csv"
)
mode="${1:-verify}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for f in FFastMAC.csv LineWeights.csv; do
  curl -fsSL "https://raw.githubusercontent.com/usnistgov/EPQ/$EPQ_COMMIT/$EPQ_DIR/$f" -o "$tmp/$f"
done
( cd "$tmp" && printf '%s\n' "${SUMS[@]}" | shasum -a 256 -c - )
if [[ "$mode" == update ]]; then mkdir -p "$DEST"; cp "$tmp/FFastMAC.csv" "$tmp/LineWeights.csv" "$DEST/"; fi
( cd "$DEST" && printf '%s\n' "${SUMS[@]}" | shasum -a 256 -c - )
echo "fetch-epq: bundled copies match EPQ $EPQ_COMMIT"
