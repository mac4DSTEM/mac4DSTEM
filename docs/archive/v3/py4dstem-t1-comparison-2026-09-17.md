# py4DSTEM's phase method on T1, head-to-head — measured 2026-09-17

**Question.** mac4DSTEM leaves 252 T1 positions "not indexed" (a real Friedel pair
of the {200} family, ~0.467 Å⁻¹, rejected because per-peak centroid noise puts
`|u+v|` ≈ 0.027 just past the 0.02 pair radius — see `docs/open-items.md`, T1 entry).
What would py4DSTEM's own phase method do with the same data?

**Reproduce.** Detection held fixed — the SAME calibrated peaks mac4DSTEM detected,
exported by `tools/phase-map-probe --dump-peaks`, so only the INDEXING method varies:

```
tools/phase-map-probe/run.sh <thronsen cube> 2 0.01904 --thronsen <truth> --reach 0.68 \
    --dump-peaks peaks.json
conda run -n py4dstem python docs/archive/v3/py4dstem-t1-comparison-2026-09-17.py peaks.json
```

py4DSTEM 0.14.19 (the pinned vendored copy), Al (fcc a=4.0495) + T1 (Al₂CuLi P6/mmm,
Thronsen Table 2) crystals, ACOM `match_orientations` + `CrystalPhase.quantify_phase`
(defaults: `corr_kernel_size=0.04`, `power_intensity=0.25`), 1052 positions.
Companion scripts: `py4dstem-t1-pairing-2026-09-17.py` (transparent peak-count),
`py4dstem-t1-alone-residual-2026-09-17.py` (single-phase residuals).

## Result — py4DSTEM labels every T1 position Al (matrix)

| group (mac4DSTEM verdict) | n | py4DSTEM Al-dominant | T1-dominant | median T1 fraction |
|---|---|---|---|---|
| T1 not-indexed | 252 | **100 %** | 0 % | 0.000 |
| T1 indexed | 250 | **100 %** | 0 % | 0.000 |
| Al | 300 | 100 % | 0 % | 0.000 |

T1 is never the winning phase — including the 250 positions mac4DSTEM correctly
indexes as T1.

## Verified real, not a setup artifact

- **T1 reference correct:** `generate_diffraction_pattern([0,-4,1])` peaks at 0.467,
  0.4933, 0.7001 … match mac4DSTEM's library.
- **ACOM found ~the right T1 orientation** (beam ≈ the [0,-4,1] direction, corr ≈ 7).
- **Peak-count pairing** (no NNLS, known zone axes, within 0.04): at T1 positions
  **T1 explains every peak (6/6, 7/7, 8/8); Al explains only 4.**
- **py4DSTEM's own residual** nonetheless prefers Al: single-phase median residual
  Al-alone **7.4** vs T1-alone **9.5** at T1 positions.

## Mechanism

A T1 precipitate sits *inside* the Al matrix, so its pattern is 4 strong Al {200}
peaks (I ≈ 300) + 2 weak T1 {200} peaks (I ≈ 20). py4DSTEM (a) never removes the
matrix and (b) scores by **intensity-weighted** correlation/NNLS. The Al reflections
carry ~97 % of the intensity, so Al wins the residual and the weak T1 signature that
*is* the precipitate is drowned out. Peak-**count** prefers T1; intensity-weighted
**correlation** prefers Al — the two metrics disagree, and py4DSTEM uses the latter.
This is the same wrong-phase failure measured independently in
[`phase-discrimination-2026-09-11.md`](phase-discrimination-2026-09-11.md) (Gold
outscores Al on a pure-Al pattern), and why Thronsen et al. ranked template matching
**worst** of their four methods.

## Consequence

py4DSTEM's standard `CrystalPhase`/ACOM path returns a confident **mislabel** (Al) where
mac4DSTEM abstains ("not indexed"). It **validates mac4DSTEM's core design**: remove the
matrix first and score on **peak positions (geometry)**, not intensity, so the two weak
precipitate peaks count as much as the strong matrix ones (`PhaseVectorMatching.swift`
header). **Caveat:** this is py4DSTEM's *default* multi-phase path; matrix masking
(not built into `CrystalPhase`), a lower `power_intensity`, or its NMF route (Thronsen's
best classical method) could do better and were not tested.
