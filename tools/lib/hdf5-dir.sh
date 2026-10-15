#!/bin/zsh
# tools/lib/hdf5-dir.sh — prints the folder holding the three HDF5 dylibs (libhdf5, libsz.2, libaec.0) every reader harness copies,
# ad-hoc signs and points MAC4DSTEM_HDF5_PATH at. They are FormatoKit's (FormatoHDF5's resource), read from the pinned checkout in
# .build/checkouts; the app no longer carries copies at the repo root (2026-10-15). Resolves the packages when the checkout is missing.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
dir="$ROOT/.build/checkouts/FormatoKit/Sources/FormatoHDF5/Resources/hdf5"
[[ -f "$dir/libhdf5.dylib" ]] || (cd "$ROOT" && swift package resolve) >&2
[[ -f "$dir/libhdf5.dylib" ]] || { echo "hdf5-dir.sh: no FormatoKit checkout at $dir (swift package resolve failed?)" >&2; exit 65; }
print -r -- "$dir"
