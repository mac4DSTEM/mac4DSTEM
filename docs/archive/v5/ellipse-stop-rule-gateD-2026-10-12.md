# Ellipse fit stop rule — Gate D (2026-10-12), and the radius bias measured

Reported by macTEM (`../macTEM/docs/archive/ellipse-diagnosis-2026-10-12/`, its copy of `EllipseCalibration.swift` is this
repo's at `7c180bce`). Registered here before any experiment on this tree; the results section is added after.

## Item 1 — `fit1D` refuses fits that sit at the optimum

**Trigger.** Gate D: a defect whose cause is reported but not yet established on this tree, in a function whose output is a
calibration (`fitBestAvailable` → `CalibrationSession.applyEllipseFit`).

**Diagnosis (macTEM's, to be refuted here).** `fit1D`'s Levenberg–Marquardt loop (`EllipseCalibration.swift:284-313`) tests
convergence only after an accepted step (`trial.cost < current.cost`). Near the optimum the cost change of a proposed step
is roundoff, the comparison refuses it, damping grows ×10 per pass, and the step shrinks until the candidate equals the
current point; nothing then sets `converged`, and the 100-pass cap throws `didNotConverge` at the optimum. Which rings fail
depends on roundoff.

**Refuting observations** (any one refutes the diagnosis; a failed reproduction closes the item, ADR 050):
- R0: no clean planted ring is refused on this tree's code, on macTEM's 84 clean plants or on our own sweep.
- R1: a refused case whose last accepted point is NOT at the optimum of the same objective found independently
  (scipy `least_squares`): more than 1e-6 relative in (A, B, C) or 1e-4 px in the centre.
- R2: a refused case whose final passes are refused for another reason — `solve` failing or a non-physical candidate —
  rather than `trial.cost >= current.cost`.

**Predictions** (registered before the run):
- P1: macTEM's clean tier (84 plants, `tools/ellipse-parity/make_fixture.py` there) fed to this tree's `fit1D` is refused
  `didNotConverge` on ≥ 1 case; secondary: on the same 12 macTEM listed (same source, same arithmetic).
- P2: every refused case: (a) ends in ≥ 10 consecutive cost refusals; (b) final damping ≥ 1e50; (c) its last accepted point
  equals the scipy optimum within 1e-7 relative in (A, B, C) and 1e-5 px in the centre; (d) the proposed relative step is
  below 1e-10 within 5 refusals after the last acceptance.
- P3 (the fix below): 0 refusals on the same plants; each previously refused case returns the point of P2(c); every case the
  old code accepted returns (centre, a, b, θ) within 1e-9 relative / 1e-7 px of its old result (bit-identical expected on
  most; every non-identical case listed); `tools/ellipse-calibration-test`'s existing cases pass with unchanged values.

**Fix design.** Test the same 1e-10 relative-step rule on the proposed step when the trial is refused for cost: a step that
small which roundoff will not let lower the cost is converged, and the fit returns the last accepted point. The accepted
branch is unchanged, so its arithmetic is too. Considered and not taken: MINPACK's xtol 1.49e-8 (what py4DSTEM's `leastsq`
uses) — it would stop earlier on cases that converge today and move their numbers by up to ~1e-8 relative; a gradient-norm
test — it needs a scale the mixed (px, px⁻²) parameters do not have.

**Fixture.** `tools/ellipse-calibration-test` gains a clean sweep (numpy plants, the scipy optimum of the same objective as the
reference): every plant must fit, the centre within 0.05 px, and `fit1D` must equal the scipy optimum (which also pins the
objective: an unbiased variant swapped in silently would fail it). Broken once: the old stop rule must turn it red.

## Item 2 — the radius is biased high (py4DSTEM parity, a decision for the owner)

The objective (A dx² + B dx dy + C dy² − 1)·I over a ring I = exp(−(r − R)²/2s²) is minimised at R(1 + 1.75 (s/R)²) (the r dr
measure, the conic's r², the squared intensity: R_f² = ∫r⁵I² dr / ∫r³I² dr). py4DSTEM's `fit_ellipse_1D` has the same
objective. The app applies only b/a and θ (`Calibration.ellipseTransform`), so the bias reaches a correction only through
the ratio, at −3.5 (s/R)² ε of the distortion ε; the absolute a and b are displayed, not applied.

**Predictions** (measurement only, nothing changes): on clean rings with s = 3 px, `fit1D`'s (a + b)/2 exceeds R by
0.246 ± 0.03 % at R 80 px, 0.109 ± 0.02 % at 120, 0.039 ± 0.01 % at 200 (macTEM: 0.258 / 0.115 / 0.042). The profile path
(`fitAmorphousRing` seeded by the conic, as `fitBestAvailable` runs it) holds the plant's model exactly, so its (a + b)/2 is
within 0.01 % of R on the same rings, and `fitBestAvailable` accepts the profile there.

## Results (2026-10-12, M5 Pro; numpy 2.5.0, scipy 1.18.0)

Written by a Sonnet lane, refuted by an independent Sonnet agent that rebuilt old (`git show HEAD`) and new `fit1D` with its own
harness and its own scipy comparison. "ABC rel" below is max |ΔA, ΔB, ΔC| / ‖(A, B, C)‖, since B ≈ 0 on a circle. Session logs
are named, not kept: `lanes/E/run-orig-clean.log`, `analysis-old.txt`, `p3-report.txt`, `bias.txt`; the refuter's `lanes/E-refute/`.

**Item 1.** R0, R1, R2 not refuted; the diagnosis stands, and the fix landed as designed.
- P1 held: this tree's `fit1D` refuses 12 of macTEM's 84 clean plants `didNotConverge`, the same 12 names as macTEM's run (the
  refuter: also 14 of its 144 noisy plants).
- P2 (a) held: 94–97 consecutive cost refusals end every refused case; (b) held: final damping 1.2e91–3.7e92; (c) held: the last
  accepted point is within 2.5e-7 px and 1.9e-9 ABC rel of scipy's optimum (the refuter: 2.5e-7 px, 2.5e-9 on all 26); the cost
  change of a refused step is at most 7.4e-14 on costs of 3–8. **(d) did not hold:** the proposed (damped) step is below 1e-10 at
  the first refusal in 9 cases and only at the sixth in 3 (first steps 1.8e-10, 6.4e-10, 3.0e-10).
- P3: 0 of 84 refused (the refuter: 0 of 228); the 12 return exactly their P2(c) point. **"Bit-identical on most" did not hold:**
  33 of 72 formerly accepted fits are bit-identical; 39 stop one tiny step earlier, because the old loop refused a step under 1e-10
  before a later accepted one. Their largest differences, 2.9e-8 px, 1.6e-10 relative in a and b, 6.7e-9 rad in θ (ε > 0), are
  inside the registered bounds except a strict relative-1e-9 reading of θ. One existing harness line changes in its 17th digit.
- The refuter's adversarial corpus (720 plants: noise with gradients and hot pixels, sparse rings and arcs fitted anyway, starts
  8–20 px off, 1024–2048 px detectors, intensity scales 1e-3–1e15) found no fit the old code accepted that the new one refuses or
  moves by more than 2.9e-8 px; a refused-branch threshold of 1e-4 still stays within 1e-6 px of scipy. Outside this item:
  contiguous arcs fitted anyway still end `didNotConverge` in 54 of its 150 (slow descent, ~68 accepted steps in 100 passes).
- Fixture: `tools/ellipse-calibration-test` plants 48 clean rings; the old rule refuses 7 of them (red), the new fits all 48 within
  0.037 px of the plant and 1.1e-7 px / 6.4e-10 / 1.7e-8 rad of scipy. A weight exponent of 0.98 fails all 48 (the objective is
  pinned). It does not pin the stop point: "no accepted number moves" rests on the measurement above. `EllipseStopRuleTests` fits four
  96 × 96 rings the old rule refused (red on it in the Debug build).

**Item 2.** Measurement held; the profile-path prediction did not.
- `fit1D`'s (a + b)/2 over R, gap-free rings: +0.2456 / 0.1093 / 0.0803 / 0.0615 / 0.0394 % at R 80 / 120 / 140 / 160 / 200 px
  against 1.75 (s/R)² = 0.2461 / 0.1094 / 0.0804 / 0.0615 / 0.0394 %; a 60° gap adds 0.002–0.011 points. Held.
- **Profile path did not hold:** `fitBestAvailable` kept the profile on 59 of 84 and fell back to the conic on 25 (residual
  0.235–0.336 > 0.22; 24 gapped, 1 gap-free); 20 of the 59 are beyond 0.01 %. The refuter, seeding the profile at the plant: the
  gap-free shortfall (0.019 % on two rings, the one fallback) is the optimiser from the conic seed, not the model; gapped rings carry
  a model bias up to 0.067 %.
- On these plants a/b is exact (the ring width scales with the elliptical radius); the registered ratio term −3.5 (s/R)² ε held to
  about 2 % on 24 constant-width plants. Not measured: background and annulus width, which a scratch model of the objective says
  dominate the bias; that is a question for its own registration, not a result.
