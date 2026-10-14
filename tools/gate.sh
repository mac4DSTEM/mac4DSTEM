#!/bin/zsh
# One gate entry: tools/gate.sh <unit|core|scientific|inventory|last> [log-path]
# Takes the machine-wide test-host lock (suite CLAUDE.md "One test host at a
# time"), logs to a file, prints the exit line, stamps green. Never waits:
# when blocked it names the blocking lock files and exits 75.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
L=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks
STAMPS="$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd)/gate-green"
mode="${1:-}"

if [[ "$mode" == last ]]; then
  for f in "$STAMPS"/*(N); do echo "== ${f:t}"; cat "$f"; done
  exit 0
fi
case "$mode" in
  unit|core|scientific|inventory) ;;
  *) echo "Usage: tools/gate.sh <unit|core|scientific|inventory|last> [log-path]" >&2; exit 64 ;;
esac

mkdir -p "$L"
mine=""
cleanup() { [[ -n "$mine" ]] && rmdir "$mine" 2>/dev/null; return 0; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

blockers() {  # print the lock entries that block this mode, with mtime
  local f
  for f in "$L"/drive(N) "$@"; do
    [[ -e "$f" ]] && echo "  ${f:t}  ($(stat -f %Sm -t %Y-%m-%dT%H:%M:%S "$f"))"
  done
}
refuse() {
  echo "gate.sh: $mode blocked by:" >&2
  blockers "$@" >&2
  echo "gate.sh $mode exit 75"
  exit 75
}

if [[ "$mode" == unit || "$mode" == scientific ]]; then
  b=("$L"/unit-*(N))
  [[ -e "$L/drive" || ${#b} -gt 0 ]] && refuse "${b[@]}"
  mkdir "$L/unit-mac4dstem.$$" 2>/dev/null || refuse "$L/unit-mac4dstem.$$"
  mine="$L/unit-mac4dstem.$$"
  b=("$L"/unit-*(N)); b=("${b[@]:#$mine}")
  if [[ -e "$L/drive" || ${#b} -gt 0 ]]; then
    rmdir "$mine" 2>/dev/null; mine=""
    refuse "${b[@]}"
  fi
else
  [[ -e "$L/drive" ]] && refuse
  if mkdir "$L/heavy.1" 2>/dev/null; then mine="$L/heavy.1"
  elif mkdir "$L/heavy.2" 2>/dev/null; then mine="$L/heavy.2"
  else refuse "$L/heavy.1" "$L/heavy.2"; fi
  if [[ -e "$L/drive" ]]; then rmdir "$mine" 2>/dev/null; mine=""; refuse; fi
fi

sha="$(git -C "$ROOT" rev-parse --short HEAD)"
log="${2:-/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/gate-logs/$mode-$(date +%Y%m%d-%H%M%S)-$sha.log}"
mkdir -p "${log:h}"

"$ROOT/tools/run-tests.sh" "$mode" > "$log" 2>&1
rc=$?

echo "log: $log"
tail -n 15 "$log"
if (( rc == 0 )); then
  state=clean
  [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] && state=dirty
  full="$(git -C "$ROOT" rev-parse HEAD)"
  mkdir -p "$STAMPS"
  printf '%s\n%s\n%s\n%s\n' "$full" "$state" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$log" > "$STAMPS/$mode"
  echo "gate.sh: stamped $mode green at $sha ($state)"
fi
echo "gate.sh $mode exit $rc"
exit $rc
