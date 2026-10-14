#!/bin/zsh
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
for v in "$@"; do
  $SP/harness/build.sh $SP/lanes/G/bin/search-$v $SP/lanes/G/search/main.swift $v || exit $?
done
