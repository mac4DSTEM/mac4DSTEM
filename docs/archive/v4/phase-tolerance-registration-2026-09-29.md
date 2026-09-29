# Phase-match tolerance: physical budget or detector pixels — registration (2026-09-29, overnight D1)

YELLOW, measure only. **Question:** pair/matrix tolerances as a physical budget (fixed Å⁻¹, max(k·px, T), a fraction f
of the disk radius) or one detector pixel? Raw Al-Mg-Si: 97.0 % not indexed at 1 px, 86.4 % matrix at 4 px (`almgsi-raw-stride3-registration-2026-09-29.md`).

## The premise, corrected by reading

The app ships **0.02 / 0.02 / 0.015 Å⁻¹**, already physical (`PhaseVectorMatching.swift:57,71,150`). One pixel
(`scaledToDetector` `:288`) is offered only when the pair radius is < 1 px under search (`advice` `:274–283`;
`PhaseMappingSettings.swift:227–249`), so it only widens: the app runs **R0 = max(0.02 Å⁻¹, 1 px)**, as does
phase-map-probe's no-truth mode (`tools/phase-map-probe/main.swift:604–611`). The 97 % came from matrix-orientation-probe,
which scales unconditionally (`main.swift:535–545`; its "the app's rule is ONE detector pixel" is wrong). **In the app
the raw cube runs at 0.02 Å⁻¹ = 3.04 px, never measured** (read, not run). Rules tested: R0; R1 fixed T; R2 k px; R3 f ×
disk radius. A shortest-g rule equals R1 on four Al-matrix datasets, so it cannot be tested here.

## Datasets, grid, reproduction (exact, or nothing below it is read)

| dataset | det | Q Å⁻¹/px | disk r | probe | reproduces |
|---|---|---|---|---|---|
| Thronsen A stride 3 (truth) | 128² | 0.01904 | 2 px, 0.038 | phase-map, T4 config | no flag: 383 = 1.31 % (`stride-N1`) |
| demo cube (truth) | 128² | 0.012 | 3 px, 0.036 | phase-map `--truth` | no flag: its record (matrix 97.0 %) |
| binned Al-Mg-Si, stride 2 | 64² | 0.026518 v | printed | matrix-orientation | k 1: 91.1 / 0.8 / 8.1 (`gd-h5`) |
| raw stride-3 file, all | 256² | 0.006577 v | 10.24 px, 0.067 | matrix-orientation | k 4: 86.4/0.8/0.2/12.6; k 1: 97.0 n.i. |

**Grid** `--tolerance-px k` (pair = matrix = k·Q, verdict 0.75·k·Q, the shipped ratio): k ∈ {0.5, 1, 2, 3, 4} ∪
{0.01, 0.02, 0.03}/Q, i.e. Thronsen 0.525210/1.050420/1.575630, demo 0.833333/1.666667/2.5, binned
0.377102/0.754205/1.131307, raw 1.520450/3.040900/4.561350. Direct beam 0.15 on all four; `.knownVariants` ignores
the verdict distance (cutoff 0.07). Thronsen also runs the search rule at the fixed three. **Probe addition first
(tools only; no Gate D trigger):** phase-map-probe has only `--scale-to-detector` (`:500`, `:616`) and
`--not-indexed-above` (`:427`); add `--tolerance-px k` at `:616`, the five lines of matrix-orientation `:535–545`, broken
first (k 1 = `--scale-to-detector` line for line; k 0.02/Q = the no-flag runs; k on the pair alone moves a number). No
probe reads saved peaks (`--dump-peaks` `:447`/`:351` only writes): every point re-detects; peak counts constant per grid.

## Commands (serial; build each probe once, as `c683b71c…/scratchpad/build-mop.sh` did)

- Thronsen: `PMP datasetA_stride3.h5 2 0.01904 --thronsen truth_stride3.json --reach 0.68 --rule known-variants --or
  --min-relative 0.0015 --min-intensity 0 --object-table --dump-labels tol-thr-$K.json --tolerance-px $K`, then
  `t4_score.py tol-thr-$K.json truth_stride3.json`. Search rule: the same without `--rule` and `--object-table`.
- Demo: `PMP AlMgSi_demo.h5 3 0.012 --truth truth.json --tolerance-px $K` (never fit the ellipse on it).
- Binned: `MOP "<bin_4_20260712.h5>" --distortion-correct --stride 2 --tolerance-px $K`, under fastguard (1.5 GB).
- Raw: `MOP <060_STEM_SI_stride3.h5> --distortion-correct --distortion-matrix 72.876,2.025,2.025,77.438 --virtual-q
  0.006577 --stride 1 --tile-rows 12 --tolerance-px $K`, fastguard; A = (78.21, 72.11) px at 69.2°. If k 4 ≠ 86.4,
  use m12 = m21 = −2.025 or fg-map4's own A, and record which one reproduced.

**Metrics:** every run gives the top matrix axis's explained fraction (the residual CDF); Thronsen adds mislabelled %,
confusion and the T4 bar; demo its five recall lines; Al-Mg-Si matrix / β″ / not indexed %. **Bands:** Thronsen error
≤ grid minimum + 0.3 pp, no T4 metric newly failing; demo lines within 1 pp of best; Al-Mg-Si not indexed within 3 pp
of its value at 0.03 Å⁻¹, a lower edge only (without truth a too-wide tolerance cannot be rejected; β″ ≥ 2 pp flagged).

## Predictions (fixed now)

1. **Distribution:** τ_sat (the smallest grid value within 3 pp of the explained fraction at 0.03) is ≤ 0.02 Å⁻¹ on
   Thronsen, demo and raw (raw ≥ 1.5 px) and ≤ 0.0265 on binned. **Refuted if** raw τ_sat ≤ 1 px (pixel-scaled).
2. **Raw vs binned (same specimen, 4× sampling):** raw at 0.02 matrix ≥ 80 %, at 0.0132 ≥ 60 %; binned at 0.02 (0.75 px)
   75–91 %, at 0.01 (0.38 px) < 50 %. **Refuted if** raw 0.02 < 70 % (R0 fails fine) or binned 0.01 ≥ 80 % (no px term).
3. **Thronsen:** 0.019–0.03 within 0.3 pp of 1.31 %; 0.0095, 0.01 and 0.076 each worse by ≥ 0.5 pp; T4 stays FAIL
   on edge-on (7 > 5) at 0.02; search rule flat across 0.02–0.03. **Refuted if** 0.03 is > 0.3 pp worse than 0.02.
4. **Demo:** 0.012–0.03 keeps every line within 1 pp of the no-flag run. At 0.006 and 0.01, grain A as matrix drops
   5–15 pp: the +1.5 % stripe (columns 20–27, 8 of grain A's 55) moves {220} by 0.0103 Å⁻¹. **Refuted if** grain A
   holds ≥ 95 % at 0.01 (only that the stripe did not bind; no mechanism is read from it).
5. **Overall:** R0 lies in all four bands; no single k does (k 1 fails raw; k ≥ 3 is 0.057 on Thronsen); R1 at 0.02
   may miss only the binned top. R3 at f ≈ 0.4–0.55 cannot be told from R0 here: reported, not decided.

**The proposal is wrong if** the bands overlap in px but not in Å⁻¹, or the best physical value costs Thronsen
> 0.3 pp or a newly failing T4 metric. **Validity:** exact reproductions, constant peak counts, break test red first,
each exit code on its own log line. The winner is a property of these four Al-matrix datasets, not the method.
**Cost** ≈ 1–1.5 h serial, one job at a time: two builds (df ≥ 4 GB); Thronsen 12 × ~1.5 min; demo 9 × < 1 min;
binned 9 × ~3–5 min (est., 1.78 GB); raw 9 × ~20 s off the SSD, read-only, fastguard 1.5 GB (peak 501 MB pre-A1).
**Decision (owner's):** (a) R0 stands, fix only matrix-orientation-probe's one-pixel default (GREEN); (b) a new T or R3
moves a shipped default: Gate D, a refuter, the owner. No ship tonight.
