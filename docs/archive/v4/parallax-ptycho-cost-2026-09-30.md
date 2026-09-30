# Parallax and ptychography: the true cost on the 051 cube — Gate D record, 2026-09-30 night (M5 Pro 64 GB)

The question (owner drive 2026-09-11, `../v3/open-items-detail-2026-09-16.md`): the app refused both on
`051_STEM SI_preprocessed_unfiltered_bin_4_20260629.h5` (128 × 128 scan of 64 × 64 patterns, 268 MB) — "Parallax KDE needs
about 8,16 GB", "Single-slice ptychography needs about 11,55 GB" — against a 1 GiB working limit. Is that cost real?

Tool: `tools/parallax-ptycho-real-probe/run.sh <h5> preprocess | align | kde <auto|factor> | ptycho <gd|dmap>` (diagnostic;
one stage per process, the app's option values, each estimator's own number read from its refusal, then the limit raised).
Inputs: 200 kV (the raw DM4's `Microscope Info.Voltage`), Q 0.03564271 Å⁻¹/px and R 100.3 Å/px from the file, rotation 0,
origin the mean pattern's centre of mass, probe radius 3.91 px.

**Predicted before the run:** the measured peak footprint is the estimator's bytes plus what is already resident, within
0.5–1.5 ×; KDE cost grows with the square of the upsample factor; no stage leaks.

| Stage | Estimator | Measured peak | Seconds | Output |
|---|---|---|---|---|
| preprocess · align (5 levels) | 3.7 MB · 6.8 MB | 78 MB · 87 MB | 0.07 · 0.07 | 18 bright-field pixels; 160 × 160 |
| KDE, factor 8 · 32 · 64 | 26 MB · 0.42 GB · 1.68 GB | 0.11 · 0.51 · 1.77 GB | 0.06 · 2.95 · 26 | 1 024² at factor 8 |
| KDE, automatic (factor 141) | **8.159 GB** | 8.25 GB | 268–275 | 18 066 × 18 066 px at 0.71 Å |
| ptychography, prepare | 7.06 GB | 7.07 GB | 1.8 | object canvas 29 129 × 29 129, probe 64 × 64 |
| ptychography, gradient descent · difference map (8 iterations) | 24.04 · 24.58 GB | 24.08 · 24.62 GB | 31.5 · 37.1 | same canvas |

- **The estimators are honest** (prediction held): peak ÷ (estimator + resident) is 0.96–1.03 for parallax and ptychography
  prepare, 0.77 for the reconstructions (the estimator counts the canvas already resident). The 8,16 GB of the drive is
  reproduced to the byte. The drive's 11,55 GB is **not** reproduced — 7.06 and 24.0 GB here; which step or setting gave it
  is unknown.
- **No leak** (held): each stage run twice in one process ends at the same footprint.
- **KDE time** grows far faster than the square of the factor (**refuted**): 8 → 141 is 310 × in pixels and about 4 600 ×
  in seconds.
- **What the numbers are made of, on this cube:** the bright-field mask is 18 detector pixels; the scan step (100 Å) is 229
  object pixels against a 64-pixel probe, and 92 % of the reconstructed object phase is exactly 0; the alignment error does
  not fall (0.281 → 0.294). The automatic KDE factor is 141 on a 128 × 128 scan.

## What it means, and what is not claimed

The refusals were right to refuse and their numbers are true: the 1 GiB limits are fixed constants (not scaled to the
machine), and this cube would need 8–25 GB and minutes for outputs that are mostly empty. The cube is a nanobeam scan with
a 100 Å step, and the measurements above say the probes do not overlap and the bright-field disk is a few pixels — not the
acquisition either method is built for. **Not measured:** either method on a dataset acquired for it. None with its
calibration is on this Mac (py4DSTEM's tutorial cube is not here), so both stay "undriven on real data" and their science
stays what the synthetic py4DSTEM-parity harnesses show.

**The owner's decision (ADR 049: kept or removed), with the session's recommendation:** keep both as they are for v4.1 —
they are gated against py4DSTEM on synthetic data, cost nothing when unused, and refuse truthfully — and do not raise the
limits. Removing them is about 4 000 lines of `Core/Analysis`, 520 of `AppState+PhaseContrast`, the Reconstruction
sidebar's two sections and six harnesses; worth it only if the owner will never acquire defocused-probe data. No independent
refuter ran on this record: no app code and no shipped number changed.
