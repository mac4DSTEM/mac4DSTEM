# Parallax default bin schedule repeats the finest bin, as py4DSTEM's does — Gate D, 2026-09-28

The open item "Parallax default bin schedule runs the finest bin once; py4DSTEM's runs it twice"
(diagnosed 2026-09-17, fix owed; the detail is `archive/open-items-detail-2026-09-18.md`).

## Diagnosis (registered before any code change)

`ParallaxAligner.defaultBinSchedule` returns `2 ** arange(ceil(log2 min), ceil(log2 diameter))[::-1]`,
for example [4, 2, 1]. py4DSTEM's `parallax.py:1274-1281` builds the same list, then, because
`num_iter_at_min_bin` defaults to **2** (`:1141`), appends the last bin once more: [4, 2, 1, 1].
So every alignment that the app calls "complete" (`isComplete`) has run one refinement pass fewer
than py4DSTEM's. The harness hides this: `tools/parallax-alignment-test/reference.py:354-357`
computes the schedule without the repeat, so it agrees with the port by construction.

**Refuting observation:** if a reference built from py4DSTEM's own schedule logic still agreed
with the port, the diagnosis would be wrong.

**Change:** `defaultBinSchedule` gains `iterationsAtMinimumBin` (py4DSTEM's `num_iter_at_min_bin`,
default 2) and appends the repeats. The one-bin edge case (the detector diameter needs no
binning) keeps returning `[minimum]`. That is a `DEVIATION`: py4DSTEM's `bin_vals[-1]` raises
`IndexError` on the empty list there. The harness reference follows `parallax.py:1274-1281`
line for line.

## Predictions

- **P1 (the refuting check, run before the Swift fix):** with only the reference corrected, the
  harness FAILS on "default coarse-to-fine bin schedule differs": the port lacks the repeated
  final bin.
- **P2:** with the fix, the harness PASSES every leg, including the multilevel run through the
  repeated final level. The port's second pass at the finest bin matches numpy within the
  harness's existing tolerances, which are not changed.
- **P3 (anti-vacuity):** the repeated pass is not a no-op on the fixture. The harness's multilevel
  output shows the final level's shifts or aligned BF differing from the level before it.
- **P4:** the unit and scientific gates stay green. Any expectation that pinned the short schedule
  changes deliberately, and is named.

Not claimed: anything about real data. Parallax is unrunnable on the owner's 8 GB Mac and undriven
on real data (`open-items.md`).
