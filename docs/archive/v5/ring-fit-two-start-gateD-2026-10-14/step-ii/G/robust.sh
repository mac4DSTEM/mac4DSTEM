#!/bin/zsh
# usage: robust.sh — the ten tail plants x head,a x PERTURB 0,1e-9,1e-6,1e-3; one ROW per run, tagged
G=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad/lanes/G
# size R eps theta noise seed (tail 0.8)
plants=("192 65 0.01 112.5 0.10 1" "192 65 0.01 112.5 0.10 5" "192 65 0.01 20 0.10 2" "192 65 0.01 20 0.10 4" "192 70 0.01 20 0.15 8"
        "192 70 0.03 112.5 0.10 0" "192 70 0.03 112.5 0.15 4" "192 70 0.03 20 0.10 0" "192 70 0.03 20 0.10 5" "192 70 0.03 20 0.10 8")
for pl in "${plants[@]}"; do
  set -- ${=pl}
  for v in head a; do
    for pt in 0 1e-9 1e-6 1e-3; do
      echo -n "PERTURB=$pt $v "
      PERTURB=$pt $G/bin/search-$v one $1 $2 $3 $4 0 $5 $6 0.8
    done
  done
done
