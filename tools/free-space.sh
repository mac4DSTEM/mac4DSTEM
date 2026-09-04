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
# Deliberately excluded from DELETION, but reported since 2026-09-04: the
# regenerable caches that actually fill this disk sit outside both roots, so
# this script could answer "nothing to clear" while the gate refused to run —
# measured that day: 680 KB of targets against 743 MB in Xcode's own
# DerivedData, and two exit-69 refusals in one session. It now SURVEYS those roots and prints the gate's
# own verdict. The survey is report-only in every mode — nothing it names is
# ever passed to rm, and guard_path() still refuses anything outside the two
# roots below. Widening what --clear deletes is a separate decision with the
# owner, not a side effect of being able to see more.
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
# Reporting only. Never a deletion root: guard_path() below does not admit it.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
# The volumes the preflight actually measures, not `/`: on a non-boot
# checkout they differ, and `/` was the wrong answer to the only question
# this script is asked.
df -g "$REPO_ROOT" "$TMP_ROOT" | awk '!seen[$0]++'

# The question this script exists to answer is "will the gate run?", so answer
# it. run-tests.sh's preflight measures BOTH the repo's volume and $TMPDIR and
# refuses at the larger floor of 8 GB (run-tests.sh: require_free_space).
GATE_FLOOR=8
echo ""
echo "== will the gate run? (run-tests.sh floor: ${GATE_FLOOR} GB on each) =="
for dir in "$REPO_ROOT" "$TMP_ROOT"; do
  have="$(df -Pg "$dir" | awk 'NR==2 {print $4}')"
  if [[ -z "$have" ]] || (( have < GATE_FLOOR )); then
    printf "  %-6s %3s GB  %s\n" "NO" "${have:-?}" "$dir"
  else
    printf "  %-6s %3s GB  %s\n" "yes" "$have" "$dir"
  fi
done

# Regenerable space this script will NOT delete. Reported because the two
# roots above are usually the smaller half of the problem, and because the
# person reading this is the one allowed to decide.
echo ""
echo "== not cleared by this script — regenerable, but yours to judge =="
survey() {
  [[ -e "$1" ]] || return 0
  printf "  %8s  %s\n" "$(du -sh "$1" 2>/dev/null | cut -f1)" "${1/#$HOME/~}   # $2"
}
survey "$HOME/Library/Developer/Xcode/DerivedData" \
  "Xcode's own build state — deleting it costs a full rebuild, and the Debug app you launch lives here"
for mc in "$HOME"/Library/Developer/Xcode/DerivedData/*/ModuleCache.noindex(/N); do
  survey "$mc" "pure cache, regenerates — the safest thing here to delete"
done
survey "$HOME/Library/Developer/Xcode/CodingAssistant" "editor cache"
survey "$HOME/Library/Developer/CoreSimulator/Caches" "simulator caches (this project is macOS-only)"
survey "$REPO_ROOT/.build" "SwiftPM build products"
echo ""
echo "  PROTECTED, never regenerable: $REPO_ROOT/build/release"
echo "            notarized and stapled disk images (docs/releasing.md: preserve them)"

if [[ ! -d "$MCP_ROOT" ]]; then
  echo "note: $MCP_ROOT does not exist — XcodeBuildMCP may have moved its" \
       "workspace root; this script's target list would not see the new one."
fi

if (( ${#targets} == 0 )); then
  echo ""
  echo "Nothing to CLEAR — no debris under the two roots this script owns."
  echo "If the gate says NO above, the space is in the survey, and freeing it"
  echo "is your call, not this script's."
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
df -g "$REPO_ROOT" "$TMP_ROOT" | awk '!seen[$0]++'
