#!/bin/zsh
# builds bin/rf2-{head,a,b,ab} from src/main.swift via the harness build.sh (run THROUGH heavy.sh)
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
L=$SP/lanes/RF2
for v in head a b ab; do
  echo "building $v"; $SP/harness/build.sh $L/bin/rf2-$v $L/src/main.swift $v || exit 1
done
echo built_all
