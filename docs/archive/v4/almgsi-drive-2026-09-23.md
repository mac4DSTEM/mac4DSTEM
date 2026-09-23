# Al-Mg-Si in the app — the synthetic demo cube, then the real cube, 2026-09-23 night

The owner asked to drive the Al-Mg-Si data through the finished precipitate pipeline (ADR 038),
"maybe also at 0,15 %", and see whether the result is reasonable. This is a measurement, with no
code change. Phase mapping stays unvalidated. The drive recipe is the Thronsen one; the settings
per run are below.

## A — synthetic demo cube (`References/demo-dataset/AlMgSi_demo.h5`, truth known)

100 × 100 scan, 0.5 nm per scan pixel, 128 × 128 detector at 0.012 Å⁻¹ per pixel. Three Al grains
([001] A, [011] B, [111] C), a vacuum corner, and β″ planted as 6 end-on [010] objects of 16 px
and 3 [001] needles of 36 px (8-connected components of `truth.json` `precipitate_map`).

**Settings:** Al (matrix, [0 0 1]) plus β″ added twice, at [0 1 0] and [0 0 1]
(`beta_double_prime_Mg5Si6.cif`). The app's shipped detection and matching (search rule). Then
the known-variants rule on the same peaks.

**Predictions, stated before driving:**
- A1, search rule: the Precipitates section counts **6 β″[010] objects and 3 β″[001] objects**,
  with no small or spurious objects at minimum size 1. The probe's truth-mode run of the same
  rule tonight was perfect (`pre-e5.log`).
- A2, known variants (guard on): grain B (Al [011], 2250 positions) is labelled β″, as in the
  probe (`post-e4k1.log`). β″ objects therefore include one ~2250-px object that is not a
  precipitate. **The rule is not fit for a multi-grain matrix, and the objects will show it.**

## B — the owner's real cube (`Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5`, no truth)

4× binned: 64 × 64 detector at 0.045741 Å⁻¹ per pixel (the file's own calibration), so the
default 0.020 Å⁻¹ tolerances are under half a pixel (`archive/v3/phase-mapping-2026-09-12.md`
finding 6). The specimen sits on ⟨110⟩Al (finding 2).

**Settings:** the app's calibration path (origin measured). Detection floor **0.15 %** as the
owner asked, then his 0.5 % default for comparison. Phases Al (matrix) and β″. Matrix zone axis
from "Find Matrix Zone Axis". Tolerances via "scale to detector". Search rule.

**What "reasonable" means here, written before the run.** There is no truth, so only
self-consistency:
- B1: Find Matrix Zone Axis returns a ⟨110⟩ axis (09-12: all five ⟨110⟩ tie at 39 %).
- B2: after scaling to the detector, most of the scan is matrix (≥ 70 %), with not indexed
  ≤ 30 %.
- B3: if β″ is found, its counted objects (at a stated minimum size) are **elongated** (median
  aspect ≥ 2), with orientations clustering along the in-plane ⟨100⟩Al directions.
- **Not reasonable, whatever the fractions:** β″ as scattered speckle, meaning raw objects ≫
  counted objects and orientations uniform. That would say the score saturates, not that
  precipitates were found (the pre-registration of 09-12 said the same).
- Expected failure mode, stated so it cannot be read as a finding afterwards: with the beam on
  ⟨110⟩Al, no β″ variant is viewed down its needle, so a library of β″ zone axes may match
  nothing. A matrix-plus-not-indexed map is a legitimate result here.

## Result

Driven on the owner's Mac, 2026-09-23/24 night, build `dd-app` of `bac36e4`. No log files: the
numbers are read off the app's own Result and Precipitates sections, as the recipe says (memory
`thronsen-in-app-drive-recipe`).

### A — demo cube

- **The app cannot hold one phase at two zone axes.** A slot takes one zone axis. Adding the same
  crystal again is refused silently: `addPhaseMappingSlot` skips a model id already in the
  list, and a re-import of the same file keeps its id. The workaround was the same CIF under a
  second file name (`beta_double_prime_Mg5Si6_needle.cif`, gitignored). Both then showed the
  CIF's own block name; `phaseDefinitions()` now appends the zone axis when names collide.
- **A1 (search rule), with β″ at [0 1 0] and [0 0 1]: HELD exactly.** 6 objects, median
  2,00 nm (4 px × 0,5 nm), and 3 objects, median 9,00 nm. Not indexed 0,0 %; grains B and C
  are matrix. Density 2 420 /µm² and 1 210 /µm². With [0 1 0] alone it was also 6 end-on
  objects, the needles not indexed, and 2 450 /µm², checked by hand: 6 / (9 792 × 0,25 nm²).
- **A2 (known variants, guard on, β″ [0 1 0] only): HELD.** Grain B (Al [011]) is labelled
  β″, 25 % of the scan, and is one object touching the edge (so not counted); grain C is not
  indexed (23 %). The 9 counted objects are the 6 end-on plus the 3 needles, labelled as the
  one β″ class. The rule is not fit for a multi-grain matrix.

### B — the real cube (`Al_Mg_Si_060…bin_4`, 330 × 330, 64 × 64 detector)

Origin measured (r 2,5 px, RMS 0,057 px). Q 0,045741 Å⁻¹ and R 1,539 nm per pixel, both from
the file. The app showed "Pair radius is 0.44 of one detector pixel … will match nothing"
before any run. "Scale to This Detector" set 0,046 / 0,046 / 0,034 Å⁻¹. Phases: Al (matrix)
and β″ at [0 1 0] and [0 0 1].

- **B1: HELD.** Find Matrix Zone Axis gives [−1 0 1] ⟨110⟩ at 10 % of vectors (unscaled), and
  [−1 1 0] ⟨110⟩ at 43 % once scaled (09-12: 39 %).
- **B2: FAILED at both floors.**

  | floor | peaks (median per pattern) | matrix | β″ [010] | β″ [001] | not indexed | matrix evidence (median) |
  |---|---|---|---|---|---|---|
  | 0,15 % | 1 010 514 (9, range 9–18) | 0,7 % | 27,1 % | 16,6 % | 55,7 % | 33 % |
  | 0,5 % | 802 752 (7, range 5–13) | 2,2 % | 19,6 % | 13,5 % | 64,7 % | 80 % |

- **B3: FAILED, the pre-registered "not reasonable" case.** β″ is speckle at both floors:
  3 135 + 3 018 objects (0,15 %) and 3 397 + 2 822 (0,5 %), median length 3,08 nm = 2 px,
  and the map is salt-and-pepper. The chance match is 3,9 % at the scaled radius.

**Reading, without a mechanism claimed:** Al is found (⟨110⟩, 43 % of vectors at one
orientation), but a typical pattern leaves about 4 of 6 detected peaks unexplained by that
single global orientation. They survive matrix removal and a dense β″ library absorbs them, so
matrix almost never wins. Raising the floor raised matrix evidence (33 → 80 %) but not the
matrix fraction. **A different Al CIF cannot help:** 4,04 vs 4,0495 Å is about 0,003 Å⁻¹ at
the outer reflections, inside a 0,046 Å⁻¹ tolerance. Open, for a Gate D: (1) does the Al
orientation vary across the scan (bending, grains)? The app's own ACOM on Al is the cheap
discriminator. (2) Are the unexplained peaks disks or maxima of the synthetic kernel (overlay
the Al template, a measured kernel, the ellipse fit)? (3) With the beam on ⟨110⟩Al, no β″ is
viewed down a low-index axis, so the β″ library itself is the wrong question until (1) and
(2) are answered.
