#!/usr/bin/env python3
"""Compare a real-data-acceptance report against the pinned golden values.

Matching is BY FILENAME, not by position. The previous version asserted
`len(actual) == len(expected)` and then `zip`ped the two lists, which had two
defects: it pinned the gate to an exact directory listing (adding any dataset
to References/training_dataset/ turned the gate red — 2026-08-31, `report count
8, expected 4`), and a file sorting before a pinned one could line the lists up
wrongly and compare mismatched pairs.

WHAT THE LENGTH ASSERT BOUGHT, and what became of each part. Enumerated by a
Gate B reviewer on 2026-08-31, because the first version of this docstring
claimed it bought only the first item:

  kept      no pinned dataset missing from the report (the check below)
  kept      expected.json is not empty (the guard below)
  improved  correct pairing — the old positional zip could get this WRONG
  improved  duplicate filenames now refuse instead of silently last-wins
  DROPPED   no extra unknown dataset. Deliberate; this is the widening.
  DROPPED   every measured dataset subject to the 15 s budget. main.swift
            records elapsedSeconds but never gates on it, so that budget is now
            pinned-datasets-only. Recorded in docs/open-items.md as an owner
            decision rather than silently accepted.
  DROPPED   expected.json as an exhaustive manifest of the machine's data. The
            UNPINNED line below is the only signal that coverage has decayed.

SCOPE OF THE MISSING-DATASET GUARD — do not overstate it, as this docstring
once did. It protects a pinned cube from vanishing out of a report that
compare.py actually sees. It does NOT cover an empty dataset directory: run.sh
exits 0 with a SKIP before invoking this file at all. That residual is an open
item, not something this file can fix.
"""
import json
import math
import sys

expected = json.load(open(sys.argv[1]))
report_text = open(sys.argv[2]).read()
actual, _ = json.JSONDecoder().raw_decode(report_text)

# Every field the loop reads, so a malformed entry is refused by name instead of
# reaching a KeyError. A traceback is not a refusal: it carries no FAIL: line,
# and comparator-test.sh scores one as a defect.
REQUIRED = (
    "file", "datasetPath", "shape", "dtype", "finitePatternFraction",
    "diskProbeRadiusPixels", "diskSampleCandidateCounts",
    "diskSampleAfterAbsoluteCounts", "diskSampleAfterRelativeCounts",
    "diskSampleAfterSpacingCounts", "diskSamplePeakCounts",
    "virtualImageMinimum", "virtualImageMaximum", "virtualImageMean",
    "virtualImageChecksum", "elapsedSeconds",
)
EXACT_FIELDS = ("datasetPath", "shape", "dtype")
COUNT_FIELDS = (
    "diskSampleCandidateCounts", "diskSampleAfterAbsoluteCounts",
    "diskSampleAfterRelativeCounts", "diskSampleAfterSpacingCounts",
    "diskSamplePeakCounts",
)
IMAGE_FIELDS = (
    "virtualImageMinimum", "virtualImageMaximum", "virtualImageMean",
    "virtualImageChecksum",
)


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def by_name(entries, label, need_all_fields):
    """Index entries on `file`, refusing malformed input and duplicates."""
    if not isinstance(entries, list):
        fail(f"{label} is not a JSON list (got {type(entries).__name__})")
    index = {}
    for position, entry in enumerate(entries):
        if not isinstance(entry, dict):
            fail(f"{label} entry {position} is not an object (got {type(entry).__name__})")
        if "file" not in entry:
            fail(f"{label} entry {position} has no 'file' key")
        name = entry["file"]
        if not isinstance(name, str):
            fail(f"{label} entry {position} has a non-string 'file' ({type(name).__name__})")
        if name in index:
            fail(f"{label} lists {name!r} more than once")
        if need_all_fields:
            for key in REQUIRED:
                if key not in entry:
                    fail(f"{label} entry {name!r} has no {key!r} key")
        index[name] = entry
    return index


if not expected:
    fail("expected.json pins no datasets — the gate would check nothing")
# SUBSUMED for correctness — kept for the message, and this comment has now been
# wrong twice, so here is the whole history rather than a third confident claim.
# (1) It was first documented as uncoverable. (2) A Gate B reviewer refuted that:
# a report that is valid JSON but not a list (`null`, `0`, `false`) was falsy
# here and crashed by_name otherwise, so the case did isolate it. (3) Fixing that
# crash with by_name's isinstance check re-subsumed this line: a non-list is now
# refused there, and `[]` is refused by the missing-dataset check. Verified by
# deleting it — every falsy report still refuses cleanly, which is exactly why
# comparator-test's sweep no longer kills this mutation.
# It stays because on `[]` it says "the report is empty" where the missing check
# would say "1 pinned dataset(s) absent" — clearer about what went wrong. A
# green suite is NOT evidence this line executes.
if not actual:
    fail("the report is empty — no file produced a measurement")

want_by_name = by_name(expected, "expected.json", need_all_fields=False)
got_by_name = by_name(actual, "the report", need_all_fields=True)

# The disappearance guard the length assert was standing in for.
missing = [name for name in want_by_name if name not in got_by_name]
if missing:
    fail(
        f"{len(missing)} pinned dataset(s) absent from the report: "
        + ", ".join(sorted(missing))
    )

for name, want in want_by_name.items():
    got = got_by_name[name]
    # `file` is deliberately NOT compared. Both sides are fetched by `name`, so
    # got["file"] == name == want["file"] can never differ — it was a live check
    # under the old positional zip and became tautological here. Two reviewers
    # flagged it independently as an assertion that reads live and is not. A
    # renamed file is caught by the missing-dataset check above.
    for key in EXACT_FIELDS:
        if got[key] != want[key]:
            fail(f"{name} {key}: {got[key]!r} != {want[key]!r}")
    # `not (x >= t)` rather than `x < t` so a NaN refuses instead of sailing
    # through — NaN compares False against everything. main.swift's own guard is
    # already NaN-safe; this stops the comparator being the weaker of the two.
    if not (got["finitePatternFraction"] >= 0.999):
        fail(f"{name} finite fraction {got['finitePatternFraction']}")
    for key in COUNT_FIELDS:
        # Order matters. These are per-sampled-position (main.swift samples a
        # corner, the centre, the opposite corner), so a permutation means disk
        # results were reassigned between scan positions. Compared with `!=` on
        # the list itself, never as a sorted/set/sum reduction — comparator-test
        # pins that with an explicit permutation case.
        if got[key] != want[key]:
            fail(f"{name} {key}: {got[key]} != {want[key]}")
    if not math.isclose(
        got["diskProbeRadiusPixels"], want["diskProbeRadiusPixels"],
        rel_tol=2e-6, abs_tol=1e-4
    ):
        fail(
            f"{name} diskProbeRadiusPixels: "
            f"{got['diskProbeRadiusPixels']} != {want['diskProbeRadiusPixels']}"
        )
    for key in IMAGE_FIELDS:
        if not math.isclose(got[key], want[key], rel_tol=2e-6, abs_tol=1e-3):
            fail(f"{name} {key}: {got[key]} != {want[key]}")
    if not (got["elapsedSeconds"] <= 15):
        fail(f"{name} exceeded 15 s acceptance budget: {got['elapsedSeconds']} s")
    print(f"PASS: {name} golden and {got['elapsedSeconds']:.2f} s budget")

# Named, not silent: an unpinned dataset is real data on this machine that no
# golden values cover, and it can never fail the gate, so this line is the ONLY
# signal it exists. comparator-test.sh asserts the line is emitted — until
# 2026-08-31 deleting it altogether left the suite green.
unpinned = sorted(name for name in got_by_name if name not in want_by_name)
if unpinned:
    print(
        f"UNPINNED: {len(unpinned)} dataset(s) measured but not covered by "
        f"expected.json — {', '.join(unpinned)}"
    )
