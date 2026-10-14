# The profile ring fit's start traps noisy rings — Gate D (2026-10-13)

Reported by macTEM (`../macTEM/docs/archive/mac4dstem-ring-start-report-2026-10-13.md`, its Gate D and refuter in
`ring-fit-noisy-gate-d-2026-10-13/`; its copy of `EllipseCalibration.swift` is this repo's at `5ba712a0`). Registered
here before any run on this tree; the Results section is added after. Nothing lands from this record without the owner:
a change here moves the ellipse the app applies (card M2).

**Trigger.** Gate D: a reported defect, cause not yet established on this tree, in the function behind the Fit button
(`fitBestAvailable` → `CalibrationSession.applyEllipseFit`; b/a and θ are applied to every Bragg vector).

**Diagnosis (macTEM's, to be refuted here).** `fitAmorphousRing` starts both ring sigmas at `max(1, ringWidth / 4)`
(10–17 px for a ±20 px annulus around a 3 px ring). On noisy rings the 11-parameter LM from there falls into a dead-ring
basin: I1 → 0, the ring sigmas at their 0.25 px bound, a wide central Gaussian and the constant carrying the annulus mean,
so a, b, θ and the centre carry no ring information. The residual cap does not refuse it, because noise inflates the
normalised residual of any model (a ring-less constant scores 0.17–0.26 against the 0.22 cap).

**Refuting observations** (any one refutes; a failed reproduction closes the item, ADR 050):
- R0: on macTEM's 144 noisy plants and its fresh set (SEED0 77031), this tree's `fitBestAvailable` (default arguments,
  macTEM's centre guess and annulus) accepts no profile fit that is off by more than 1 % in (a + b)/2.
- R1: the accepted wrong fits cost no more than the true ring's model on the same pixels (then they are the model's
  optimum, and no start can fix them).
- R2: a ring-sigma start read from the seed (below) rescues fewer than 90 % of them, or turns a right fit wrong.

**Predictions:**
- P1: ≥ 10 accepted profile fits off by > 1 % in (a + b)/2 on the 144 (macTEM: 16 through its own wrapper, which also
  refuses a/b − 1 > 0.093); on most, I1 below a tenth of its start or a ring sigma within 0.05 px of 0.25. Their b/a and
  θ errors are reported too, since those are what the app applies.
- P2: each costs ≥ 1.2× the true ring's model on the same pixels.
- P3, candidate (a), the ring sigmas started from a width measured on the seed ellipse's radial profile (half maximum,
  no truth): 0 such fits on both sets; no fit within 0.1 % before is outside it after; on macTEM's 84 clean plants and
  `tools/ellipse-calibration-test`'s 48-ring sweep and existing cases, no model choice is lost and every profile fit kept
  both ways moves by ≤ 0.01 % of R in (a + b)/2 and ≤ 1e-3 rad in θ.
- P4, candidate (b), a profile fit with a ring sigma ending within 0.05 px of its bound is refused (the fit falls back to
  the conic): it catches ≥ 10 of the P1 fits and refuses no fit that was within 0.1 %.
- P5, real data: on the mean pattern of `Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5` (polycrystalline Au
  rings), HEAD and candidate (a) choose the same model on each ring annulus tried and agree to 0.01 px and 1e-3 rad.

**What would be built.** Candidates (a) and (b) as held patches with a fixture (a noisy plant red on HEAD), gated, not
applied. The owner chooses on card M2: (a), (b), both, or neither.

## Step 2 amendment (2026-10-14, written and committed before any step-2 run)

- **The candidates as built**, held in `ring-sigma-start-gateD-2026-10-13/` (`core-a.diff`, `core-b.diff`, `core-ab.diff`,
  each against `EllipseCalibration.swift` at `5ddec30d`; none applied). (a): both ring sigmas start at the half-maximum width
  of the annulus's radial profile about the conic seed: 1 px bins of the seed's elliptical radius scaled to (a + b)/2, a
  3-bin mean, the half maximum between the profile's minimum and peak, crossings interpolated linearly, σ = FWHM / 2.3548,
  at least 1 px; py4DSTEM's (ro − ri)/4 stands when the peak has no crossing on both sides inside the annulus. The sigma
  step scales stay (ro − ri)/4. macTEM's tested estimator measured the circular radius about the seed centre in whole bins,
  so its 16 of 16 is not evidence for this one; P3 is. (b): a profile fit whose smaller ring sigma ends ≤ 0.30 px throws
  `ringWidthAtFloor` after the existing checks, and `fitBestAvailable` falls back to the conic (or throws when the conic's
  residual is over 0.2). Lower bound only.
- **P6, both (a + b):** 0 accepted profile fits off by > 1 % on either noisy set; no fit within 0.1 % before is refused
  or outside it after; on the clean sets and the 48-ring sweep, as P3.
- **Sets:** set A = macTEM `refuter/plants_a.py`, set B = `plants_b.py` (SEED0 77031, the "fresh set"), macTEM `6c1f4d4`,
  all 275 cases each: noisy and clean decide P3, P4 and P6 as registered; the printed and refusal tiers are printed, not
  decided. "Wrong" = off by > 1 % in (a + b)/2 (step 1); "right" = within 0.1 %.
- **P5's annuli**, read off the mean pattern's radial profile before any fit (64 × 64, a beam stop and its wire; rings near
  9.5, 16.5, 25 and 33.5 px about the centre guess (28.47, 34.43), the centroid of the brightest 1 % of pixels): [5, 13],
  [13, 21], [21, 30], [30, 38], and each widened by 1 px on both sides.
- **The fixture:** seeded noisy plants rendered in the test (no data file) on which HEAD accepts a profile fit off by more
  than 1 %; the test asserts the Fit returns no profile fit that far off. One plant of the dead-ring kind (expected green
  under (a) and (b)) and, if one exists at a unit-test size, one of the drifting kind (expected green under (a) only).

## Results — partial: step 1 only (2026-10-13, M5 Pro; the session ended before steps 2–5)

A Sonnet lane ran this tree's `fitBestAvailable` (HEAD `ce245821`, default arguments, macTEM's centre guess and annulus) on
macTEM's refuter plant sets (`refuter/plants_a.py`, `plants_b.py` at macTEM `6c1f4d4`; 144 noisy plants each, 3 and 10 %
noise). The harness and the analysis are in `ring-sigma-start-gateD-2026-10-13/` (`scan-main.swift`, `build.sh`, `an.py`);
its output, `head-noisy-summary.txt`. "Wrong" = an accepted profile fit off by more than 1 % in (a + b)/2.

- **R0 not refuted, P1 held:** 35 of 144 (set A) and 32 of 144 (set B) accepted profile fits are wrong — macTEM counted 16 on
  set A because its wrapper refused 19 more for a/b − 1 > 0.093 (16 + 19 = 35); this app has no such refusal. Off by up to 48 % in R, 0.51 in b/a (what the
  app applies), 1.56 rad in θ, 40 px in the centre. The conic seed was within 1.3 % on every one.
- **R1 not refuted, P2 held:** every wrong fit costs 1.30–3.42× the true ring's model on the same pixels (35 of 35, 32 of 32).
- **Not as diagnosed:** only 17 of 35 and 18 of 32 are the dead ring (I1 below a tenth of its start, or a ring sigma ≤ 0.30
  px). The rest keep ring sigmas of 2–7 px and drift 10–40 px off centre, mostly 10 %-noise rings with a 60° gap. So
  candidate (b) alone cannot catch about half; whether (a) rescues them is P3, not yet run.
- Clean plants (84): 59 profile, 25 conic fallbacks (residual 0.235–0.336), as lane E measured on 2026-10-12.
- Not run: R2, P3, P4, P5 (candidates, Au_ref), the held patches, the fixture, the refuter. The next session resumes at step 2.
