#!/bin/zsh
# usage: heavy-build.sh <logfile> <command...> — a build slot (heavy.1|heavy.2) for a build that launches no test host or app;
# does not wait on macTEM unit-* locks (suite CLAUDE.md: those exclude runs that launch a test host or the app). Exit in <log>.exit.
LOCKS=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks
log="$1"; shift; slot=""
while [[ -z "$slot" ]]; do
  if mkdir "$LOCKS/heavy.1" 2>/dev/null; then slot="$LOCKS/heavy.1"
  elif mkdir "$LOCKS/heavy.2" 2>/dev/null; then slot="$LOCKS/heavy.2"
  else sleep 15; fi
done
trap 'rmdir "$slot" 2>/dev/null' EXIT INT TERM
echo "heavy-build.sh: slot $slot, started $(date '+%H:%M:%S')" > "$log"
"$@" >> "$log" 2>&1; rc=$?
echo "heavy-build.sh: exit $rc at $(date '+%H:%M:%S')" >> "$log"; echo $rc > "$log.exit"; exit $rc
