#!/bin/zsh
# tools/free-space.sh — report (default) or delete (--clear) the two classes of
# regenerable build debris this machine accumulates (M1/T1, 2026-08-26):
#
#   1. XcodeBuildMCP workspace debris:
#      ~/Library/Developer/XcodeBuildMCP/workspaces/<ws>/{test-products,
#      result-bundles, DerivedData, logs} — products of past MCP builds and
#      test runs (2026-08-25 alone left ~15 result bundles; test-products
#      reached 5.4 GB). DerivedData is included as regenerable debris beyond
#      the brief's named three (a recorded M1 deviation); `state/` and
#      `locks/` are session configuration, not debris, and are never touched.
#   2. Leaked isolated unit-test DerivedData:
#      ${TMPDIR:-/tmp}/mac4dstem-unit-tests.* — tools/run-tests.sh removes
#      these via an EXIT trap on every ordinary exit, so only a hard kill
#      leaks one. A LIVE run also owns a matching directory, so only
#      directories untouched for >1 hour are eligible (the unit suite runs
#      in minutes; a leaked directory is hours old).
#
# Deliberately excluded: the ~300 MB system log archives `xcodebuild test`
# writes to /var/tmp per run (documented in tools/run-tests.sh) — system-owned
# and outside this script's named roots.
#
# Do NOT run --clear while a build or test run is active: products of a run
# in flight live under the same roots. Nothing else is touched — never
# References/, never the repo, never a path outside the two roots named
# below; guard_path() enforces that structurally on every deletion.
# Report-only by default; not part of any test gate.
set -euo pipefail

MODE="report"
case "${1:-}" in
  --clear) MODE="clear" ;;
  "") ;;
  *) echo "Usage: tools/free-space.sh [--clear]" >&2; exit 64 ;;
esac

MCP_ROOT="$HOME/Library/Developer/XcodeBuildMCP/workspaces"
TMP_ROOT="${TMPDIR:-/tmp}"

# Every path handed to rm must live under one of the two named roots. A bug
# that composes anything else must die here, not in rm.
guard_path() {
  case "$1" in
    "$MCP_ROOT"/*) ;;
    "$TMP_ROOT"/mac4dstem-unit-tests.*) ;;
    *) echo "free-space.sh: refusing unnamed path: $1" >&2; exit 70 ;;
  esac
}

targets=()
for ws in "$MCP_ROOT"/*(/N); do
  for kind in test-products result-bundles DerivedData logs; do
    [[ -e "$ws/$kind" ]] && targets+=("$ws/$kind")
  done
done
# (/Nmh+1): directories only, no-match tolerated, modified >1 hour ago —
# so an in-flight run's working directory is never eligible.
for leaked in "$TMP_ROOT"/mac4dstem-unit-tests.*(/Nmh+1); do
  targets+=("$leaked")
done

echo "== free space before =="
df -g /

if [[ ! -d "$MCP_ROOT" ]]; then
  echo "note: $MCP_ROOT does not exist — XcodeBuildMCP may have moved its" \
       "workspace root; this script's target list would not see the new one."
fi

if (( ${#targets} == 0 )); then
  echo "Nothing to clear — no debris found under the named roots."
  exit 0
fi

echo ""
echo "== targets =="
# Tolerate a target vanishing between the glob and the du (a concurrent
# build rotating DerivedData): report what remains rather than aborting.
du -sh "${targets[@]}" 2>/dev/null | sort -rh || true

if [[ "$MODE" == "report" ]]; then
  echo ""
  echo "Report only. Re-run with --clear to delete the paths above."
  exit 0
fi

echo ""
echo "== clearing (do not run while a build or test is active) =="
for t in "${targets[@]}"; do
  guard_path "$t"
  echo "rm -rf $t"
  rm -rf "$t"
done

echo ""
echo "== free space after =="
df -g /
