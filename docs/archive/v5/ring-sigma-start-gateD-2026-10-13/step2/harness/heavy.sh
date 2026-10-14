#!/bin/zsh
# usage: heavy.sh <logfile> <command...>
# Takes a build slot (locks/heavy.1 or heavy.2), runs the command with all output to <logfile>,
# writes the exit code to <logfile>.exit, releases the slot. Never reports through a pipe.
# Waits while a `drive` file or any macTEM `unit-*` file is in the locks dir (one test host machine-wide,
# suite CLAUDE.md 2026-10-14); re-checks after taking the slot, so a macTEM run that started meanwhile wins.
LOCKS=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks
mkdir -p "$LOCKS"
log="$1"; shift
busy() { [[ -e "$LOCKS/drive" ]] || [[ -n "$(ls "$LOCKS" 2>/dev/null | grep '^unit-')" ]]; }
slot=""
while [[ -z "$slot" ]]; do
  if busy; then sleep 20; continue; fi
  if mkdir "$LOCKS/heavy.1" 2>/dev/null; then slot="$LOCKS/heavy.1"
  elif mkdir "$LOCKS/heavy.2" 2>/dev/null; then slot="$LOCKS/heavy.2"
  else sleep 15; continue; fi
  if busy; then rmdir "$slot"; slot=""; sleep 20; fi
done
trap 'rmdir "$slot" 2>/dev/null' EXIT INT TERM
echo "heavy.sh: slot $slot, started $(date '+%H:%M:%S')" > "$log"
"$@" >> "$log" 2>&1
rc=$?
echo "heavy.sh: exit $rc at $(date '+%H:%M:%S')" >> "$log"
echo $rc > "$log.exit"
exit $rc
