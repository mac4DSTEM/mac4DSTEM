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

## Results

(Added after the run.)
