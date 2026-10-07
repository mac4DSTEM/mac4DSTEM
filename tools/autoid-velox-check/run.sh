#!/bin/zsh
# tools/autoid-velox-check/run.sh — the room's Auto ID against the elements Velox's own session had selected (lane L10, 2026-10-07).
# DIAGNOSTIC, never a gate (tools/run-tests.sh inventory's `diagnostic` list): it needs the owner's private Velox SI files.
#
#   tools/autoid-velox-check/run.sh [--all] [--out <dir>] <file.emd | folder>...
#   tools/autoid-velox-check/run.sh --out /tmp/autoid /Volumes/PL_SSD_2TB/NAS_Backup/01_projects
#
# Each file's stored element selection (VeloxEMDReader.storedElementSelection) is the truth; the harness prints one line per file
# (velox / app / hits / extras) and the precision and recall over the set. See main.swift's header. Nothing is written beside a file.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-autoid-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# Ad-hoc-signed copies of the bundled dylibs, as every reader harness does.
for l in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$l.dylib" "$WORK/"
  codesign -f -s - "$WORK/$l.dylib" 2>/dev/null
done

. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers
CORE="$REPO/mac4DSTEM/Core"
# MaskTransport and PoolBuilder map masks between a 4D cube and the map (PhaseMap, Analysis): nothing Auto ID uses.
SPECTRO=("$CORE"/Spectroscopy/**/*.swift(N))
SPECTRO=(${SPECTRO:#*/Registration/(MaskTransport|PoolBuilder).swift})
xcrun swiftc -package-name mac4DSTEM -O -parse-as-library -o "$WORK/harness" \
  "${MAC4DSTEM_SOURCES[@]}" "$CORE/Crystal/ScatteringFactors.swift" "${SPECTRO[@]}" \
  "$REPO/mac4DSTEM/UI/Spectroscopy/SpectroscopyLogic.swift" "$REPO/mac4DSTEM/UI/Spectroscopy/AutoIDPresentation.swift" \
  main.swift "${MAC4DSTEM_ISOLATION_FLAGS[@]}" -Xcc -DACCELERATE_NEW_LAPACK -framework Accelerate
codesign -f -s - "$WORK/harness" 2>/dev/null

MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/harness" "$@"
