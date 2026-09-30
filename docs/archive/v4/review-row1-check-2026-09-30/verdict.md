# Row 1 — ACOM bank covers the mirror-reduced triangle only, no conjugated pass

**Verdict: REPRODUCES.** Independent re-derivation from the sources plus two numpy checks with the Swift constants
(`geom_check.py`, `matcher_check.py`, logs `geom_check.log`, `matcher_check.log`, this directory; python = ~/miniconda3/envs/py4dstem, numpy 2.5.0).
Reviewer: Fable 5.1, 2026-09-30. No repo file changed.

## 1. What the port samples and what it correlates

- `Core/Analysis/OrientationResult.swift:158-163` `CubicOrientationSymmetry.reduceDirection` takes `abs` of all three components and sorts them,
  returning `(middle, smallest, largest)` — the m-3m sector z ≥ x ≥ y ≥ 0, i.e. one of 48 triangles (three coordinate mirrors and the inversion are used).
- `:169-209` `sampleFundamentalZone(count:)`: vertices (001), (101)/√2, (111)/√3; a Fibonacci sphere folded by `reduceDirection`, then
  farthest-point selection. Ported verbatim: all 600 axes satisfy z ≥ x ≥ y ≥ 0; nearest-neighbour spacing median 1.03°, max 1.43°.
- `:415-427` hexagonal `reduceDirection`: `if value.z < 0 { value = -value }` (inversion), azimuth mod 60°, `if azimuth > .pi/6 { azimuth = .pi/3 - azimuth }`
  (mirror) → the 0–30° sector, 1/24 of the sphere. `:429-437` samples that sector.
- `:113-135` the symmetry used to REDUCE a result is the 24 proper signed permutations (`simd_determinant(candidate) > 0.5`); `:366-388` the 12 proper D6 ops.
  So results are reduced by the proper group (correct), but the bank is sampled over the improper group's zone (half the proper zone).
- `Core/Crystal/OrientationPlan.swift:121-122` `let axes = symmetry.sampleFundamentalZone(count: zoneAxisCount); let bases = axes.map(ACOMOrientation.detectorBasis)`;
  `:187-235` `project` uses `basis.columns.0/1` as (e1, e2), `spots.append((r: radius, azim: atan2(y, x), ...))`.
- `Core/Crystal/OrientationMatcher.swift:8` `corr(Δφ) = IFFT_φ( Σ_ring conj(FFT(exp_ring)) · FFT(template_ring) )`; `:141-142` "Template * conj(Experimental)";
  `:165-168` the single `vDSP_zvmul(..., -1)` pass; `:197-201` argmax over Δφ; `:203-210` `selectOrientation` → `makeOrientationResult`.
  There is no second pass on `conj(experimental)` anywhere in the file, and `grep DEVIATION` finds notes only at `:338` (runner-up rule) and in OrientationPlan (`:178, :212, :278`) — none about mirror/inversion.

## 2. What py4DSTEM does (pinned `References/py4DSTEM-dev/py4DSTEM/process/diffraction/crystal_ACOM.py`)

- `:23` `zone_axis_range: np.ndarray = np.array([[0, 1, 1], [1, 1, 1]])`, `:50-52` "If user specifies 2 vectors (2x3 array), we start at [0,0,1]";
  `:2791` `"m-3m": [[[0, 1, 1], [1, 1, 1]], None, None]`, `:2782` `"6/mmm": [[[0.5*np.sqrt(3), 0.5, 0.0], [1, 0, 0]], None, None]`.
  `:343-431` SLERP fills exactly that spherical triangle (`orientation_num_zones = (steps+1)(steps+2)/2`). So py4DSTEM's bank is ALSO the 1/48 (cubic) / 1/24 (hex) mirror-reduced triangle.
- `:877` `inversion_symmetry: bool = True,` (default of `match_orientations`), `:894` "check for inversion symmetry in the matches".
- `:1272-1323` "# Calculate orientation correlogram for inverse pattern (in-plane mirror)": `corr_full_inv = np.maximum(np.sum(np.real(np.fft.ifft(self.orientation_ref * np.conj(im_polar_fft)[None, :, :])), axis=1), 0)`
  — the same product as the forward pass at `:1233-1240` (`self.orientation_ref * im_polar_fft`) with the experimental FFT conjugated.
- `:1364-1370` per zone axis the larger of the two wins and sets `corr_inv[a0] = True`; `:1374-1383` the in-plane angle of an inverted win gets `+ np.pi`;
  `:1548-1550` `if inversion_symmetry and corr_inv[ind_best_fit]: # Rotate 180 degrees around x axis for projected x-mirroring operation / orientation_matrix[:, 1:] = -orientation_matrix[:, 1:]`;
  `:1571` `orientation.mirror[match_ind] = corr_inv[ind_best_fit]`.
  That is how py4DSTEM reaches the other half of the proper zone with a half-zone bank; the port copied the bank but not the pass.

## 3. Derivation (why one pass cannot cover it)

- Proper cubic group O has 24 elements; O_h has 48 and acts simply transitively on the 48 triangles, so O splits them into two orbits of 24.
  The sampled triangle T0 = {z ≥ x ≥ y ≥ 0} and its mirror T0' = {z ≥ y ≥ x ≥ 0} are in different orbits: no proper rotation carries a direction of T0' into T0.
  Check: `is (2,1,3) a proper image of (1,2,3)? False`; `is -(2,1,3) a proper image of (1,2,3)? True` — the proper orbit of a mirror-triangle axis contains the ANTIPODE of a sampled axis.
- `detectorBasis` (`OrientationResult.swift:91-96`) gives `basis(-n) = (-e1, e2, -n)` (verified numerically), so the pattern seen along −n is the x-mirror of the pattern along n;
  with Ewald curvature (`sg = g·n + λ|g|²/2`) the Friedel partner −g takes the same weight and lands at (−x, −y), so the −n pattern is still an exact mirror (y → −y) — the relation does not depend on `wavelengthAngstrom`, and `AppState+ACOM.swift:168-176` passes one when a voltage is known.
- A 2-D mirror equals an in-plane rotation only for patterns with a mirror line, i.e. zone axes on a {100}/{110} plane — exactly the triangle's three edges. Interior axes are chiral.
- Polar representation: mirroring sends azimuth φ → −φ, so each ring's real sequence is reversed and its DFT is conjugated, E_r(k) → conj(E_r(k)). The shipped product conj(E)·T then becomes E·T, whose inverse FFT is the circular CONVOLUTION of the ring with the template — it peaks at no Δφ unless the template is itself mirror-symmetric. py4DSTEM's conj(im_polar_fft) is precisely the extra conjugation that turns it back into a correlation against the mirrored template.

## 4. numpy results (Swift constants: FCC Al a = 4.0495 Å, kMax 1.2, 600 axes, 32×128, sgWidth 0.03, sgMax 0.1, intensity^0.25, radial kernel 0.08 Å⁻¹, blur 1.5 bins, per-ring mean removed, L2 norm, wavelength nil; Al f_e from Peng's 4-Gaussian fit — intensities only affect scores, not the chirality result)

Geometry (`geom_check.log`), exact spot-set comparison up to an in-plane rotation, `#proper` = bank templates equal to the query pattern, `#mirror` = equal to its mirror:

| query axis | d_proper (nearest template on the proper orbit) | d_full48 | #proper | #mirror |
|---|---|---|---|---|
| (2,1,3) sampled | 0.37° | 0.37° | 10 | 0 |
| (1,2,3) mirror | 10.92° | 0.37° | 0 | 10 |
| (3,1,5) sampled / (1,3,5) mirror | 0.47° / 9.75° | 0.47° / 0.47° | 1 / 0 | 0 / 3 |
| (5,2,7) sampled / (2,5,7) mirror | 0.51° / 9.47° | 0.51° / 0.51° | 10 / 0 | 0 / 10 |
| (1,1,3) edge, (1,2,2) ⟨122⟩ on {110} | 0.51°, 0.10° | same | 1, 1 | 1, 1 (achiral) |

(#proper > 1 for sampled axes is the ZOLZ tilt insensitivity: templates within ~3° project to the same spot set to 2e-3 Å⁻¹.)
4000 random directions: 50.4 % have a proper orbit that misses the bank; on that half the geometric floor on the axis error is median 4.0°, 90 % 8.9°, max 12.3° (bank itself: median 0.49°, max 1.02°).

Matcher port (`matcher_check.log`), truth = own projection rotated 17.3° in-plane, winner axis error under the proper group / after the 48-fold fold / score:

| truth | triangle | shipped forward pass | + py4DSTEM's conjugated pass |
|---|---|---|---|
| (2,1,3) | sampled | 1.25° / 1.25° / 1.000 | — |
| (1,2,3) | mirror | 19.36° / 2.43° / 0.905 | 22.18°* / 1.25° / 1.000 |
| (3,1,5) / (1,3,5) | sampled / mirror | 0.47° / 0.969 ; 14.74° / 5.03° / 0.759 | mirror: 0.47° after fold / 0.996 |
| (5,2,7) / (2,5,7) | sampled / mirror | 0.51° / 0.998 ; 17.56° / 1.12° / 0.970 | mirror: 0.51° after fold / 0.989 |
| (4,1,6) / (1,4,6) | sampled / mirror | 0.82° / 0.996 ; 12.36° / 4.23° / 0.814 | mirror: 0.82° after fold / 0.996 |
| (7,3,9) / (3,7,9) | sampled / mirror | 0.51° / 0.992 ; 17.16° / 4.27° / 0.921 | mirror: 0.51° after fold / 0.996 |

*The conjugated pass wins on the template that is the truth's mirror image; its proper-orbit distance is large by construction, which is why py4DSTEM then flips the beam to −n (`orientation_matrix[:, 1:] *= -1`, a 180° rotation about x) — −n IS on the proper orbit. 60 random truths, shipped pass: sampled-triangle half median 0.64°, 90 % 1.29°, max 1.97° (score 0.992); mirror-triangle half median 7.28°, 90 % 18.97°, max 21.87° (score 0.940). The review's 4.7–20.4° / 0.80–0.96 is reproduced in kind and in range.

Hexagonal: same structure by inspection (sector 1/24 vs D6 zone 1/12; py4DSTEM's 6/mmm range is the same 0–30° sector plus the inverted pass); not run numerically.

## 5. Consequence for a user

For a cubic (or hexagonal) phase, half of all generic beam directions — those whose 48-fold fold crosses a mirror plane, 50 % of random orientations — have no template on their proper-symmetry orbit. The shipped matcher still returns a winner (a sampled-triangle template), so nothing refuses: the zone axis is wrong by 5–22° (median ≈ 7°) with a score only modestly below a true match (0.76–0.97 vs 0.97–1.00), the Euler angles and the in-plane angle are those of that wrong template, and `secondScore`-based confidence does not flag it. Axes on the triangle edges ({100} and {110} planes: ⟨001⟩, ⟨011⟩, ⟨111⟩, ⟨112⟩, ⟨122⟩, ⟨113⟩ …) are achiral and unaffected — which is why the demo cube's three grains (`tools/demo-dataset/make_demo.py:54-58`: Al [001], [011], [111]) and the in-app demo ([001], `DemoFourDDataSource.swift:124`), the S20 probe (templates' own spots and ⟨122⟩), and the convention harness (`tools/acom-convention-test/main.swift:98`, generic axes drawn from `plan.zoneAxes`) could not see it. IPF-Z colour only partly hides it: it is computed from the 48-fold fold, so the colour of the wrong winner is off by the 48-fold distance (0.4–5° here), not the 5–22° proper-orbit error — a map can look right while every Euler triple in that half is wrong. The fix class the review names is consistent with the pinned source: add the conjugated pass and, on an inverted win, negate columns 1–2 before/after the in-plane rotation as `crystal_ACOM.py:1548-1550` does (or sample both triangles); add a `DEVIATION` note; plant mirror-triangle axes (e.g. (1,2,3), (1,3,5), (2,5,7)) in the convention harness, whose current generic set cannot go red on this.
