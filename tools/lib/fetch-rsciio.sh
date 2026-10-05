#!/bin/zsh
# The rosettasciio source + test-data lock — fetched, not vendored (v5.0 WP1, 2026-10-05).
#
# rosettasciio (rsciio) is the reference reader for Velox EMD spectrum images
# (ADR 053; docs/archive/v5/wp1-spectrum-readers-preregistration-2026-10-05.md).
# `tools/velox-parity` reads its Velox test zips and runs its reader as truth,
# and the inline `DEVIATION` notes in Core/Data/VeloxEMDReader.swift cite its
# source by file, so the exact upstream state matters. The test zips are 2-9 MB,
# over the 1 MiB tracked-file guard, so they are fetched with the pin into the
# gitignored References/ folder, the way fetch-py4dstem.sh does for py4DSTEM.
set -euo pipefail

RSCIIO_LOCK_COMMIT="049e7d7070e84779b499adaf3295beee9facb004"   # main, 2026-10-05, version 0.14.0
RSCIIO_REPO="https://github.com/hyperspy/rosettasciio.git"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/References/rosettasciio"

if [[ -f "$DEST/rsciio/emd/_emd_velox.py" ]]; then
  if [[ -d "$DEST/.git" ]]; then
    have="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ "$have" != "$RSCIIO_LOCK_COMMIT" ]]; then
      echo "fetch-rsciio: $DEST is at $have, lock is $RSCIIO_LOCK_COMMIT — checking out the lock" >&2
      git -C "$DEST" fetch -q origin "$RSCIIO_LOCK_COMMIT"
      git -C "$DEST" checkout -q "$RSCIIO_LOCK_COMMIT"
    fi
  fi
  echo "fetch-rsciio: lock present"
  exit 0
fi

mkdir -p "$ROOT/References"
echo "fetch-rsciio: cloning rosettasciio at $RSCIIO_LOCK_COMMIT into References/" >&2
git clone -q --filter=blob:none "$RSCIIO_REPO" "$DEST"
git -C "$DEST" checkout -q "$RSCIIO_LOCK_COMMIT"
[[ -f "$DEST/rsciio/tests/data/emd/velox_emd_version11.zip" ]] \
  || { echo "fetch-rsciio: the Velox test zips are missing at the lock" >&2; exit 1; }
echo "fetch-rsciio: ready"
