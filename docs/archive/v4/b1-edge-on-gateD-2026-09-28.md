# B1 — the θ′ edge-on speckle, Gate D (2026-09-28): diagnosed, no fix shipped

The symptom: T4's first scored run (Thronsen A, stride 3, known-variants, `--or`, floor 0.15 %, guard k = 1) failed one
metric, 7 spurious θ′ edge-on objects against the published limit of 5 (`t4-first-scored-run-2026-09-28.md`). Gate D
because a fix would move a scientific number. No `mac4DSTEM/` code changed; the probe gained `--position-detail`
(`tools/phase-map-probe`, diagnostic). Commands (the probe's log does not echo them):

```
tools/thronsen-dataset/run.sh probe --rule known-variants --or --min-relative 0.0015 --min-intensity 0 \
  [--specific-guard 2] --object-table --dump-labels labels-kN.json \
  --position-detail "6,91;6,92;8,91;10,103;22,10;46,126;100,54;151,57"
python3 tools/cloud-analysis/t4_score.py labels-kN.json References/thronsen-datasetA/truth_stride3.json
```

Logs (session scratchpad): `probe-b1.log` (first read, without `--object-table`), `probe-k1.log`, `probe-k2.log`,
`t4-k1.log`, `t4-k2.log`; the diagnosis, refutation criteria and predictions in `predictions.md`, each run's outcome
appended after it. Independent refuter the same day (`b1/refuter/`), its corrections applied below.

**Known before:** at 0.1 % without the guard, 53 T1 → edge-on positions won by edge-on's dense 46-vector entry on mean
distance, `matchedCount` 0 for 39, 52 of 53 within 2 px of another truth class (precipitate-overnight §Step 2); the
guard (≥ 1 edge-on-specific reflection) removed most of them.

## The 7 objects are two populations

Located with the scorer's own functions (refuter: identical):

| Group | Positions | Specific reflections | Margin over the T1 runner-up | Specific hits vs the brightest non-central peak |
|---|---|---|---|---|
| In truth T1 (4 objects) | (6,91) (6,92) (8,91) (22,10) (46,126) | 1 each | 0.025, 0.014, 0.0075, 0.0022, 0.0095 | 0.004–0.011 |
| In truth Al (3 single positions) | (10,103) at a T1 border, (100,54), (151,57) | 4, 2, 2 | 0.031, 0.057, 0.025 | 0.008–0.017 |

Correct edge-on calls (398): specific count 1:11 2:26 3:37 4:45 5:53 6+:226; margin p10 0.0217, p50 0.0474. The
relative intensity is not in the detection floor's units (the floor is relative to the brightest peak including the
direct beam).

- **D1 as written was partly refuted.** It said one weak specific reflection and a thin margin for all of them. (a) ≥ 6 of
  8 with one specific reflection: 5 of 8. (b) correct calls' median ≥ 3: held. (c) all margins below the correct p10:
  4 of 8. D1 holds for the T1 group (4 of 5 margins below p10). The Al group's margins sit inside the correct calls'
  range.
- **The Al group is spurious by the scorer's definition, not shown to be false.** (100,54) and (151,57) lie 2.2 stride-px
  along sampled truth edge-on needles; 38 of the truth's 74 edge-on objects are single positions at stride 3, and 50 of
  the 55 Al → edge-on positions are within 1 px of truth edge-on. The full-resolution truth, not on this disk, would
  settle it. The T1 group sits in disturbed patches (mixed labels at (6–8, 89–92); a truth "disagreement" pixel 3.2 px
  from (22,10); a T1/face-on/Al junction at (46,126)).

## The discriminating experiment: the guard at k = 2 (measurement only)

The k = 1 rerun reproduced the T4 run's label arrays exactly (`baseline`, `guarded`, width, height; the JSON's key order
differs, so the files are not byte-identical).

| Prediction | Outcome |
|---|---|
| P1 edge-on raw spurious 7 → 3 | **held** (3; the Al group stays) |
| P2 ≤ 11 of 398 correct edge-on lost; area ratio 1.07–1.12, within the limit | count **held** (exactly 11); area ratio **missed**, 1.024 (the prediction left out 21 truth-Al boundary edge-on calls that k = 2 also drops) |
| P3 other classes move, size not predicted | per-position error 1.31 → **1.93 %** (outside the paper's 0.96–1.75 % band); T1 **FAILS** split 4 (≤ 2), count ratio 1.118, area ratio 0.934 |

All 264 changed positions go to Al: 207 T1 (201 of them correct T1 calls), 38 edge-on, 19 face-on. A winner that fails the
guard becomes matrix by design (`classifyKnownVariants` step e), not its runner-up. **A global k = 2 is rejected.** (The
scorer's "k = 1" heading on `t4-k2.log` is a hard-coded string; its "unguarded" rows equal the guarded ones because the
dumped baseline already carries the shipped guard.)

## Post hoc, not findings

- **Edge-on-only k = 2 (refuter's reconstruction).** The k = 1 map with only k = 2's edge-on → Al changes applied is exact,
  since the guard runs per position after the argmin. It passes every T4 metric at 1.28 %, edge-on area ratio 1.024,
  one edge-on object "vanished". Chosen after seeing the failure.
- **Intensity.** All 8 positions rest on specific hits at ≤ 1.7 % of their brightest non-central peak, against 19 of 398
  correct edge-on calls whose strongest specific hit is below 2 %. `probe-b1.log` has no such line; the probe was extended
  after it was read. A 0.02 cut sits just above the 8's maximum: a threshold fitted to 8 points.

Either becomes a registered experiment only with an independently set threshold (e.g. in the floor's own units), a
spatial-halves holdout as for k on 09-23, a physical reason for treating edge-on differently (T1's entry is as dense:
48 vectors, chance match 1.3 % vs 1.2 %), and the threshold rule's second dataset before any default moves (CLAUDE.md).

## Where it leaves B1

Diagnosed, no fix. The metric stays 7 against 5. Next, in order: register the edge-on-only guard with a spatial holdout;
check the Al group against the full-resolution truth when it is on disk. Phase mapping stays badged unvalidated.
