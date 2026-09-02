#!/bin/zsh
# The py4DSTEM source lock — fetched, not vendored (2026-09-03).
#
# The parity harnesses read upstream source files by path, and the inline
# `DEVIATION` notes in Core/ cite them by file and line, so the exact upstream
# state matters. Until 2026-09-03 that state was a tracked copy under
# References/; it is now this pinned checkout, made on demand into the
# gitignored References/ folder. Same files, same lines — the pin is the commit
# whose tree matched the tracked copy byte for byte.
set -euo pipefail

PY4DSTEM_LOCK_COMMIT="f050d207851f8accd3aa550365baaf1f38230428"   # dev, 2026-03-26, version 0.14.19
PY4DSTEM_REPO="https://github.com/py4dstem/py4DSTEM.git"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/References/py4DSTEM-dev"

if [[ -f "$DEST/py4DSTEM/version.py" ]]; then
  if [[ -d "$DEST/.git" ]]; then
    have="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ "$have" != "$PY4DSTEM_LOCK_COMMIT" ]]; then
      echo "fetch-py4dstem: $DEST is at $have, lock is $PY4DSTEM_LOCK_COMMIT — checking out the lock" >&2
      git -C "$DEST" fetch -q origin "$PY4DSTEM_LOCK_COMMIT"
      git -C "$DEST" checkout -q "$PY4DSTEM_LOCK_COMMIT"
    fi
  fi
  echo "fetch-py4dstem: lock present ($(grep -o '"[0-9.]*"' "$DEST/py4DSTEM/version.py"))"
  exit 0
fi

mkdir -p "$ROOT/References"
echo "fetch-py4dstem: cloning py4DSTEM at $PY4DSTEM_LOCK_COMMIT into References/" >&2
git clone -q --filter=blob:none "$PY4DSTEM_REPO" "$DEST"
git -C "$DEST" checkout -q "$PY4DSTEM_LOCK_COMMIT"
grep -q '0.14.19' "$DEST/py4DSTEM/version.py" || { echo "fetch-py4dstem: version.py is not 0.14.19 at the lock" >&2; exit 1; }
echo "fetch-py4dstem: ready"
