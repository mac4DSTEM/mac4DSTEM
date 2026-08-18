#!/bin/zsh
# S1: a refused sidecar open must report WHY, not just THAT it failed.
# See main.swift for the two cases and the negative control.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d)"
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

for library in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$library.dylib" "$WORK/"
  codesign -f -s - "$WORK/$library.dylib" 2>/dev/null
done

xcrun swiftc -o "$WORK/harness" \
  main.swift \
  "$REPO/mac4DSTEM/Core/Data/HDF5Types.swift" \
  "$REPO/mac4DSTEM/Core/Data/FourDDataSource.swift" \
  "$REPO/mac4DSTEM/Core/Data/LoadSpecification.swift" \
  "$REPO/mac4DSTEM/Core/Data/Calibration.swift" \
  "$REPO/mac4DSTEM/Core/Data/DatasetDescriptor.swift" \
  "$REPO/mac4DSTEM/Core/Data/DiffractionPattern.swift" \
  "$REPO/mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift" \
  "$REPO/mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift" \
  "$REPO/mac4DSTEM/Core/Compute/FFT2D.swift" \
  "$REPO/mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/ProbeKernel.swift" \
  "$REPO/mac4DSTEM/Core/Analysis/DiskDetection.swift" \
  -framework Accelerate -framework Metal
codesign -f -s - "$WORK/harness" 2>/dev/null

export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"

# Case A — a POSIX-unreadable file (EACCES).
"$WORK/harness" "$WORK" posix

# Case B — the shape the app actually hits: a perfectly readable file that the
# SANDBOX refuses (EPERM). This is not interchangeable with case A — a sandbox
# denial is `errno = 1 'Operation not permitted'`, a chmod-000 denial is
# `errno = 13 'Permission denied'` — and getting that backwards is what would
# have made the S1 experiment reach the wrong verdict. Measured 2026-08-19.
if ! command -v sandbox-exec >/dev/null 2>&1; then
  echo "FAIL: sandbox-exec is unavailable; the sandbox denial shape went untested" >&2
  echo "  Do not treat this as a skip - it is the case the fixture exists for." >&2
  exit 1
fi
# Written by the harness itself in a first pass, so the denied file is a real
# HDF5 file rather than a signature stub (see main.swift).
"$WORK/harness" "$WORK" write-denied-fixture
# The profile must name the RESOLVED path: $WORK is /var/folders/... which the
# kernel resolves to /private/var/folders/..., and a `literal` rule against the
# unresolved form silently matches nothing — the denial would not fire and the
# case would pass for the wrong reason.
WORK_REAL="$(cd "$WORK" && pwd -P)"
cat > "$WORK/deny.sb" <<PROFILE
(version 1)
(allow default)
(deny file-read-data (literal "$WORK_REAL/denied-sandboxed.mac4dstem.h5"))
PROFILE
sandbox-exec -f "$WORK/deny.sb" "$WORK/harness" "$WORK" sandboxed
