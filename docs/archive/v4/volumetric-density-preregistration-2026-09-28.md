# Volumetric precipitate density — pre-registration (2026-09-28 night)

ROADMAP step 2's last item. Registered before any code; the owner's three decisions of 2026-09-28 night are in §1.

## 1. Decided (owner, 2026-09-28)

- **Thickness is typed, not measured.** Nanobeam precessed data cannot measure foil thickness: PACBED fitting works
  at ~7–25 mrad convergence (LeBeau et al., Ultramicroscopy 110 (2010) 118; Xu & LeBeau, Ultramicroscopy 188 (2018)
  59), Thronsen's is 1.13 mrad with 1.04° precession, and precession averages away Kossel–Möllenstedt fringes. The user
  enters t (nm), its uncertainty σₜ, and its source (EELS, CBED, assumed). PACBED estimation is deferred until a
  large-convergence dataset exists.
- **No independent thickness exists yet;** the owner will acquire EELS or CBED with the next microscope session.
- **Per-object correction:** N_V = (1/A) · Σᵢ 1/(t + hᵢ), hᵢ = object i's extent along the beam.

## 2. The formula and where it comes from

Nie & Muddle (Acta Mater. 56 (2008) 3490), as applied to θ′ in Al-4Cu (Rodriguez-Veiga et al., arXiv:1804.09634,
Eq. 2): n = N / (A (d + δ)) for {100} plates of true diameter d in a foil of thickness δ — a plate is counted when any
part of it lies in the foil, so its centre may sit in a slab δ + (extent along the beam) thick. They use d for every
variant because the face-on variant is invisible in their images and is estimated (their Eq. 3). The app classifies
face-on plates directly, so each object takes its own extent:

| Class (beam ∥ ⟨001⟩Al) | hᵢ | From |
|---|---|---|
| θ′ edge-on ([100], [010] variants) | measured trace length Lᵢ (≈ d) | the object table |
| θ′ face-on ([001]) | plate thickness, not measurable here → the owner types it (default: none, refuse) | typed |
| T1 on {111} | d·sin 54.7° ≈ 0.82 d, d from the trace | geometry — **to verify** before build |

Uncertainty: σ(N_V) from σₜ by propagation per object; the count's own Poisson error beside it.

## 3. Refusals (never silently volumetric)

No t → areal only, and the row says why. t ≤ 0 or σₜ < 0 → refused. A class without an hᵢ rule → that class areal only.
Areal density stays shown beside every volumetric one. Provenance and the CSV carry t, σₜ, source, hᵢ per object.

## 4. Pass bar (T6), fixed before the build

A synthetic foil, generated in `tools/` (not the app): circular plates of known N_V in a slab of thickness t, the three
{100} variants (and T1's four {111}), random centres including plates cut by both surfaces, projected along [001];
counted with the app's own `PrecipitateObjectReport` path. **Pass:** the estimator recovers the true N_V within 5 %
(mean of 20 seeds) for t ∈ {50, 100, 200} nm and d ∈ {20, 100} nm; **and** the naive N/(A·t) fails the same bar at
d = 100 nm (the test must be able to fail). This validates the formula and the code, not a thickness. The real bar
waits for the owner's EELS/CBED measurement.

## 5. State, surface, tests

- **Owner of the state:** thickness is a property of the specimen area, per dataset, persisted in the sidecar beside
  the calibration — not `AppState` (a new stored field in `PhaseMappingProduct`'s precipitate settings; confirm at
  build).
- **Surface (costed):** in Precipitates, two rows — "Foil thickness [ 120 ] ± [ 10 ] nm" and "Source [EELS ▾]" —
  and one line per phase, "N_V 3,1 ± 0,3 ×10³ /µm³"; the Object Table summary gains one column. A mock goes to the
  owner before the UI is built (Drive before more surface).
- **Tests before code:** the hᵢ rule per class; the refusal cases; the propagation against a hand-derived value; each
  broken first. Gate D applies (a new scientific number) — an independent refuter on the formula, not the diff.

## 6. Open before the build

1. ~~T1's hᵢ~~ — owner 2026-09-28: by geometry, h = d·sin 54.74° = d·√(2/3), checked in T6.
2. ~~Face-on θ′~~ — owner 2026-09-28: areal-only unless a plate thickness is typed.

## 7. Amendment before any T6 run (2026-09-28 night, committed before the harness exists)

Two effects the §2 estimator ignores, found reading `PrecipitateStatistics` and by geometry, not from data:
**truncation** — a plate whose centre lies outside the foil shows a chord, so hᵢ = Lᵢ·s is too small and (a) reads
high where d ≳ t (Nie & Muddle's Eq. 1 is the correction: mean apparent d_a = d (t + (π/4) h) / (t + h), h = d·s,
s = sin of the plate normal's angle to the beam; the chord of a tilted disc cut by the foil has the same π/4 mean);
**edge exclusion** — the app counts only objects clear of the scan edge but divides by the whole scan (the areal
density too), low by the fraction of objects the edge band catches: a property of plate size ÷ field size.

**T6 therefore scores four estimators, the bar (|mean − 1| ≤ 5 % in every cell) applied to each:**
(a) the registered per-object Σ 1/(t + Lᵢ·s) / A; (b) class-level N / (A (t + d̂·s)), d̂ from the mean counted Lᵢ by
inverting Eq. 1; (c) (b) with each counted object weighted by Miles–Lantuéjoul's S² / ((S − bxᵢ)(S − byᵢ)) (its
bounding box), weights also in the mean L; naive N / (A·t). Only an estimator that passes every cell may ship.
**Harness parameters fixed now:** field S = 2400 nm (Thronsen A's extent), pixel 2.5 nm (960²), θ′ edge-on
(normals ±x, ±y) and T1 (normals (±1, ±1, 1)/√3) run separately, centres uniform in x, y ∈ [−R, S + R] and
z ∈ [−h/2, t + h/2], truth N_V = accepted plates / ((S + 2R)² (t + h)); a plate whose in-foil footprint (dilated one
pixel) meets an earlier one is rejected and not counted in truth; ~1 % projected coverage; seeds until the standard
error of the mean is ≤ 1.5 % (cap 400) — amending §4's 20 seeds, which cannot reach that at this field size; counting
through `PrecipitateSegmentation.classObjects` with the edge rule of `PrecipitateStatistics`, minimum size off.

**Predictions (analytic; pixelisation, merging and rejection ignored):** (a) FAILS one cell (θ′ d 100 t 50: 1.095)
and passes others partly because the edge loss cancels the truncation gain; (b) FAILS the three T1 d 100 cells (0.932);
(c) PASSES all twelve (1.000); naive FAILS all twelve (1.07–2.87). A deviation from these beyond the standard error is
a finding about the harness or the app's counting before it is one about the formula.

```
T6 analytic predictions, field 2400 nm (Thronsen A extent), ratio = estimate / true N_V
(a) registered per-object h_i = L_i*s; (b) Nie-Muddle class-level, app edge exclusion; (c) (b) + Miles-Lantuejoul edge weights; naive N/(A t)
theta' edge-on     d= 20 t= 50  (a) 1.011 PASS  (b) 0.991 PASS  (c) 1.000 PASS  naive 1.39 FAIL
theta' edge-on     d= 20 t=100  (a) 0.997 PASS  (b) 0.991 PASS  (c) 1.000 PASS  naive 1.19 FAIL
theta' edge-on     d= 20 t=200  (a) 0.992 PASS  (b) 0.991 PASS  (c) 1.000 PASS  naive 1.09 FAIL
theta' edge-on     d=100 t= 50  (a) 1.095 FAIL  (b) 0.957 PASS  (c) 1.000 PASS  naive 2.87 FAIL
theta' edge-on     d=100 t=100  (a) 1.025 PASS  (b) 0.957 PASS  (c) 1.000 PASS  naive 1.91 FAIL
theta' edge-on     d=100 t=200  (a) 0.984 PASS  (b) 0.957 PASS  (c) 1.000 PASS  naive 1.44 FAIL
T1 {111} at <001>  d= 20 t= 50  (a) 1.001 PASS  (b) 0.986 PASS  (c) 1.000 PASS  naive 1.31 FAIL
T1 {111} at <001>  d= 20 t=100  (a) 0.991 PASS  (b) 0.986 PASS  (c) 1.000 PASS  naive 1.15 FAIL
T1 {111} at <001>  d= 20 t=200  (a) 0.988 PASS  (b) 0.986 PASS  (c) 1.000 PASS  naive 1.07 FAIL
T1 {111} at <001>  d=100 t= 50  (a) 1.043 PASS  (b) 0.932 FAIL  (c) 1.000 PASS  naive 2.45 FAIL
T1 {111} at <001>  d=100 t=100  (a) 0.984 PASS  (b) 0.932 FAIL  (c) 1.000 PASS  naive 1.69 FAIL
T1 {111} at <001>  d=100 t=200  (a) 0.951 PASS  (b) 0.932 FAIL  (c) 1.000 PASS  naive 1.31 FAIL
```

The edge finding reaches the **shipped areal density** (Thronsen A, T1: 14 edge objects beside 43 counted). Changing
it is its own Gate D, with the owner — not part of this build.

## 8. Run 1 — the registered result (2026-09-28 night, `tools/volumetric-density-test`, `t6-run1.log`)

**Every estimator FAILS the bar as registered.** (a) one cell (θ′ d 100 t 50: 1.081, predicted 1.095); (b) eight;
(c) one (T1 d 20 t 50: 0.948); naive all twelve. First run, no harness change before it. The code was reviewed line
by line against §7 (basis, truth, counting through `classObjects` + `PrecipitateStatistics`).

```
theta' edge-on d= 20 t= 50 seeds= 20  cnt=1102.8 edge= 22.8 rej=  4.6%  (a) 0.972+-0.001 PASS  (b) 0.950+-0.001 FAIL  (c) 0.959+-0.001 PASS  naive 1.370+-0.002 FAIL
theta' edge-on d= 20 t=100 seeds= 20  cnt=1076.5 edge= 21.8 rej=  4.7%  (a) 0.974+-0.001 PASS  (b) 0.966+-0.001 PASS  (c) 0.976+-0.001 PASS  naive 1.179+-0.001 FAIL
theta' edge-on d= 20 t=200 seeds= 20  cnt=1058.8 edge= 21.7 rej=  4.7%  (a) 0.978+-0.001 PASS  (b) 0.976+-0.001 PASS  (c) 0.986+-0.001 PASS  naive 1.083+-0.001 FAIL
theta' edge-on d=100 t= 50 seeds= 20  cnt= 254.1 edge= 20.5 rej= 10.5%  (a) 1.081+-0.007 FAIL  (b) 0.943+-0.005 FAIL  (c) 0.978+-0.006 PASS  naive 2.855+-0.014 FAIL
theta' edge-on d=100 t=100 seeds= 20  cnt= 244.6 edge= 19.4 rej= 10.5%  (a) 1.015+-0.005 PASS  (b) 0.946+-0.004 FAIL  (c) 0.983+-0.004 PASS  naive 1.907+-0.008 FAIL
theta' edge-on d=100 t=200 seeds= 20  cnt= 233.7 edge= 19.7 rej= 10.9%  (a) 0.973+-0.006 PASS  (b) 0.946+-0.005 FAIL  (c) 0.985+-0.006 PASS  naive 1.427+-0.009 FAIL
T1 {111} d= 20 t= 50 seeds= 20  cnt= 274.8 edge=  8.6 rej=  2.5%  (a) 0.952+-0.003 PASS  (b) 0.935+-0.003 FAIL  (c) 0.948+-0.003 FAIL  naive 1.294+-0.004 FAIL
T1 {111} d= 20 t=100 seeds= 20  cnt= 249.1 edge=  8.4 rej=  2.4%  (a) 0.958+-0.004 PASS  (b) 0.952+-0.004 PASS  (c) 0.967+-0.004 PASS  naive 1.135+-0.005 FAIL
T1 {111} d= 20 t=200 seeds= 20  cnt= 234.4 edge=  7.0 rej=  2.4%  (a) 0.970+-0.002 PASS  (b) 0.968+-0.002 PASS  (c) 0.983+-0.002 PASS  naive 1.061+-0.002 FAIL
T1 {111} d=100 t= 50 seeds=120  cnt=  27.9 edge=  3.2 rej=  2.6%  (a) 1.030+-0.007 PASS  (b) 0.919+-0.006 FAIL  (c) 0.972+-0.006 PASS  naive 2.475+-0.015 FAIL
T1 {111} d=100 t=100 seeds= 89  cnt=  19.7 edge=  2.6 rej=  2.3%  (a) 0.977+-0.009 PASS  (b) 0.925+-0.008 FAIL  (c) 0.982+-0.009 PASS  naive 1.710+-0.015 FAIL
T1 {111} d=100 t=200 seeds= 59  cnt=  16.1 edge=  1.9 rej=  2.5%  (a) 0.962+-0.011 PASS  (b) 0.941+-0.011 FAIL  (c) 1.003+-0.011 PASS  naive 1.335+-0.015 FAIL
sanity worst |deviation| = 0.0146
VERDICT (a): FAIL
VERDICT (b): FAIL
VERDICT (c): FAIL
VERDICT naive: FAIL
```

**Deviation from §7 to explain first:** every d = 20 cell of (a) and (c) reads 2–5 % low, both classes, where the
analytic model says ≈ 1.00. **Hypothesis H (before any diagnostic run):** the harness rasterises by *cell
intersection* (every pixel a sample falls in, `main.swift` line 128), so a trace of length c covers ≈ c/p + 1 pixels
and the app's length (extent + 1) reads ≈ c + p — 12 % of a 20-nm plate, 2.5 % of a 100-nm one — making hᵢ and d̂
too large. A scan samples *points* (probe positions), not cells. **Predicted:** D1, pixel 1.25 nm → the d 20
deficits roughly halve ((c) T1 d 20 t 50 → ≈ 0.974); D2, pixel 2.5 nm with Lᵢ − p → (a) and (c) at d 20 within 1.5 %
of §7's analytic values. **Refuted if** D1 leaves the d 20 deficits unchanged. Diagnostics do not replace run 1's
verdict; a changed harness or estimator is a new registration.

## 9. Diagnostics D1, D2 — H held (`t6-D1.log`, `t6-D2.log`; run 1 reproduced byte-identical first)

| Cell | run 1 (c) | D1: p 1.25 nm (c) | D2: Lᵢ − p (c) | §7 analytic (c) |
|---|---|---|---|---|
| T1 d 20 t 50 | 0.948 | **0.972** (pred. ≈ 0.974) | 0.980 | 1.000 |
| θ′ d 20 t 50 | 0.959 | 0.978 | 0.998 | 1.000 |
| θ′ d 100 t 50, estimator (a) | 1.081 | 1.085 | 1.102 | 1.095 |

D1 roughly halves every d 20 deficit; (c) then passes all twelve cells. D2 puts θ′ on the analytic values ((a)
1.008/0.994/0.989 vs 1.011/0.997/0.992; (c) 0.994–0.998) and (c) passes all twelve. **Partial miss:** T1 d 20 keeps
−1 to −2 % (predicted within 1.5 %): its traces run at 45° to the grid, where cell intersection overshoots by ≈ √2·p,
not p. **Reading:** the formula did not fail at d 20; object length read about one pixel long did. (c) is unbiased
wherever lengths are; (a) is biased by truncation (1.08–1.10 at d ≈ 2t) as §7 predicted. Length accuracy of order one
pixel (13.9 nm on the stride-3 Thronsen scan) is the limiting systematic and must enter the reported uncertainty.
Not yet refuted by an independent reader; no app code written.

## 10. Independent refuter (Opus, 2026-09-28 night; its scratch `refuter/`, prediction written before its run)

**Oracle experiment:** (c) fed the generator's true in-foil chords reads 0.986–1.013 in all twelve cells (T1 d 20 t 50:
0.988; predicted ~1.000, H weakened at ≤ 0.975) — **H not refuted:** the d 20 deficit is length measurement. Measured
overshoot L − c: θ′ +0.70–0.73 px, T1 d 20 +1.23–1.35 px (D2's −1 px over-corrects θ′). **Held:** the tilted-disc π/4
chord and h = d·√(2/3) for T1; Miles–Lantuéjoul on visible footprints; rejection thinning negligible (D1 raised θ′ d 100
rejection 10.5 → 17.5 %, (c) moved 0.002). Claim 1 corrected: truncation alone is +14.4 % at θ′ d 100 t 50, partly
cancelled by the edge loss.

**Found:** (1) **(c) is exact only for one plate size.** For lognormal d it inverts to ≈ E[d²]/E[d]: exact lengths give
0.935 at d 100 t 50, CV 0.4, and 0.82–0.87 at d ≈ 190 t 50, CV 0.6 — where real T1 sits. **No estimator here may ship
as volumetric density.** (2) The exact edge weight counts the forbidden border pixel: S² / ((S − bx − p)(S − by − p))
(0.2 % here, ~1.2 % on a 171-px scan). (3) 0.3–1 % of accepted interior plates leave no pixel (harness defect).
(4) **The shipped areal density is biased low by the edge rule, ≈ 13–17 % for T1 on Thronsen A** (its model predicts
edge/counted 0.29–0.40; the drive saw 14/43 = 0.33) — systematic, inside one scan's Poisson error.
**Unestablished:** polydisperse (c), sliver visibility, trace merging at real coverage, the length bias on real
point-sampled masks, any real thickness.

**Status:** volumetric density is NOT built. Next only with the owner: a polydisperse bar (CV 0, 0.3, 0.6) and an
estimator that passes it, and — separately — the areal edge correction as its own Gate D.

