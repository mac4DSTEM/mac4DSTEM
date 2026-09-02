#!/bin/zsh
#
# sync-agents-md.sh — regenerate AGENTS.md from CLAUDE.md.
#
# AGENTS.md is the same document for a non-Claude-Code agent. It was maintained
# by hand until 2026-08-28 and drifted six sessions, ending up telling readers
# that `run-tests.sh all` had never been run end to end — a claim S19 had
# already refuted, contradicting README.md, CHANGELOG.md and CLAUDE.md at once.
# Three of its four hand-made substitutions were themselves wrong (a
# `.Codex/skills/` directory that does not exist, and the pre-move memory path
# CLAUDE.md had already corrected). So it is generated now, and the only
# differences from CLAUDE.md are the three below.
#
#   tools/sync-agents-md.sh           rewrite AGENTS.md
#   tools/sync-agents-md.sh --check   exit 1 if AGENTS.md is stale (closeout)
#
# The substitutions are ANCHORED: if CLAUDE.md's wording moves and an anchor
# stops matching, this script FAILS rather than emitting a half-substituted
# copy. A generator that silently degrades is worse than the hand-maintained
# file it replaced.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/CLAUDE.md"
TARGET="$ROOT/AGENTS.md"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

require() {
  grep -qF -- "$1" "$SOURCE" || {
    echo "sync-agents-md: anchor missing from CLAUDE.md — refusing to generate." >&2
    echo "  wanted: $1" >&2
    echo "  Update the substitution in tools/sync-agents-md.sh to match the new wording." >&2
    exit 1
  }
}

A1='# CLAUDE.md — start here'
A2='Skills: `/pickup` takes the next step from `docs/status.md`; `/diagnose` is'
A3='## Hard rules'
for anchor in "$A1" "$A2" "$A3"; do require "$anchor"; done

GENERATED="$(mktemp)"
trap 'rm -f "$GENERATED"' EXIT

python3 - "$SOURCE" "$GENERATED" <<'PY'
import re, sys
source, out = sys.argv[1], sys.argv[2]
text = open(source).read()

# 1. Title + a banner saying where to edit.
text = text.replace(
    "# CLAUDE.md — start here\n",
    "# AGENTS.md — start here\n\n"
    "> **Generated from `CLAUDE.md` by `tools/sync-agents-md.sh` — do not edit this\n"
    "> file.** Edit `CLAUDE.md`; the two passages that differ for a non-Claude-Code\n"
    "> agent are substituted by that script and listed in its header. Hand-maintained\n"
    "> until 2026-08-28, when it was found six sessions stale.\n",
    1)

# 2. The skills are Claude Code skills. A Codex (or any other) agent cannot
#    invoke them — telling it to type `/pickup` is a claim that does not hold.
old_skills = (
    "Skills: `/pickup` takes the next step from `docs/status.md`; `/diagnose` is\n"
    "Gate D; `/adversarial-review` is Gate B; `/track-b`; `/closeout`.\n")
new_skills = (
    "Skills in `.claude/skills/` — `pickup`, `diagnose` (Gate D), `adversarial-review`\n"
    "(Gate B), `track-b`, `closeout` — are **Claude Code skills and cannot be invoked\n"
    "from here**; read the matching `SKILL.md` as a document before doing that kind\n"
    "of work. Session memory lives in Claude Code's per-project memory directory and\n"
    "is not loaded here: do not assume a fact is remembered.\n")
assert old_skills in text, "skills passage anchor moved"
text = text.replace(old_skills, new_skills, 1)

open(out, "w").write(text)
PY

if (( CHECK )); then
  if cmp -s "$GENERATED" "$TARGET"; then
    echo "AGENTS.md is in sync with CLAUDE.md."
  else
    echo "AGENTS.md is STALE — run tools/sync-agents-md.sh (no arguments)." >&2
    diff "$TARGET" "$GENERATED" | head -40 >&2
    exit 1
  fi
else
  cp "$GENERATED" "$TARGET"
  echo "AGENTS.md regenerated from CLAUDE.md ($(wc -l < "$TARGET" | tr -d ' ') lines)."
fi
