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

*(Written after the drives.)*
