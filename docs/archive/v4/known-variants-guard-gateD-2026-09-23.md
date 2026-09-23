# Known-variants evidence guard — Gate D, 2026-09-23 night

**Owner decision (2026-09-23):** ship the known-variants evidence guard, k ≥ 1, **on by default**
for the `.knownVariants` rule. A position whose winning entry matches no phase-specific reflection
falls back to the matrix. The 0.5 % detection-floor default stays; 0.15 % stays the owner's
per-dataset setting. This moves a scientific number (phase-map labels), so **Gate D applies**.
Phase mapping stays badged unvalidated (`validation:"none"`).

## What is already known (read first)

- `archive/v3/precipitate-overnight-2026-09-23.md` step 1: the guard's definition, as
  computed inline in `tools/phase-map-probe/main.swift` from the survivors and the called entry.
  A matched reflection counts as "specific" when its reference `q` sits outside the matrix
  tolerance of every matrix reference. Sweep: k ≥ 1 → 423 = 1.45 % at the 0.1 % floor.
- The same record's independent refutation: reproduced to the digit, and leak-free (truth never
  enters). Held out on spatial halves, k = 1 was chosen 170 of 200 times. But it is a
  **(k, pair-radius) family, not parameter-free**: k ≥ 1 gives 2.18 % at 0.010 Å⁻¹ and 1.35 %
  at 0.015. It is one-directional (precipitate → Al only). It also relabels 40 already-wrong
  precipitate calls as Al, so precipitate → Al errors rise from 39 to 85.
- `archive/v4/detection-floor-sweep-2026-09-23.md`: at 0.15 %, k ≥ 1 → 383 = 1.31 %; at 0.2 %,
  1168 = 3.99 %.
- **The radius, checked here.** Thronsen mode runs the app's shipped `PhaseVectorSettings`:
  pair radius and matrix tolerance are both 0.020 Å⁻¹, the app's default. One pixel (0.01904 Å⁻¹
  on this data) applies only after the user runs "scale to detector"
  (`AppState.scalePhaseMatchingToDetector`). The guard therefore uses **the run's own pair
  radius and matrix tolerance**, whatever they are.

## Diagnosis (as a change, not a defect)

The unguarded known-variants rule accepts an argmin winner that matched no reflection its phase
does not share with Al. Those calls are 1 median specific reflection for the 407 false Al calls
against 7 for correct calls. Moving the probe's inline guard into
`PhaseVectorMatcher.classifyKnownVariants`, behind a new setting
`knownVariantsMinimumSpecificReflections` (default 1; 0 = off), reproduces the measured numbers
and changes nothing else.

## What would refute it

1. The Core guard at k = 1 **differs by even one position** from the probe's inline guarded
   labels at any floor (label maps compared byte for byte via `--dump-labels`).
2. With the guard off (k = 0), the maps differ from today's baseline.
3. Any `.search` result changes.
4. On the demo cube (the second dataset with a truth), the guard loses a correct precipitate call.

## Predictions, stated before any run

| experiment | prediction |
|---|---|
| E1 Thronsen, k = 1 at 0.1 / 0.15 / 0.2 % | exactly 423 / 383 / 1168; label maps byte-identical to the inline "guarded" maps |
| E1 Thronsen, k = 0 at the same floors | exactly 529 / 424 / 1189; byte-identical to the baseline maps |
| E2 Thronsen at the default 0.5 % floor, k = 0 vs 1 | guard lowers error; change ≤ 0.3 points (few Al false calls survive a high floor) |
| E3 Thronsen at 0.15 %, one-pixel radius 0.01904 Å⁻¹, k = 0 vs 1 | guard lowers error, to within 1.2–1.6 % |
| E4 demo cube, known-variants, k = 0 vs 1 | 0 of the planted precipitate positions' correct calls lost |
| E5 `.search` (unit test + demo cube truth mode) | identical |

## Result

*(Written after the runs.)*
