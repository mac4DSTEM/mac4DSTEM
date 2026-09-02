#!/bin/zsh
# Baseline + parity gate for the Bragg disk-correlation path — the step a
# Metal backend is meant to accelerate (ROADMAP B4).
#
# Compiles the *production* Core sources (not a copy) against a small harness,
# so the thing measured is the thing that ships. Input is generated from a
# fixed seed, so this needs no dataset and runs in seconds — unlike the QC
# playthrough, this is a loop you can iterate against.
#
#   tools/disk-correlation-parity/run.sh              # verify against baseline.json
#   tools/disk-correlation-parity/run.sh --record     # re-pin the baseline
#   tools/disk-correlation-parity/run.sh --backend cpu-parallel  # the shipping path
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# -O so the timing reflects a release build. Without it the CPU baseline is
# unrepresentatively slow and any GPU comparison is flattering by default.
xcrun swiftc -package-name mac4DSTEM -O -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  -framework Accelerate -framework Metal

# Two detector sizes, both against their own pinned baseline:
#   128 — the historical fixture (a vDSP radix-2 length);
#   250 — the FFT-session case (2·5³, no vDSP_DFT setup exists for it), pinned
#         on the scalar exact-DFT path BEFORE the arbitrary-length FFT landed,
#         so the fast path is judged against the slow-but-exact one it replaced
#         (docs/s22-ux-design.md §6, FFT speedup session). Fewer patterns
#         because the pre-change path ran ~100 ms/pattern.
"$WORK/harness" --baseline "$PWD/baseline.json" "$@"
echo
"$WORK/harness" --detector 250 --patterns 32 --baseline "$PWD/baseline-250.json" "$@"
