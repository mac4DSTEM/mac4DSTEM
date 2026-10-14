#!/usr/bin/env python3
"""PreToolUse hook (Bash): refuse long sleeps and sleep/poll loops.

Owner rule 2026-10-14: wait on events, not loops. Simple regexes, not a shell
parser; any internal error allows the command (exit 0).
"""
import json
import re
import sys

MSG = ("Refused by .claude/hooks/no-sleep-poll.py (owner rule 2026-10-14: wait on events, "
       "not loops): do not sleep or poll. Run the job with run_in_background and wait for "
       "its completion notification, or use the Monitor tool for a stream of events.")

# `sleep` as a command word: not part of a path or a longer word (/tmp/sleepy, asleep).
SLEEP = re.compile(r"(?<![\w/.\-])sleep(?=\s)([^;&|\n)]*)")
UNIT = {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}
LOOP = re.compile(r"(?<![\w/.\-])(while|until|for)\b[^\n]*?\bdo\b.*?(?<![\w/.\-])sleep(?=\s)", re.S)
WATCH = re.compile(r"(?<![\w/.\-])watch\s+(?:\S+\s+)*?-n\b")


def seconds(args):
    total = 0.0
    for tok in args.split():
        m = re.fullmatch(r"(\d+(?:\.\d+)?|\.\d+)([smhd]?)", tok)
        if m:
            total += float(m.group(1)) * UNIT[m.group(2)]
    return total


def refuse(cmd):
    if LOOP.search(cmd) or WATCH.search(cmd):
        return True
    return any(seconds(m.group(1)) >= 30 for m in SLEEP.finditer(cmd))


def main():
    try:
        cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command") or ""
        if refuse(cmd):
            print(MSG, file=sys.stderr)
            return 2
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
