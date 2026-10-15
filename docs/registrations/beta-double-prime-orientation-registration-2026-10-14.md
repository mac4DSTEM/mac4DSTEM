# β″ (Mg5Si6, monoclinic C2/m) orientation maps — registration (2026-10-14)

Suite ROADMAP "What blocks the study" item 1; ADR 046 parked β″ maps ("orientation mapping stays cubic and hexagonal"). The
owner's study needs them. Tier 1 (orientation angles are numbers a scientist reads). Gate D applies. Registered before any
code or run; nothing here is an owner-validated result.

**What blocks it today** (read, not edited).
- `ACOMCrystalSymmetry` (`Core/Analysis/OrientationResult.swift`) has `.cubic`, `.hexagonal`, `.identity`; `reduce`,
  `sampleFundamentalZone` and `ipfColor` switch on those three.
- `CrystalModel.swift` validates `.cubic`/`.hexagonal` by cell metric; `supportsOrientationMapping` is `symmetry != .identity`
  (line 220), so a CIF-imported monoclinic phase (`CIFImport` returns `.identity`, line ~1035) is refused for maps by design.
- `OrientationPlan` / `OrientationMatcher` take the symmetry at init and sample the m-3m sector (`OrientationPlan.swift`
  header); `PhaseReferenceLibrary.lowIndexZoneAxes` is deliberately unreduced for this reason.
- Template generation is already symmetry-agnostic (`Crystal` builds the triclinic metric; `CIFImport` comment, 2026-09-11)
  and `cartesianZoneAxis` is monoclinic-correct. Both CIFs load; the two files in `References/crystal-structures/` are
  byte-identical (checked with `cmp`), a = 15.16, b = 4.05, c = 6.74 Å, β = 105.3° (Andersen 1998 per the CIF).

**The candidate: `.monoclinic` (Laue 2/m).**
- Proper rotation subgroup {E, C₂ ∥ b} (b unique axis, as the CIF), order 2; inversion is not distinguishable in a
  kinematic pattern, so the reporting group is 2/m, order 4 (same practice as the cubic 24 / hexagonal rotations).
- Fundamental zone: orientation space SO(3) halves under C₂ (rotation about b of 180° identifies two matrices); the
  direction (IPF) zone for 2/m is a quarter sphere: polar angle from b ∈ [0, 90°], azimuth ∈ [0, 180°].
- Disorientation: min over the 2 proper operators of the rotation angle of S·M₁·M₂ᵀ (cf. cubic `reduce`, 24 operators);
  maximum possible disorientation 180° for a two-element group, to be checked in a test, not assumed.
- Deterministic representative as in the cubic code: smallest rotation angle, canonical quaternion breaks ties.
- Needle axis: β″ needles run along Al <100> with b ∥ the needle (**literature convention, not in the repo — the
  coordinator must confirm**; the repo only records "variant-1 β″ needles", `../v3/precipitate-handcount-2026-09-11.md`).
  Count of distinct orientations in Al = |cubic proper group| / |stabiliser| = 24/2 = **12** variants, derived from group
  order, valid only if one orientation relationship holds; the repo has no per-variant record. The Al reference frame uses
  the existing cubic reduction; the 12 variants are the cubic images of one β″ orientation.

**Truth and cross-check.**
- Synthetic round trip: templates of the β″ cell rotated by known orientations (random SO(3) draws and the 12 Al-variant
  images, ≥ 500 seeds), indexed against the library generated at the app's angular step. No orix or pyxem exists under
  `References/` (checked: only `py4DSTEM-dev`, `SPED-phase-mapping-main`, no orix); `docs/open-items.md` records a known
  frame rotation P between app Euler angles and py4DSTEM/orix, so angles compare as disorientations, never as raw Euler
  angles. A pip-installed orix 2/m reduction is an optional cross-check, run from the owner's conda env if present.
- **Cannot be validated:** no β″ truth set exists (suite ROADMAP item 5); real β″ speckle and needle merging
  (`open-items.md`: B1, the needles still fragment); the correctness of the library step on a 15.16 Å cell.

**Predictions** (set before runs; bands justified or deferred):
- P1 the group closes: 2 operators, S² = E, det +1, to 1e-12; cubic and hexagonal paths byte-identical (existing tests).
- P2 round trip: recovered disorientation to truth ≤ the library's angular step for ≥ 95 % of draws — the step and the
  fraction are **to be set from the first synthetic run's design before the candidate is run** (no β″ measure in the record).
- P3 variants: the 12 templates are pairwise distinct under 2/m reduction and map into one orbit under the cubic group.
- P4 a β″ pattern indexed with `.identity` shows the C₂ ambiguity (two equal-score matrices 180° about b); `.monoclinic`
  merges them — the test that fails if reduction is missing.

**Refuting observations:** P1 violated; any draw whose reduced orientation differs for two C₂-related inputs; round-trip
error above the step in > 5 % of draws; the 12 variants not distinct; cubic/hexagonal outputs changing by a byte.

**Ships badged unvalidated** ("Unvalidated stays labelled"): `validation:"none"`, "monoclinic orientation — no β″ truth
set" beside the map and in the CSV/provenance, never "validated" in a release note until one dataset with truth passes.

**UI cost:** none new; the phase picker already lists the symmetry name (`displayName`, "Monoclinic 2/m"); rooms unchanged,
frozen shell untouched. Wording only: one badge line in the Crystal Maps inspector (1 row, to be costed at build).

**Gates.** Tests first, each broken once (drop an operator, wrong axis, wrong zone); unit + core + scientific; a fixture
(synthetic β″ draw, red on `.identity`); one independent Gate B refuter on the diagnosis, not the diff; a card only if an
existing map moves (it must not).

Registered 2026-10-14 before any code or run.
