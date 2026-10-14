#!/bin/zsh
# usage: gate-copy.sh <name> <repo-relative file>...
# Builds $SP/gates/<name>/mac4DSTEM = git archive HEAD + the listed working-tree files, References symlinked.
# Prints the copy's path. The directory must be named mac4DSTEM (package name).
set -euo pipefail
REPO=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
name="$1"; shift
dest="$SP/gates/$name/mac4DSTEM"
rm -rf "$SP/gates/$name"; mkdir -p "$dest" "$SP/gates/$name/tmp"
git -C "$REPO" archive HEAD | tar -x -C "$dest"
for f in "$@"; do
  if [[ -e "$REPO/$f" ]]; then mkdir -p "$dest/$(dirname "$f")"; cp "$REPO/$f" "$dest/$f"
  else rm -f "$dest/$f"; fi
done
ln -s "$REPO/References" "$dest/References"
echo "$dest"
