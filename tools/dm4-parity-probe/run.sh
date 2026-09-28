#!/bin/zsh
# DM4 open/parity probe (Plan C, 2026-09-24). See main.swift. `diagnostic`:
# it needs the owner's multi-GB raw DM4 on an external volume.
#
# RSS watchdog: the probe is killed if its resident memory passes
# DM4_PROBE_RSS_LIMIT_MB (default 2048), so a full read of a 28 GB file into
# anonymous memory cannot take an 8 GB Mac down with it. It did not save the
# Mac on 2026-09-24, and it samples every 0.2 s, so its "peak RSS" misses a
# short run entirely (0 and 5 MB printed where RSS reached 7 and 135 MB,
# 2026-09-28). Quote the probe's own footprint lines, never this peak.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-dm4-parity-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
. "$REPO/tools/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir
. "$REPO/tools/lib/sources.manifest"
mac4dstem_sources "$REPO" readers
for lib in libhdf5 libsz.2 libaec.0; do
  cp "$REPO/$lib.dylib" "$WORK/"
  codesign -f -s - "$WORK/$lib.dylib" 2>/dev/null
done
xcrun swiftc -O -package-name mac4DSTEM -parse-as-library -o "$WORK/probe" \
  main.swift dm4writer.swift "${MAC4DSTEM_SOURCES[@]}" "${MAC4DSTEM_ISOLATION_FLAGS[@]}"
codesign -f -s - "$WORK/probe" 2>/dev/null
LIMIT="${DM4_PROBE_RSS_LIMIT_MB:-2048}"
MAC4DSTEM_HDF5_PATH="$WORK/libhdf5.dylib" "$WORK/probe" "$@" &
PID=$!
PEAK=0
while kill -0 $PID 2>/dev/null; do
  RSS=$(( $(ps -o rss= -p $PID 2>/dev/null || echo 0) / 1024 ))
  (( RSS > PEAK )) && PEAK=$RSS
  if (( RSS > LIMIT )); then
    kill -9 $PID 2>/dev/null
    echo "WATCHDOG: killed at RSS ${RSS} MB (limit ${LIMIT} MB)"
    wait $PID 2>/dev/null || true
    echo "peak RSS ${PEAK} MB"
    exit 3
  fi
  sleep 0.2
done
wait $PID; STATUS=$?
echo "peak RSS ${PEAK} MB"
exit $STATUS
