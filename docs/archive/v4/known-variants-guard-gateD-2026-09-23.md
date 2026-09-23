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

Logs (session scratchpad, not retained): the pre-change runs `pre-e2..e5.log` and the post-change
runs `post-e1k1-{0.001,0.0015,0.002}`, `post-e1k0-0.0015`, `post-e2k{0,1}`, `post-e3k1`,
`post-e4k{0,1}` and `post-e5.log`, each exit 0 on its own line (`pre-exits.txt`,
`post-exits.txt`). Label maps are compared position for position by the committed
`tools/thronsen-dataset/compare_labels.py <post>.json <pre>.json:guarded …`: exit 0, all seven
pairs below IDENTICAL (`compare-labels.log`). Anti-vacuity: guard off against guard on at 0.15 %
differs at 75 positions (exit 1, `antivac.log`), so the comparison can fail. The probe runs are
`tools/thronsen-dataset/run.sh probe --rule known-variants --or --min-relative F --min-intensity 0
--al-precipitate-detail --object-table --dump-labels OUT [--specific-guard 0] [--scale-to-detector]`.

| experiment | prediction | result |
|---|---|---|
| E1 k = 1 at 0.1 / 0.15 / 0.2 % | exactly 423 / 383 / 1168, maps identical to the inline guard | **identical, 29 241 of 29 241 at each floor** (423 / 383 / 1168) — held |
| E1 k = 0 at 0.15 % | identical to the old baseline (424) | **identical** — held |
| E2 default floor 0.5 %, k = 0 → 1 | guard lowers error, by ≤ 0.3 points | **REFUTED in direction: 3333 → 3338 (11.40 → 11.42 %)**, 8 Al false calls fixed against 13 correct calls lost. Both maps are identical to the inline guard / old baseline. |
| E3 0.15 %, one-pixel radius 0.01904 Å⁻¹ | guard lowers error, to 1.2–1.6 % | 426 → **384 = 1.31 %**, identical to the inline guard — held |
| E4 demo cube, known-variants, k = 0 → 1 | 0 correct precipitate calls lost | held: end-on and needle recall stay 100 %. **Not predicted:** grain C (Al [111], 2250 positions) moves from β″[001] to matrix, and 50 of grain A's 100 false β″ calls go to matrix. Grain B (Al [011], 2250) stays labelled β″: this rule has no matrix challenge. |
| E5 `.search` on the demo cube | identical | identical on every matching and truth line. Only the order of tied, symmetry-equivalent axes in the zone-axis print differs, and it also differs between two runs of unchanged code (pre-e4 vs post-e4k0): pre-existing nondeterminism, recorded in `open-items.md` |

Break-first, unit (`PhaseVectorMatchingTests`, scratch DerivedData):

| mutation | went red |
|---|---|
| guard disabled | G1, G2 |
| shared-with-matrix filter removed | G1 |
| `<` → `<=` | G2 (and the unique-hit test) |
| guard applied to refusals too | G3 |
| default 0 | G4 |

The existing cutoff test now pins k = 0: its survivors sit outside the pair radius by
construction.

**What this says:** at the app's shipped settings, the Core guard is exactly the guard that was
measured. **It helps at low detection floors and costs slightly at the shipped 0.5 %** (−5
positions of 29 241, within noise but the wrong sign). The owner decided on-by-default knowing
the 0.15 % result; this record adds the 0.5 % result. The demo cube is a second dataset, and
there the guard lost nothing and removed a whole mislabelled grain.

## Independent review (Gate B, 2026-09-23 night)

A separate agent (Sonnet) that did not write the change was briefed to refute it. It was given
the logs, label dumps and harness rather than the diff. It worked from pristine byte copies,
never ran git restore, and at hand-back all 16 files were `cmp`-identical.

- **Byte-equality not vacuous:** NOT REFUTED. It verified with its own SHA-256 script, not
  `compare_e1.py`. For k = 0 the dump's `baseline` and `guarded` keys differ, which rules out
  the post "baseline" secretly being the inline guard.
- **Divergence between the probe's vectors / matrix entry and the app path:** REFUTED as a risk.
  `PhaseVectorMatcher.map` hands the same `vectors` and `matrixEntry` to scoring and the guard;
  the second computation only ever existed in the probe.
- **Numbers in doc comments:** every one spot-checked against the logs; none unsupported.
- **Report / pipeline:** no wrong number found (edge, minimum size, report-time calibration,
  pixel-sorted physical columns).
- **Three mutations survived the tests.** Each now has a test, broken first (`nmutations.txt`):
  - the shared filter at the pair radius instead of the matrix tolerance → G5
    `testKnownVariantsGuardJudgesSharedAtTheMatrixTolerance`, red on that mutation;
  - the guard evaluated on the first entry in library order instead of the winner → G6
    `testKnownVariantsGuardJudgesTheWinnerNotTheFirstEntry`, red;
  - the stale-result token check deleted →
    `PhaseMapObjectsWiringTests.testStaleBackgroundResultIsDropped`, red.

The refuter's full report was a session file, not retained; its findings are this section.
