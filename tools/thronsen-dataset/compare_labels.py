#!/usr/bin/env python3
"""Compare two label maps written by `tools/phase-map-probe --object-table
--dump-labels`, position for position.

usage: compare_labels.py A.json[:key] B.json[:key] [...more pairs]

`key` is `baseline` (default) or `guarded`. Prints IDENTICAL or the number of
differing positions for each pair, and exits 1 if any pair differs.

Used by the known-variants guard Gate D
(`docs/archive/v4/known-variants-guard-gateD-2026-09-23.md`): the Core guard's
map (post-change, key `baseline`) against the probe's inline guard measured
before the change (key `guarded`). As an anti-vacuity check, the same
comparison with the guard off must differ from the guarded map.
"""
import json
import sys


def load(spec):
    path, _, key = spec.partition(":")
    return json.load(open(path))[key or "baseline"]


def main(argv):
    if len(argv) < 3 or len(argv) % 2 == 0:
        print(__doc__)
        return 2
    differ = False
    for a, b in zip(argv[1::2], argv[2::2]):
        x, y = load(a), load(b)
        n = sum(1 for i, j in zip(x, y) if i != j) + abs(len(x) - len(y))
        print("%s vs %s: %s (n=%d)" % (a, b, "IDENTICAL" if n == 0 else "DIFFER at %d" % n, len(x)))
        differ |= n > 0
    return 1 if differ else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
