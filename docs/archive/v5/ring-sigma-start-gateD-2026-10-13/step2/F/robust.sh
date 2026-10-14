#!/bin/zsh
# usage: robust.sh <variant> <build: search3|search3-onone> plant-args...   (size R eps theta gap noise seed)
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
v=$1; bin=$2; shift 2
for pt in 0 1e-9 1e-6 1e-3; do
  echo -n "$bin-$v PERTURB=$pt "; PERTURB=$pt $SP/lanes/F/bin/$bin-$v one "$@" | sed 's/^ROW|id=[^|]*|size=[^|]*|R=[^|]*|eps=[^|]*|theta=[^|]*|gap=[^|]*|noise=[^|]*|seed=[^|]*|//'
done
