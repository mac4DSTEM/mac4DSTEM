#!/bin/zsh
# Parallax + single-slice ptychography, measured on one real cube (2026-09-30). See main.swift.
# `diagnostic`: needs a real 4D-STEM cube on local disk; never a gate.
#
#   tools/parallax-ptycho-real-probe/run.sh <cube.h5> preprocess|align|kde <auto|factor>|ptycho <gd|dmap> [options]
#   ptycho probe options: --defocus <A> --c12a <A> --c12b <A>  (py4DSTEM's `defocus`: C10 = -defocus; the parallax fit's C1 implies
#   defocus = -C1, convention_check.py). The reference side is reference_ptycho.py (py4DSTEM, same float32 cube); compare_ptycho.py tabulates the two.
#
# One stage per process (a footprint is a lifetime maximum). The estimator
# (the `memoryLimit` refusal), the default-option run and the raised-limit run
# are all inside main.swift; /usr/bin/time -l on the binary gives the kernel's
# own "peak memory footprint" as a second witness. Quote the probe's lines.
# Exit 3 = the 40 GiB footprint guard fired. The probe binary is built on demand (see PROBE_DIR below).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
# PROBE_DIR=<dir>: keep the compiled binary and its dylibs there and reuse them on the next call (a stage per
# process means many calls; the build is the slow part). Without it everything lives in a temp dir.
if [[ -n "${PROBE_DIR:-}" ]]; then
  WORK="$PROBE_DIR"; mkdir -p "$WORK"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-parallax-ptycho-real-probe.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
fi
if [[ ! -x "$WORK/probe" ]]; then
  . "$REPO/tools/lib/developer-dir.sh"
  resolve_mac4dstem_developer_dir
  . "$REPO/tools/lib/sources.manifest"
  mac4dstem_sources "$REPO" readers parallax ptychography
  for lib in libhdf5 libsz.2 libaec.0; do
    cp "$REPO/$lib.dylib" "$WORK/"
    codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
  done
  xcrun swiftc -O -swift-version 5 -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
    main.swift "${MAC4DSTEM_SOURCES[@]}" -framework Accelerate
  codesign -f -s - "$WORK/probe" 2>/dev/null
fi
export MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib"
/usr/bin/time -l "$WORK/probe" "$@"
