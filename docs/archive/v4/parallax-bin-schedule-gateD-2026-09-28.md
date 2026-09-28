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

## Outcome, same day

- **P1 held** (`p1-reference-only.log`). With only `reference.py` corrected to parallax.py's lines,
  the harness fails: "default coarse-to-fine bin schedule differs" (exit 133). The diagnosis
  stands.
- **P2 held** (`p2-fixed.log`, exit 0). The port's schedule is **[4, 2, 1, 1]**, and every leg
  passes, including a second factor-8 pass at bin 1 (peak 0.0026, cumulative 3.1e-4, BF 7.5e-6
  against the reference). No tolerance was changed.
- **P3 held** (the reference's own output). Level 4 against level 3: total shifts differ by up to
  **1.75e-3 px**, and the aligned BF by 3.8e-5. The repeated pass is not a no-op. The change is
  small on this fixture; nothing is claimed about real data.
- No unit test pinned the short schedule. The two that build `[4, 2, 1]` results construct their
  own schedule and do not call the default.

## Independent refuter (Sonnet), same day

**NOT REFUTED.** I checked the handback: both files `cmp`-identical, no processes left.
- **The transcription is exact.** It matches parallax.py:1141 and 1257-1281 for diameters 1, 2, 3,
  4, 5, 8, 9 and 17, and for a non-default minimum bin. `ceil(log(x)/log 2)` and `ceil(log2 x)`
  agree for every minimum 1–8 and diameter 1–2 050. The diameter is symmetric in the two axes.
- **No persistence hazard.** Nothing reads a saved `ParallaxAlignmentResult` back in. The schedule is
  computed fresh in every process, so an alignment made before today cannot be rejected on reopen.
  The UI shows the schedule's length dynamically.
- **Mutations, all red** ("schedule differs"): no repeat; the first bin repeated instead of the last;
  the repeat only above a diameter threshold (`refuter-mut*.log`).
- **Adjacent and already labelled:** `ParallaxAlignmentOptions.upsampleFactor` defaults to 1 against
  py4DSTEM's 8. The interactive path sets 8 explicitly, and the code says so. This change does not
  touch it.
