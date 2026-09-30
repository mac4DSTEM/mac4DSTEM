# Parallax and ptychography on a dataset made for them — the graphene cube against py4DSTEM, 2026-09-30 night

The owner's decision (2026-09-30): keep both, scale the memory limits to the Mac, test on suitable data. The data:
`twisted_bilayer_graphene.hdf5` on the owner's SSD — py4DSTEM's simulated tutorial cube (`DPC_ptycho_02_sim.ipynb`:
101 × 101 scan of 128 × 128 patterns, Q 0.025 Å⁻¹/px, R 5.0 Å/px, 80 keV, probe defocus 600 Å; the tutorial's vacuum-probe
file is not on this Mac, so py4DSTEM took `semiangle_cutoff` = 26.35 mrad, the app's own half-max probe radius × Q × λ).
Tool: `tools/parallax-ptycho-real-probe/run.sh <h5> <stage> --kv 80 --q 0.025 --r 5.0 [--out <dir>]` (flags added tonight);
py4DSTEM 0.14.19 from `References/py4DSTEM-dev` on the same float32 cube the app's reader produced. Both sides' outputs,
the comparison JSONs and the scripts' numbers are beside this file; the Sonnet agent's logs were session scratch.

**Predicted before the run:** (a) every stage < 2 min and < 8 GB with the limits raised; (b) the app's fitted defocus
within 15 % of py4DSTEM's, aligned bright-field images correlating > 0.95; (c) the object phase correlating > 0.9 with
py4DSTEM's at the same method and iterations; (d) the old 1 GiB defaults refuse at least one stage.

## Cost (the old 1 GiB defaults)

| Stage | Estimator | Peak | Seconds | Output |
|---|---|---|---|---|
| preprocess · align (7 levels) | 0.26 · 0.39 GB | 0.33 · 0.85 GB | 0.8 · 13.8 | 1 961 bright-field pixels; 133 × 133 |
| KDE, automatic (factor 9.35) · 4 | 0.02 · 0.004 GB | 0.87 · 0.86 GB | 0.25 · 0.19 | 945² at 0.53 Å · 404² |
| ptychography prepare · gradient descent | 0.65 · 0.72 GB | 0.66 · 0.73 GB | 3.9 · 25.5 | canvas 1 731² at 0.3125 Å |
| ptychography difference map | 1.97 GB | 1.98 GB | 40 | **refused at 1 GiB**, ran at the raised limit |

(a) and (d) **held**. On this Mac the defaults are now half the physical memory (`PhaseContrastMemoryBudget`), so all
of it runs in the app.

## Parallax — agrees with py4DSTEM where it counts, differs at the edges and in the higher-order fit

| | C1 (Å) | C12a / C12b (Å) | R–Q rotation |
|---|---|---|---|
| app | 663.6 | 10.1 / 12.8 | −0.096° |
| py4DSTEM, app's padding/blend (32, 16) | 663.7 | 9.9 / 12.4 | −0.086° |
| py4DSTEM, tutorial's (16, 8) | 657.5 | 7.5 / 14.8 | −0.034° |
| simulated | 600 | | |

- **Defocus held** (−0.007 % against py4DSTEM at the same settings; both +10.6 % against the simulation's 600 Å, so the
  offset is the method's, not the port's).
- **Aligned bright field: refuted as stated, held in the interior.** Full 101 × 101 crop: Pearson 0.36 after registration;
  trimmed 8 / 12 / 16 px: 0.92 / 0.996 / 1.000. The app's image carries a dark vignette at the edges (mean 0.88, minimum 0.79)
  that py4DSTEM's does not (`aligned-bf-app-vs-py4dstem.png`). The KDE image against py4DSTEM's subpixel alignment: 0.905
  full frame, 0.999 trimmed 150 px, shift (1, 1) px.
- **Higher-order aberrations disagree:** the same seven terms are fitted on both sides, but the (2,1) pair is ≈ 0 in the app
  and 619 / 599 Å in py4DSTEM (`compare_parallax.json`, the coefficient logs' numbers). Recorded, not explained.

## Single-slice ptychography — the app cannot yet reconstruct this dataset

The cube was simulated with a 600 Å defocused probe. **The app builds an in-focus aperture probe only; it has no defocus
(or any aberration) input**, and py4DSTEM's reconstruction takes `defocus=600`. The comparison therefore has two arms:

| App run (8 iterations) | py4DSTEM run | Pearson (object phase, trimmed 64 px) | RMS (rad) |
|---|---|---|---|
| gradient descent, app defaults (step 0.5, norm-min 1) | defocus 0 | 0.60 (0.93 low-passed at 1.25 Å) | 0.002 |
| gradient descent, step 0.95 / norm-min 0.1 | defocus 0 | 0.51 (0.87) | 0.009 |
| gradient descent, either | **defocus 600 (the truth)** | **0.04 / −0.05** | 0.015–0.022 |
| difference map, either | any | −0.07…0.05 | 1.2–2.7 |

- Against py4DSTEM run *without* defocus the app's gradient descent is the same algorithm: the error histories agree step for
  step (0.0625 → 0.00033 vs 0.0624 → 0.00035) and the phase maps correlate 0.6 raw, 0.93 low-passed. What the app
  computes, it computes like py4DSTEM.
- Against py4DSTEM *with* the dataset's defocus — the reconstruction a user wants — the app's object is uncorrelated
  (`ptycho-phase-app-vs-py4dstem-df600.png`). (c) **refuted**: the app cannot enter the probe it needs.
- **The app's difference-map path diverges** on this cube: its error rises through the iterations (final 6.8 and 1.8) and
  the phase fills ±π; py4DSTEM's converges. Recorded as a defect; not diagnosed.
- Also unmatched, and stated: py4DSTEM fits a per-pattern origin, the app shifts by one mean origin (a noted `DEVIATION`);
  py4DSTEM's "potential" object is real-valued, the app's complex; the app pads the canvas by half a detector.

## What follows (the owner's cards)

Parallax is validated against py4DSTEM on this cube in the interior; its edge vignette and the higher-order fit are two
open items. Ptychography as shipped is half-built for its own use case: it needs the probe's defocus (py4DSTEM's own
workflow takes it from the parallax fit, which the app already has to 0.007 %) and a difference map that converges — or
it comes out (ADR 049: finished or removed). The memory limits are no longer the reason either refuses.

**Amendment (Slot 1 lane R1, 2026-09-30 night; `slot1-r1-record-2026-09-30.md`).** The ptychography table's "defocus 600 (the truth)"
arm is the WRONG-SIGN arm at rotation 0: py4DSTEM's own convention is `defocus = −aberration_C1`, and its Parallax on a probe built
from `ComplexProbe(defocus=+500)` returns C1 = −509; on this cube py4DSTEM's 8-iteration error is 2.73e-4 at −600 against 4.47e-4
at +600. "Its difference map diverges … py4DSTEM's converges" needs other settings: at the same settings py4DSTEM's DM_AP error is
non-monotone too. The app now takes the defocus; the numbers above the amendment stand as measured. The line "the error histories agree step for step" holds for the first and last iterations only: with the same probe the app and py4DSTEM differ 8–15 % at iterations 4–5 in every arm, defocus 0 included, and both sides' canvases moved between the archived run and R1's (1731 → 1728, 1601 → 1600) with no code change on the canvas files — the archived rows are not reproducible from what was kept (R1's refuter, finding (d)).
