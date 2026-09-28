# A3a — Thronsen et al.'s own vector analysis on the stride-3 cube (2026-09-28)

ROADMAP A3's first half on this Mac (ADR 042 permits running their code; ADR 044 makes their methods references).
Measurement only: no `mac4DSTEM/` code changes.

## Registered before the run

**Inputs.**
- Their notebooks, unmodified on disk: `References/SPED-phase-mapping-main/VectorAnalysis/vector_analysis_1_peak_finding.ipynb`
  and `vector_analysis_2.ipynb` (the repo as fetched for ADR 042).
- Run by `tools/thronsen-dataset/run_their_vectors.py`, which executes their code cells in order in one namespace,
  skips display-only cells (plots, `%matplotlib`, the interactive peak-finding preview, bare expressions), and applies
  the patches listed below. Their code is read at run time; none of it is copied into this repo.
- The cube is `References/thronsen-datasetA/datasetA_stride3.h5`: their `datasetA_preprocessed.hspy` at every third scan
  row and column (171 × 171), stored ×65535 as uint16 (`tools/thronsen-dataset/subsample.py`). It is divided back by
  65535 to float32, with their axes (signal 0.01904 Å⁻¹/px, offset −1.2138).
- Environment: conda env `thronsen`, Python 3.10, their `packages.txt` pins for pyxem 0.14.2, hyperspy 1.7.3, numpy 1.23.5,
  scipy 1.10.0, scikit-image 0.19.3, scikit-learn 1.2.1, orix 0.10.2, diffsims 0.5.1, numba 0.56.4, dask 2023.1.0,
  h5py 3.8.0, pyFAI 0.21.3, silx 1.1.2. **Deviations:** Apple's `tensorflow-macos` 2.10.0 for `tensorflow` 2.10.0 (unused
  here); Python 3.10 (their list names none).
- References: their published `datasetA_phasemap_vectors.hspy` and `ground_truth.hspy` (Zenodo 10.5281/zenodo.6645396,
  CC BY 4.0, md5 checked, `References/thronsen-datasetA/published/`), sampled `[::3, ::3]`.

**Patches (each a deviation, each for the grid, not for the method).**
1. Notebook 1: `dp` is our stride-3 cube instead of `hs.load('datasetA_preprocessed.hspy')`.
2. Notebook 1: the Al reference pattern `peaks_com[215, 274]` becomes `peaks_com[72, 91]`, full-resolution (216, 273),
   the nearest position on our grid.
3. Both notebooks: the 512 × 512 shapes (`dpshape`, `X_pix`) become 171 × 171.
4. Notebook 2: `ground_truth_all.npy` becomes their `ground_truth.hspy` at `[::3, ::3]`.

Everything else in the method runs as written. Their LoG threshold 0.0005, COM refinement (square 8), Al removal at
8 px, the direct-Al rule (≤ 1 spot), slab cuts, orientation relationships and score cut-off 0.07 are all unchanged.
Two global inputs change with the grid: the mean pure-Al pattern and the sample rotation derived from it. Both are built
from the pure-Al positions present, about one ninth of them.

**Reference numbers (already read, they are not outcomes).** Against the stride-3 truth: their published vectors map
`[::3, ::3]` 1.51 %, template matching 1.70 %, NMF 1.56 %, ANN 0.95 %; the app (T4 configuration) 1.31 %.

**Predictions.**
- **P1 (environment).** Their vector analysis on our cube reproduces their published vectors map at our positions on
  ≥ 99.0 % of positions. Refuted if < 99.0 %. Expected differences come only from the Al reference position, the
  subset-built Al mean and rotation, and uint16 quantisation (≤ 1/65535 per pixel).
- **P2.** Its per-position error against the stride-3 truth is 1.51 ± 0.15 %. Refuted outside 1.36–1.66 %.
- **P3 (method against method).** It and the app disagree at 1.5–3.0 % of positions, more than half of them within
  1 px of a truth phase boundary. Refuted outside the range, or if half or fewer are at boundaries.
- **P4 (B1's positions).** At the 5 truth-T1 positions where the app says edge-on, theirs says T1 at ≥ 4. At the 3
  truth-Al positions, no prediction; read as it comes.

**Kill rule.** If P1 fails, the environment or the patches are wrong. Nothing about the methods is concluded until the
difference is explained.

## Result (`run-vectors.log` notebook 1, 473 s, peak footprint 3.15 GB; `run-vectors-nb2.log` notebook 2)

Run: `python tools/thronsen-dataset/run_their_vectors.py <work>` in the `thronsen` env; notebook 2 was rerun alone
(`--nb2-only`, from notebook 1's saved peak files) after the first run stopped on a display-only cell whose plot call
spans two lines. The runner now skips such a cell only if it contains a display call. **Added after registration, path
only:** their CIF folder is resolved absolutely (`folder_cif`), because the run's working directory is not the notebook's.

| Prediction | Outcome |
|---|---|
| P1 their run = their published map at our positions on ≥ 99.0 % | **held**: 99.99 %, 3 of 29 241 differ (Al → edge-on twice, face-on → edge-on once) |
| P2 error vs the stride-3 truth 1.51 ± 0.15 % | **held**: 1.51 %; their own printed line: success rate 98.49 % |
| P3 theirs vs the app disagree at 1.5–3.0 %, over half within 1 px of a truth boundary | **held**: 1.55 % (453), 85 % at a boundary |
| P4 at B1's 5 truth-T1 positions theirs says T1 at ≥ 4 | **refuted**: T1 at 1 — edge-on at (6,91), (6,92), (8,91); face-on at (46,126) |

**The environment is proved without the full cube.** Their per-pattern method, run by their own code here, reproduces
their published map at our positions to 3 positions in 29 241. Their methods are now references we can run on any input.

**Method against method.** Their vector analysis errs at 443 positions, the app at 383, both at the same 203. Their
largest error is Al → edge-on (140); the app's is T1 → Al (204). The app is right where theirs is wrong at 240
positions; theirs right where the app is wrong at 180.

**For B1.** All 3 truth-Al positions the app calls edge-on, theirs calls edge-on too; so do 3 of the 5 truth-T1 ones.
B1's spurious edge-on positions are hard for both methods, not an artefact of the app's matcher: it argues for checking
them against the full-resolution truth (now on disk, `References/thronsen-datasetA/published/ground_truth.hspy`) before
any edge-on guard is registered.
