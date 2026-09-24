# Can Q and the detector ellipse be calibrated from a known crystal's spot lattice? — 2026-09-24

The owner's go, 2026-09-24 ("ok go ahead"), on plan A, which follows the Al-Mg-Si Gate D
([`almgsi-gateD-2026-09-24.md`](almgsi-gateD-2026-09-24.md)). That cube's microscope-recorded Q
was 1.733× off, and an 8.5 % ellipse was unmodelled. The app cannot fit an ellipse from a spot
pattern, because its ring fit refuses four spots per ring. The owner would consider a
lattice-based calibration "if that makes sense from a science standpoint". **This file decides
that, headless, before any app code (plan B) is designed.** It is a measurement; no app number
moves. It is committed before any run, and results are appended below.

## The method under test

The user declares a crystal and a zone axis. The in-zone reciprocal vectors g (Å⁻¹) are mapped to
detector pixels by one 2 × 2 matrix A (px per Å⁻¹): p = A·g. A is coarse-searched as a
similarity (scale from the strongest ring against the first shells; rotation in 0.5° steps),
then refined by weighted least squares on the cluster centroids of the scan-accumulated,
descan-corrected peaks, with the match radius shrinking from 1.5 to 1 px. A's polar
decomposition gives Q = 1/√det A (Å⁻¹/px), the ellipse axis ratio σ₁/σ₂ and the major-axis
angle. The in-plane rotation, which the matchers search anyway, drops out.

**What it cannot do, stated first:** any 2D lattice maps onto any other by some A (the refuter's
point in the Gate D record), so the fit alone cannot identify the zone. The zone must be
declared, or ranked by **the distortion it requires**, with the alternatives shown. It also
reads any real anisotropic strain of the reference region as detector distortion. That is
harmless for the ≈ 10⁻³ strains of an aged matrix against a percent-level distortion, and it is
why the region must be unstrained.

**py4DSTEM does not do this.** It fits the ellipse from a ring (`fit_ellipse_1D`, amorphous
ring), which is the app's `EllipseCalibration`. An app version would be a `DEVIATION`.

## Fixtures

- **D0:** the shipped demo cube, `References/demo-dataset/AlMgSi_demo.h5`. True Q 0.012 Å⁻¹/px,
  no ellipse, grains A [001], B [011], C [111]. Precipitate positions and the strained stripe
  (`truth.json` `stripe_mask`) are excluded from every fit.
- **D1 and D2:** the same generator (`tools/demo-dataset/make_demo.py`) with a new optional
  `--distort RATIO,ANGLE`. It applies an area-preserving ellipse (det 1, so the true Q stays
  0.012) where reciprocal positions become pixels. D1: 1.085 at 69.6° (the real cube's). D2:
  1.03 at 20°. Written to the session scratchpad, never committed. The default output must stay
  byte-identical in its data arrays to the shipped cube, and that is checked.
- **R:** the owner's real cube, four scan quadrants fitted independently. There is no truth,
  so this measures precision.
- **Baseline:** the app's existing ring fit (`EllipseCalibration.fitBestAvailable`) on R's mean
  pattern around the {200} ring, with and without `acceptSparseCoverage`.

## Predictions

- **P1 (D0, grain A, [001]):** Q within 0.3 % of 0.012; axis ratio ≤ 1.005.
- **P2 (D1 and D2, grain A):** Q within 0.3 %; axis ratio within ± 0.005 of the planted value;
  angle within ± 2° (D1) or ± 5° (D2).
- **P3 (D1, grains B [011] and C [111]):** the same tolerances as P2. The method is not
  [001]-only.
- **P4 (zone ranking, every D grain):** among the low-index zones whose fit explains within 5
  points of the best fraction of peaks, the true zone requires the least distortion.
- **P5 (R quadrants):** spread (max − min) / mean of Q ≤ 0.5 %, of axis ratio ≤ 0.005, of
  angle ≤ 2°. Mean within 0.5 % of the Gate D cluster fit (0.026392, 1.0853).
- **P6 (baseline):** the ring fit refuses R without `acceptSparseCoverage`. The value it gives
  with it is not predicted; the question is whether it lands within ± 0.01 of the lattice
  fit's axis ratio.

## What decides plan B

- P1–P3 fail: the method is not accurate enough, and B is not built.
- P4 fails: the app cannot propose a zone, and B must require the user to declare it. B stays
  feasible.
- P5 fails: not precise on real data; B waits.
- P6 lands within ± 0.01: B shrinks to unblocking the existing ring fit for spot patterns.

## Instrument

A new diagnostic, `tools/lattice-calibration-probe/` (numpy only). It runs on the peak dumps
`tools/matrix-orientation-probe --dump-peaks` writes, which use the app's own detection and
descan correction. `--ring-ellipse` is added to that probe for the baseline, through the app's
own `EllipseCalibration`.

## Result, part 1 (v1 fit; `lattice-fit.log`, `ring-*.log`, all exit 0)

The generator's default output is identical to the shipped cube: every data array and
`truth.json`. The peak dumps come from `matrix-orientation-probe --dump-peaks` at the 0.5 %
floor (demo) and the 0.15 % floor (real cube).

| fixture | grain / region | explained | Q vs truth | axis ratio vs truth | angle off | verdict |
|---|---|---|---|---|---|---|
| D0 | A [001] | 98.0 % | −0.006 % | +0.0000 | — | P1 holds |
| D0 | B [011] | 98.5 % | −0.000 % | +0.0001 | — | holds |
| D0 | C [111] | 100.0 % | +0.002 % | +0.0001 | — | holds |
| D1 (1.085 @ 69.6°) | A [001] | **no fit** | — | — | — | **P2 FAILS** |
| D1 | B [011] | 98.5 % | +0.017 % | −0.0001 | 0.1° | holds |
| D1 | C [111] | **no fit** | — | — | — | **P3 FAILS** |
| D2 (1.03 @ 20°) | A [001] | 98.0 % | +0.011 % | +0.0001 | 0.4° | P2 holds |
| D2 | B [011] | 98.5 % | −0.010 % | +0.0001 | 0.3° | P3 holds |
| D2 | C [111] | 100.0 % | −0.005 % | +0.0001 | 0.1° | P3 holds |
| R | quadrants 0–3 | 93.7–95.8 % | 0.026381–0.026391 (spread 0.038 %) | 1.0848–1.0857 (spread 0.0009) | 69.5–69.6° | **P5 holds**; mean within 0.04 % of the Gate D fit |

- **Where v1 converged it is accurate to about 0.02 % in Q, 0.0001 in axis ratio and 0.4° in
  angle.** Where it did not, it returned nothing. It never returned a wrong number.
- **Why D1 A and C fail (a mechanism, not measured):** the demo detector puts {200} and {220}
  at 41 and 58 px. An 8.5 % ellipse moves them up to about 2–3 px from the similarity start,
  beyond v1's 2 px first capture radius. On R the disks are at 18–27 px, so the same ellipse
  stays inside it.
- **P4 was not tested.** The wrong zones mostly failed to converge rather than being ranked by
  distortion (D2 A's [111] alternative explained 24.8 %). **Treated as failed: plan B must have
  the user declare the zone.**
- **P6: the ring fit refuses R even with `acceptSparseCoverage`** (5 of 36 sectors on the {200}
  annulus 15.6–21.6 px, 4 of 36 on {220} at 24.5–30.5 px). Plan B cannot shrink to unblocking
  it.

## v2, registered after part 1 and before it runs

**Change, capture range only:** the coarse scale window widens from ± 4 % to ± 8 %. Refinement
starts from the innermost two shells alone, with a capture radius of max(2 px, 0.10·|p|), then
takes all shells at max(1.5 px, 0.05·|p|), then fixed 1.25 → 1.0 px. Nothing else changes.

**Predictions:**
- **V1:** v2 converges on D1 A, B and C within P2's tolerances (Q ± 0.3 %, ratio ± 0.005,
  angle ± 2°).
- **V2, fixtures generated after this is committed, never run before:** D3 (1.12 @ 135°) and D4
  (1.05 @ 0°), all three grains, within the same tolerances. D4's angle is ± 5°, as for D2.
- **V3, no regression:** D0, D2 and R reproduce v1's numbers within 0.02 % Q, 0.0005 ratio and
  0.5°.

**Refuted if** any grain gives no fit or falls outside tolerance. Then the capture-range
explanation is wrong or incomplete, and plan B waits.

## Result, part 2: v2 (`lattice-fit-v2.log`, exit 0)

Correction to the fixture list above: the baseline ran on the **Bragg-vector map**, not the
mean pattern. That is the input `AppState+Calibration.swift` gives the ring fit whenever peaks
exist.

| fixture | A [001] | B [011] | C [111] |
|---|---|---|---|
| D1 1.085 @ 69.6° | Q −0.012 %, ratio −0.0001, 0.1° | +0.017 %, −0.0001, 0.1° | +0.005 %, −0.0001, 0.0° |
| **D3 1.12 @ 135° (unseen)** | +0.019 %, −0.0003, 0.1° | −0.003 %, +0.0002, 0.0° | **no fit** |
| **D4 1.05 @ 0° (unseen)** | **Q −29.3 %**, ratio +0.0004, 0.1°: **wrong, with 4 clusters, 49 % explained** | +0.012 %, −0.0000, 0.1° | −0.017 %, +0.0001, 0.1° |
| D0 / D2 / R (regression) | identical to v1 | identical to v1 | identical to v1 |

- **V1 holds. V3 holds. V2 is REFUTED:** D3 C gives no fit, and **D4 A returns a wrong number.**
  The D4 failure is the dangerous kind. The coarse search locked onto a √2-scaled sublattice (Q
  0.008487 = 0.012 / √2) and refined it to a self-consistent fit, **with RMS 0.000 px**. What
  gives it away is not the residual. It is **4 clusters instead of 8, and 49 % of peaks
  explained instead of 98 %**.
- A first look at P4, which part 1 could not test: on D2 B, [111] explains as much as the true
  [011] (98.5 %), but only with an axis ratio of 1.198 against 1.030. The least-distortion rule
  picks correctly there. That is one case, not a test.

## Conclusion of A (for the owner)

**Scientifically it makes sense, and on the real cube it works.** When the fit lands on the
right solution it is accurate to ≈ 0.02 % in Q, 0.0003 in axis ratio and 0.4° in angle, across
all three zones and ellipses from 1.00 to 1.12. On the owner's cube, four independent quadrants
agree to 0.04 %. The app's existing ring fit cannot do this: it refuses a spot pattern even
with "Fit Anyway".

**This prototype's search is not good enough to ship behind a button.** Of 15 fixture grains it
refused one and gave one confidently wrong Q. Both failures are in the search, not the model.
From this record, a version for the app needs:
1. the **crystal and zone declared by the user**, with alternatives shown with the distortion
   each needs (P4 is untested);
2. a **multi-start search**, refining every coarse optimum rather than the best one, because
   scale sublattices are a known trap;
3. the **explained fraction and cluster count shown with the result** (the owner's question 3).
   Here they were the only signal separating right from wrong, and a residual alone would have
   passed a −29 % Q.

**Plan B waits on one more headless round (v3: multi-start), pre-registered on fixtures v3 has
never seen**, as the registered rule requires.

## v3, registered after part 2 and before it runs

**Change, search only:** v3 is **multi-start**. The coarse search keeps its best rotation for
every (shell, scale) start. Starts within 1 % in scale and 2° in rotation of a better one are
suppressed, and up to 12 remain. Each is refined with v2's schedule unchanged. The result is
the refined candidate that **explains the largest fraction of peaks**, ties going to more
clusters, then to lower RMS. The runner-up is reported too. No threshold is added: a
candidate is chosen, never refused, and the explained fraction and cluster count are printed
for the reader.

**Predictions:**
- **W1, fixtures generated after this is committed, never run before:** D5 (1.10 @ 45°) and D6
  (1.07 @ 100°), all three grains, within Q ± 0.3 %, axis ratio ± 0.005, angle ± 2°.
- **W2:** v3 gets D3 C and D4 A right, within the same tolerances. These are v2's seen
  failures, so W2 is not independent; W1 is.
- **W3, no regression:** D0, D1, D2 and R reproduce v2's numbers within 0.02 % Q, 0.0005 ratio
  and 0.5°.
- **W4:** on every D grain, any refined candidate whose Q is off by more than 5 % explains
  ≤ 60 % of peaks, so the explained fraction separates it from the right answer.

**Refuted if** any grain gives no fit or falls outside tolerance, or W4 fails. Then plan B is
not built on this method without the owner deciding otherwise.
