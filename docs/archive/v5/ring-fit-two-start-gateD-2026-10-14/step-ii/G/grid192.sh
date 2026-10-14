#!/bin/zsh
# usage: grid192.sh <variants...> — runs the 192 px grid (720 plants) for each variant in 3 parts in parallel
G=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/G
pids=()
for v in "$@"; do
  for p in 0 1 2; do
    $G/bin/search-$v grid 192 60,65,70 0.01,0.03 20,112.5 0.05,0.10,0.15 0.4,0.8 0 10 $p 3 > $G/logs/grid192-$v-p$p.log 2>&1 &
    pids+=($!)
  done
done
rc=0
for p in $pids; do wait $p || rc=$?; done
exit $rc
