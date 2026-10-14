#!/bin/zsh
B=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/G/bin
for v in head a c; do
  echo "== $v dead (tail 0)"; $B/search-$v one 192 70 0.01 0 60 0.10 3
  echo "== $v drift (tail 0)"; $B/search-$v one 192 70 0.01 112.5 0 0.10 2
  echo "== $v tail 0.4 noise .10"; $B/search-$v one 192 70 0.01 112.5 0 0.10 2 0.4
done
