# Slot 1 lane R1 — independent refuter (Fable 5.1, read-only, 2026-09-30 night)

# Lane R1 — Gate B refuter (Fable 5.1, read-only), 2026-09-30

Reviewed: BRIEF.md, report.md, the R1 diff (Core/App/Session/UI/tools), PtychographyProbeTests.swift, the three new python files, every log
in $SP/R1 and $SP/R1/evidence (e1-*, e2-py-*, arm-*, cmp-*.json, harness-*, mut/, unit-mut-*, test-*, golden/), record.md, and the cited
py4DSTEM-dev / tutorial lines. No repo file changed; no xcodebuild run; one read-only python over the cmp/meta JSONs.

Overall: **HOLDS WITH CORRECTIONS.** The science (sign, conventions, fixture) is established by E1 and the ComplexProbe pin; what must
change before landing is wording that overstates a source, one unpinned seam at the app's call site (the product can say a defocus the
run did not use), the labelling of two unverified branches (the 180° branch, the higher-order toggle), and three record.md amendments.

## (a) Seed sign — HOLDS WITH CORRECTIONS

1. **The sign is established, by E1 not by "the tutorials".** E1's cube is py4DSTEM's own forward model (`e1_parallax_convention.py`:
   fft2 of the centred `ComplexProbe(...).build()._array` × object, fftshift) and the vendored `Parallax` returns C1 = −508.67 for
   `defocus=+500`, C12a/b = 73.94/58.03 against ComplexProbe's 76.60/64.28, rotation −0.074°, transpose False (e1-a.log; e1-a-repro.log
   byte-identical). With utils.py:159–160 / phase_base_class.py:1820–1821 (`C10 = -defocus`) that gives C1 = C10, defocus = −C1.
2. **Correction — the tutorial citation is 2 of 6.** `defocus = -…aberration_C1` appears only in phase_retrieval_01.ipynb:1028 and
   version_0.14.8/ptycho01_gold_on_carbon.ipynb:817 (the 1025 Å gold dataset). phase_retrieval_02.ipynb:614→665 and all three
   ptycho02_MoS2 notebooks (0.13.17:605, 0.14.1:595→638, 0.14.8:622→674) pass `defocus = parallax.aberration_C1` (+C1) into the
   reconstruction while printing `defocus*-1` as the "estimated defocus" (≈ 50 Å, where the sign is nearly harmless; 0.14.1 even
   comments "dF has the opposite sign as C1"). The notebooks contradict each other. The claim "py4DSTEM's tutorials use −C1" is
   repeated in convention_check.py's docstring, PtychographyPreparation.swift's type comment, PtychographySettings.swift (the
   `useParallaxFit` doc), the UI .help ("py4DSTEM's rule") and the proposed status line — reword all five to "E1 and the gold-on-carbon
   tutorial; the MoS2 tutorials pass +C1 at ≈ 50 Å".
3. **`c1Angstrom` carries py4DSTEM's sign.** ParallaxAberrationFitting.swift:186–202 is parallax.py:2284–2306 line for line, including
   the ±π fold with `aberration.scaled(by: -1)` (:193–195 ↔ :2290–2293) and the transposed C12a sign (:199–201 ↔ :2298–2301);
   tools/parallax-aberration-test pins rotation/c1/c12a/c12b to 2e-5 against a python re-derivation with the same fold
   (reference.py:94–113) and greps the py4DSTEM source strings (:18–21). Graphene: app 663.6 vs py 663.7 (arm-align.log, record.md).
4. **The 180° ambiguity is right and is py4DSTEM's fold, not a new finding.** e1-d (rot90 k=2): rotation −0.21°, C1 = +509.57, C12a/b
   negated. e1-c (k=1) shows the fold at the knife-edge: recovered −90.2° → reported +89.8° with every sign flipped — a cube whose true
   rotation is near ±90° lands on either branch by noise. Physically the other branch is not "a worse fit": a 180° detector rotation
   equals (−defocus, conjugated object), so the wrong branch reconstructs a NEGATIVE-phase object.
5. **Same rotation? Not enforced.** `runSingleslicePtychography` resolves `calibrationSession.calibration.rotationRad`/`transposeQR`
   (ParallaxPreprocessing.swift:91–132; used at PtychographyPreparation.swift:330–348); `useParallaxFit` reads `lowOrder.c1Angstrom`
   only, never `lowOrder.rotationRad`, and the app's fit always runs the auto branch (`fitParallaxAberrations()` passes default
   options: forceTranspose false). Every arm had both ≈ 0 (arm logs "rotation 0.0000 deg", fit −0.0956°, py COM 0.0°), so the runs are
   on one branch — but the app has no guard, and a calibrated rotation > 90° from the fit's (or `transposeQR` true against a
   transpose-false fit) silently applies the wrong sign / wrong C12a sign. The status line prints both angles
   (AppState+PhaseContrast.swift:445–451) and the reader must know the rule. Must: the .help and status say what the other branch
   means (use +C1; the wrong branch conjugates the object); open-items carries it; the automatic flip/refusal is an owner card.

## (b) The three conventions — HOLDS

6. defocus → C10: utils.py:159–160, phase_base_class.py:1820–1821; reference.py greps the source string. C12a/b: utils.py:2717–2722
   (C12a = C12 cos 2φ12, C12b = C12 sin 2φ12) and χ at utils.py:317–320 gives C12 cos 2(φ−φ12) = C12a cos 2φ + C12b sin 2φ; exp(−iχ)
   :383; ifft2 + unit norm :456–457. Higher terms: utils.py `aberrations_basis_function` (α^(m+1)/(m+1)·{cos,sin}(nθ),
   θ = arctan2(qy[None,:], qx[:,None])) = ParallaxAberrationCorrection.swift:110–128 = the new `chi`; ComplexProbe's ⅓α³(C21 cos(φ−φ21)+…)
   is its m = 2 row. φ axis: utils.py:446–451 (alpha from x[:,None] = first axis; phi = arctan2(y[None,:], x[:,None])) with
   kx = fftfreq(gpts[0], sampling[0]) → rows; the app's θ = atan2(frequencyColumn, frequencyRow) with per-axis samplings; pinned on
   32×24 at 0.4/0.55 Å (M3 red at |Δ| 0.11 vs limit 8e-7).
7. **Where θ could still differ — the transposed cube, and only for astigmatism.** py4DSTEM transposes the INTENSITIES
   (phase_base_class.py:861–920), so its probe grid is the transposed detector; the app keeps the (qy, qx) grid and swaps only the
   positions' sampling (PtychographyPreparation.swift:341–348, pre-R1). With pure defocus χ is even and this is invisible; with C12 the
   pair "fitter flips C12a under transpose (Fitting.swift:199–201) ↔ probe on the untransposed grid" is verified by nothing: E1 ran
   transpose False only; the tutorials never pass C12 into ptychography (grep: no `polar_parameters`/`C12` in either gold notebook).
   Label: astigmatism seeding verified for transpose = false. Non-square is pinned; the corrector's single `sampling`
   (Correction.swift:108–111) is square-only by construction and does not conflict.

## (c) The fixture — HOLDS WITH CORRECTIONS

8. Real pin: 6 cases on the non-square 32×24 grid through py4DSTEM's own `polar_aberrations_to_cartesian`, every term to fifth order,
   |Δ| ≤ 1e-5·max, worst 1.7e-6; 15 planted controls each ≥ 0.28 relative; M1–M6, M8, M9 red at |Δ| 0.05–0.12 against limits
   7e-7…1.4e-6 (mut/m*.out, harness-2/3.log).
9. **Bit-identity to 02174c9c is established.** `golden/golden` contains the pre-R1 error string ("dataset, probe radius, rolloff, or
   memory limit"), not the new one, and no `PtychographyProbeAberrations` symbol (nm/strings); built 22:21:07, the Core file written
   22:21:34. Hashes a2f70f0e…/1c821196… therefore come from the old code; M11 (1e-4 on one pixel) red proves the pin bites.
10. **The app's call site is pinned by nothing (the code change that leaves everything green).** The harness pins
    `PtychographyPreparer.prepare(…, aberrations:)` at tools/…/main.swift:539 and M10 is red THERE; but the app's call
    (AppState+PhaseContrast.swift:364–368) is exercised by no test — grep: `runSingleslicePtychography` appears only at
    AppState.swift:1208. Delete `aberrations: aberrations,` on that line: harness green, all 9 unit tests green, and the status line
    and product name still say "defocus −600 Å", because both read `aberrations` from the settings (:396–402, :431–434), not from the
    input the run used. Must: the prepared input (or the result) carries the aberrations it was built with, and the product
    name/status read those — or a unit test drives `runSingleslicePtychography` on the demo cube and checks the input's probe against
    the in-focus one. Prefer the first; then the product cannot lie.
11. Smaller: the fixture's meaning of `defocusAngstrom` rests on the Swift harness's own `defocus = −C10` mapping
    (`probeAberrations(from:)`) mirroring utils.py:160 — two places share one assumption; the fixture already carries
    `polar["defocus"]`, so `require(aberrations.defocusAngstrom == polar["defocus"] ?? 0)` closes it end to end. Units are Å
    throughout and the fields go through NumericField → DecimalEntryFormat (LayoutPolicy.swift:324–325). Replay/sidecar do not
    carry the probe (report Q2): a replayed run silently starts in focus — must be an open-items line.

## (d) The graphene arms — HOLDS WITH CORRECTIONS

12. The numbers support "same algorithm, same probe, same final error", not "step for step". cmp-*.json: raw 0.69/0.73, registered
    0.69/0.74, low-passed 0.79/0.90 at ∓600; errors within 1.2 % at iterations 0–1 and 0.1–5.6 % at the end, 8–15 % at iterations 3–4
    in EVERY arm including df 0 (15.1 % at it. 3) — the mid-run gap belongs to the app/py pairing (mean vs per-pattern origin is the
    declared suspect), not to the new probe. The report's "within 5 %" bar failed and says so.
13. **The archive comparison cannot be attributed — both sides moved.** record.md: app canvas 1 731² (crop 1603), py 1601²; today
    1728² (arm-a0.log) and 1600²; py df-0 phase std 0.008 → 0.0026, py first error 0.0624 → 0.06265. No file that sets the app's
    canvas changed since the archive commit (git log: 2f5d90e2 last on main.swift / PtychographyPreparation.swift), so the archived
    app arm ran with flags the archive's scratch logs did not keep; py settings likewise unrecorded; the archived compare_ptycho.json
    holds no error histories or settings. What the logs settle: today's pairing is self-consistent (same canvas both sides,
    registration ≈ 0 px). Say "the archived rows are not reproducible from what was kept", not "comparator validation failed". The
    record's "step for step" was first-and-last only — those two agree today as well.
14. "−600 converges lower than +600" (app 2.64e-4 vs 4.47e-4, py 2.73e-4 vs 4.47e-4, crop-51 × 32 it. 2.15e-4 vs 3.77e-4) is
    py4DSTEM-vs-py4DSTEM evidence about the cube's convention (a probe that matches the data leaves a lower residual; the wrong branch
    forces a conjugated object GD cannot reach in 8 iterations), consistent with E1 — supporting, not independent, and not a general
    discriminator (the ratio can be ≈ 1 on a thick sample). Fine as stated. The "extra" a3-vs-py-600 row (−0.31 raw, −0.43 after a
    17-px registration) is unexplained and carries no claim: drop it or mark the registration spurious.

## (e) The difference map — the report HOLDS; record.md is REFUTED on this line

15. py-dm600.log / meta.json: DM_AP, 8 iterations, reconstruction_parameter 1.0, step 0.5, norm-min 1, no constraints: errors
    [0.0627, 0.1135, 0.0646, 0.343, 0.367, 0.751, 0.154, 0.538], phase −π…π, std 1.44 — wrapped noise, like the app's
    [0.0625 … 4.76 … 0.475]. The record's "py4DSTEM's converges" was measured at unrecorded settings (probably the tutorial's constraints
    or another parameter/step); at the archived settings it does not reproduce. R2's input is "both diverge at these settings"; R2 must
    first find the settings at which py4DSTEM's DM converges before diagnosing the app.

## (f) Breaking the tests — HOLDS WITH CORRECTIONS

16. M7 is an equivalent mutant (χ = 0 → cos 1, −sin 0 = −0.0; the golden hashes stayed identical) — "unobservable" is right.
17. M10 is the harness's catch only (mut/m10.out: "crop 0: the prepared probe is not the aberrated probe"). With `prepare` ignoring
    aberrations all 9 unit tests pass: `testNoAberrationsReproduce…` calls prepare without aberrations, the other eight use
    `PtychographyProbe.build` or the settings. Neither gate pins the app's call site (finding 10).
18. Unit mutation batches match the claim: A → exactly the four convention/bit tests red, B 3, C 3, D 2, E 1 (unit-mut-A…E.log);
    test-2/3: 9 passed, 0 failed. Batches A–D ran on 8 tests (the width test came after) — fine.
19. Process: harness-2/3.log and test-2/3.log carry no exit line (grep EXIT = 0); the harness's own "all passed" line and the 9/0
    counts stand, but "EXIT=0" in the report is asserted, not logged (the mut/*.out files do log it). The full unit gate did not run on
    this diff (-only-testing PtychographyProbeTests only) while `SingleslicePtychographySection` went private → internal with a new
    init and SingleslicePtychographyExportTests was left untouched — the supervisor's full unit run is required before commit.
20. **The higher-order toggle ships unverified.** E1 could not validate the seeding of C21/C23: py4DSTEM's own recursive fit returned
    C21 = 0.00 for a planted 8000 Å (e1-b.log) and off numbers on the rotated cubes; on graphene the app's (2,1) pair is ≈ 0 while
    py4DSTEM's is 619/599 Å (record.md) — the very terms the toggle would feed. "Unvalidated stays labelled": the toggle's .help says
    "unverified against py4DSTEM", or the toggle waits for a cube where both fits agree.

## What must change before this lands

- Wording (finding 2): five places — cite E1 + the gold tutorial, name the MoS2 notebooks' +C1.
- The call-site seam (10, 17): the input/result carries its probe aberrations and the product name/status read them from there.
- The branch (5, 7): .help/status/open-items state the other branch (+C1) and its consequence (conjugated object); astigmatism labelled
  transpose-false-verified; the automatic flip goes to the owner as a card.
- The higher-order toggle labelled unverified (20). Replay/sidecar omission in open-items (11).
- record.md amendments (13, 15): "defocus 600 (the truth)" = the wrong-sign arm at rotation 0; "py4DSTEM's DM converges" = not at
  the archived settings; "step for step" = first and last iterations.
- Full unit gate by the supervisor (19). Optional: the polar-defocus cross-check in the harness (11); drop the a3-vs-py-600 row (14).
