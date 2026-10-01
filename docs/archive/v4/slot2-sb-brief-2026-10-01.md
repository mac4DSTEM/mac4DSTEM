# Lane SB — row 1 + sub-bin azimuth deposition (owner: card row 1, option b, 2026-10-01)
Gate D (moves scientific numbers) → independent refuter after. Release v4.1.0.

## Diagnosis (established by the F-A refuter, docs/archive/v4/slot2-fa-refuter-2026-10-01.md)
`OrientationPlan.buildPolar` (mac4DSTEM/Core/Crystal/OrientationPlan.swift:262) deposits each spot's azimuth to the
NEAREST bin, for templates and experiment alike. py4DSTEM keeps sub-bin position:
- templates: linear interpolation between floor and floor+1 (References/py4DSTEM-dev/.../crystal_ACOM.py:800-818);
- experiment: a Gaussian evaluated at the EXACT qphi, in arc length (Δφ·radius) with sigma = orientation_kernel_size (:1046-1080).
Rounding discards up to half a bin (1.4° at 128 bins); the row-1 mirror pass doubles the candidates and the quantisation
penalty then beats the Friedel penalty → 15 Au sampled trials fall into the half-turn class (acom-convention-test 116 < 120).
Refuting observation already in hand: nAzimuthal 512 at the same 4.2° blur → regression 15 → 5 (q.log).

## Change
Row 1 (mirror pass) is applied in the tree (from docs/archive/v4/slot2-fa-row1-mirror-pass-2026-10-01.patch) — keep it.
Add: sub-bin deposition in buildPolar — template path linear interpolation in azimuth; experiment path the azimuthal
Gaussian at the exact azimuth (sigma = the existing azimBlurBins, in bins, wrapped) instead of nearest-bin-then-blur, OR,
if templates and experiment share one call site with no way to tell them apart, linear interpolation for both followed by
the existing blur — choose after reading the call sites and say which and why (DEVIATION note where it differs from py4DSTEM).
radialKernel path: keep its radial spread, deposit azimuth sub-bin there too. Also FitOverlays.swift:226: draw a mirrored
win's template mirrored (azimuth π − (azim + angle); verify the sign against the matcher's mirrored convention).
Check whether any Metal kernel or other code builds a polar image with nearest-bin azimuth (grep) and treat it the same.

## Predictions (written 2026-10-01 before any run; never edited — amendments are new dated lines)
P1 tools/acom-convention-test EXIT 0: Au sampled in-plane < 20° ≥ 120 (proxy says ≈ 130 of 144); HEAD-without-row-1 was 131.
P2 tools/acom-mirror-test: mirror-zone wrong ≤ 3 of 93 (row 1 alone: 3); sampled ≤ 9 of 107.
P3 Off-grid self-recovery (S20 class, demo cube / FA grainb sweep): failures at off-grid in-plane angles drop sharply;
   grain B of the demo cube (truth.json; head 6.50°, winner t84) moves toward t1 — predict < 3°, not necessarily exact.
P4 On-grid synthetic cases unchanged (exact before and after).
P5 Runtime of buildPolar ≤ 1.5× (two deposits or a short Gaussian loop per spot); matcher cost unchanged.
If P1 fails, do NOT re-pin; report the number.
