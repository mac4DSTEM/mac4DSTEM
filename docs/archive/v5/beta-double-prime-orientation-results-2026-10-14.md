# β″ monoclinic 2/m orientation maps — results (2026-10-14, lane B; Sonnet; closed: P2 refuted as registered, nothing landed — ADR 050; the follow-up is a new item, `beta-double-prime-orientation-b2-registration-2026-10-14.md`)

Registration: `beta-double-prime-orientation-registration-2026-10-14.md` (4ff4ab51). Design/band: `beta-double-prime-orientation-design-2026-10-14.md`
(committed before any candidate code or run). Tier 1, Gate D (the cause of the one failed prediction below was not known; it is diagnosed, not fixed).
Tests: `mac4DSTEMTests/MonoclinicOrientationTests.swift` (12 tests). The coordinator's Gate B refuter has not run; nothing here is self-approved.

## Candidate
`ACOMCrystalSymmetry.monoclinic` (2/m, b unique = Cartesian +y in the py4DSTEM frame): proper operators {E, C₂ ∥ b}; `reduce`,
`reduceDirection` (y ≥ 0, azimuth about b in [0, 180°)), `sampleFundamentalZone` (farthest-point on the quarter sphere, azimuth wrap),
`ipfColor` (hexagonal pattern: b red, a green, z blue, green/blue weight (1 − cos 2φ)/2 so there is no seam at 180°). `CrystalModel`
validates by cell metric (α = γ = 90°, β ≠ 90°, the importer's 0.05°). `CIFImport`/MP: the metric proposes `.monoclinic`; `confirmedFamily`
demands a 2-fold along b or a mirror ⟂ b from the atoms (centring absorbed by the translation search) and otherwise falls back to
`.identity`, as every monoclinic metric imported before. The needle convention (b ∥ Al ⟨001⟩) is Andersen et al. 1998, stated in code.
Badge: `validation: "none"` + `validation_note` in `CrystalModel.provenance` → the existing inspector note, export caption and PNG
metadata; one `InspectorWarning` row in the Phase-model section, only for a monoclinic phase.

## Scores (registered wording)
- **P1 group closes — PASS.** 2 operators, S² = E, det +1, orthogonal, closed, fixes the lattice-derived b (1e-12). Cubic/hexagonal: the existing tests, unchanged.
- **P2 round trip — FAIL as registered.** Band set in the design note: ≤ 7.7° for ≥ 95 % of 600 draws at 200 templates. Measured:
  86.5 % within 7.7° (median 3.09°, p90 156.7°, max 180°). Refuting observation met (error above the step in > 5 %). Recorded in the test
  with `XCTExpectFailure` (red the day the default library passes). **Diagnosis** (same 600 draws, by class): 519 ok; 22 are fixed by a
  half turn in-plane (the π-near-symmetric pattern); 15 axis right, in-plane wrong; 44 axis wrong by 6–34° at reliability ≈ 0.01–0.06 (a
  near-miss in a dense pattern). Mirrored and sampled-zone draws fail alike, so it is not the group. Library density: 400 / 800 / 1600
  templates give 96.3 / 99.0 / 99.5 % within 7.7° (one log, `lanes/B/logs/diag2.log`; post-hoc, **not** a P2 pass). Cause: the default
  library (7.7° spacing) is too coarse for a 15.16 Å cell plus the 180° in-plane ambiguity. Not fixed; a quality/step choice for β″ is a **new registration**.
- **P3 12 variants — PASS.** 24 cubic images of one β″ orientation → 12 distinct under 2/m (24 unreduced), all in one cubic orbit. The in-plane
  direction (a ∥ [320]Al) is an example; the count needs only b ∥ ⟨001⟩.
- **P4 C₂ merge — PASS** (group isolated from the library: scored on draws the matcher found, ≥ 40 of 60 required). The two C₂-related truths give
  one pattern; unreduced the recovered matrix is > 172° from one of them, reduced by 2/m both are ≤ 7.7° away. Red with `reduce` = identity.
- **Cubic/hexagonal byte-identical:** the code paths and tests for those cases are untouched (gate lines in the lane report).

## Mutations (each confirmed red, then restored)
M1 drop C₂ → P1, P3, P4, reduce red. M2 C₂ about x → P1, P2, P3, P4, post-hoc, reduce red. M3 no azimuth fold → zone and IPF red. M4 `confirmedFamily` always
`.monoclinic` → "stays Unreduced" and the MP monoclinic document red. M5 drop `validation` key / γ check → badge and validation red.

## Cannot be validated
No β″ truth set (suite ROADMAP item 5); real needle speckle (B1); the P2 result is for synthetic kinematic patterns at 200 kV.
