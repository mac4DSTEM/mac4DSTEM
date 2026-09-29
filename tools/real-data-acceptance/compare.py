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
compare.py actually sees. An empty dataset directory never reaches this file:
run.sh refuses it (exit 1, "FAIL: no ... .h5 files") before building anything,
and compare-selftest.sh pins that.

EVERY MISMATCH IS NAMED (S19, 2026-09-30). `fail()` used to raise at the first
mismatch, so a red gate named one symptom and hid the rest — on `ba6360d` the
first line said "count" and the real defect was elsewhere. `fail()` now records
and prints each mismatch and the script exits 1 at the end, after all of them.
Only a report that cannot be indexed at all (not a list, empty) stops early.

POSITIONS, NOT ONLY COUNTS (S19, 2026-09-30). The count fields cannot see a peak
that moved: on `ba6360d` one peak moved ~26 px, the counts did not change, and the
gate stayed green. An entry that pins `diskSamplePeakPositions` (the surviving
peaks' (x, y) in detector pixels, per sampled scan position) is matched by
nearest neighbour in BOTH directions within POSITION_TOLERANCE_PX. The pin is
today's behaviour, generated from the harness's own report, not a py4DSTEM
comparison. An entry without the key is not position-checked (the synthetic
fixture of tools/comparator-test carries none); compare-selftest.sh asserts the
shipped expected.json pins every dataset, so the pin cannot be dropped silently.
"""
import json
import math
import sys

# Peak positions are pinned rounded to 0.01 px; 0.05 px is five times that and
# far below the ~26 px movement the count fields missed. A threshold is a
# property of the datasets it was measured on (CLAUDE.md): measured 2026-09-30 on
# this Mac, three harness runs from two builds reproduced every pinned position
# bit-for-bit (max nearest-neighbour distance 0 px); 0.05 px absorbs one .xx5
# rounding flip on another GPU, not an offset.
POSITION_TOLERANCE_PX = 0.05
MAX_LISTED_PEAKS = 6

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


FAILURES = []


def fail(message):
    """Record and print one mismatch; the run continues and finish() exits 1."""
    FAILURES.append(message)
    print(f"FAIL: {message}", file=sys.stderr, flush=True)


def finish():
    if FAILURES:
        print(
            f"RESULT: {len(FAILURES)} mismatch(es) — every one is listed above as a FAIL: line",
            file=sys.stderr, flush=True,
        )
        raise SystemExit(1)


def fatal(message):
    """A mismatch after which nothing further can be compared."""
    fail(message)
    finish()


def by_name(entries, label, need_all_fields):
    """Index entries on `file`, naming malformed input and duplicates.

    Returns (index, malformed): `malformed` holds the names of entries that were
    present but unusable, so they are not ALSO reported as absent."""
    if not isinstance(entries, list):
        fatal(f"{label} is not a JSON list (got {type(entries).__name__})")
    index = {}
    malformed = set()
    for position, entry in enumerate(entries):
        if not isinstance(entry, dict):
            fail(f"{label} entry {position} is not an object (got {type(entry).__name__})")
            continue
        if "file" not in entry:
            fail(f"{label} entry {position} has no 'file' key")
            continue
        name = entry["file"]
        if not isinstance(name, str):
            fail(f"{label} entry {position} has a non-string 'file' ({type(name).__name__})")
            continue
        if name in index or name in malformed:
            fail(f"{label} lists {name!r} more than once")
            continue
        if need_all_fields:
            absent = [key for key in REQUIRED if key not in entry]
            for key in absent:
                fail(f"{label} entry {name!r} has no {key!r} key")
            if absent:
                malformed.add(name)
                continue
        index[name] = entry
    return index, malformed


def peak_list(name, label, value):
    """A list of finite [x, y] pairs, or None after naming what is wrong."""
    if not isinstance(value, list):
        fail(f"{name} {label}: peaks are not a list (got {type(value).__name__})")
        return None
    points = []
    for k, point in enumerate(value):
        if (not isinstance(point, list) or len(point) != 2
                or not all(isinstance(c, (int, float)) and not isinstance(c, bool)
                           and math.isfinite(c) for c in point)):
            fail(f"{name} {label}: peak {k + 1} is not a finite [x, y] pair: {point!r}")
            return None
        points.append((float(point[0]), float(point[1])))
    return points


def unmatched(points, others):
    """Points with no point of `others` within the tolerance (`d <= tol`, so
    a distance that is not a number can never count as a match)."""
    return [
        p for p in points
        if not any(math.hypot(p[0] - q[0], p[1] - q[1]) <= POSITION_TOLERANCE_PX for q in others)
    ]


def listed(points):
    shown = ", ".join(f"({x:.2f}, {y:.2f})" for x, y in points[:MAX_LISTED_PEAKS])
    return shown + (f" and {len(points) - MAX_LISTED_PEAKS} more" if len(points) > MAX_LISTED_PEAKS else "")


def check_positions(name, want, got):
    """Nearest-neighbour match of the surviving peaks, both ways, per sampled
    scan position; one mismatch per position, naming the peaks left over."""
    key = "diskSamplePeakPositions"
    if "diskSampleScanPositions" in want and got.get("diskSampleScanPositions") != want["diskSampleScanPositions"]:
        fail(f"{name} diskSampleScanPositions: {got.get('diskSampleScanPositions')} != {want['diskSampleScanPositions']}")
    if key not in got:
        fail(f"{name} {key}: the report carries none, but expected.json pins them")
        return
    want_sets, got_sets = want[key], got[key]
    if not isinstance(want_sets, list) or not isinstance(got_sets, list):
        fail(f"{name} {key}: not a list per sampled position")
        return
    if len(want_sets) != len(got_sets):
        fail(f"{name} {key}: {len(got_sets)} sampled positions, pinned {len(want_sets)}")
        return
    scan = want.get("diskSampleScanPositions") or got.get("diskSampleScanPositions")
    for i, (w_raw, g_raw) in enumerate(zip(want_sets, got_sets)):
        where = (f"scan position (ry={scan[i][0]}, rx={scan[i][1]})"
                 if isinstance(scan, list) and i < len(scan) and len(scan[i]) == 2
                 else f"sampled position {i}")
        w = peak_list(name, where + " (pinned)", w_raw)
        g = peak_list(name, where, g_raw)
        if w is None or g is None:
            continue
        lost, extra = unmatched(w, g), unmatched(g, w)
        if lost or extra:
            parts = []
            if lost:
                parts.append(f"{len(lost)} pinned peak(s) with no reported peak within "
                             f"{POSITION_TOLERANCE_PX} px: {listed(lost)}")
            if extra:
                parts.append(f"{len(extra)} reported peak(s) matching no pinned peak: {listed(extra)}")
            fail(f"{name} {where}: " + "; ".join(parts))


if not expected:
    fatal("expected.json pins no datasets — the gate would check nothing")
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
    fatal("the report is empty — no file produced a measurement")

want_by_name, _ = by_name(expected, "expected.json", need_all_fields=False)
got_by_name, unusable = by_name(actual, "the report", need_all_fields=True)

# The disappearance guard the length assert was standing in for. A present but
# malformed entry was already named above; it is not also "absent".
missing = [name for name in want_by_name if name not in got_by_name and name not in unusable]
if missing:
    fail(
        f"{len(missing)} pinned dataset(s) absent from the report: "
        + ", ".join(sorted(missing))
    )

for name, want in want_by_name.items():
    if name not in got_by_name:
        continue  # absent or malformed: named above
    got = got_by_name[name]
    failures_before = len(FAILURES)
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
    if "diskSamplePeakPositions" in want:
        check_positions(name, want, got)
    if not (got["elapsedSeconds"] <= 15):
        fail(f"{name} exceeded 15 s acceptance budget: {got['elapsedSeconds']} s")
    if len(FAILURES) == failures_before:
        print(f"PASS: {name} golden and {got['elapsedSeconds']:.2f} s budget", flush=True)

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

finish()
