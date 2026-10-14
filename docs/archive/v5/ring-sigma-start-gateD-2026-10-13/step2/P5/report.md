# Lane P5 report: ring-fit Gate D, step 2, real Au mean pattern (2026-10-14)

Record: docs/archive/v5/ring-sigma-start-gateD-2026-10-13.md (step 2 amendment, registered at e402373b before any step-2 run).
Variants: head (HEAD 5ddec30d, EllipseCalibration.head.swift), a (half-maximum ring-sigma start), b (refuse a ring sigma
<= 0.30 px), ab (both). Patches are held, not applied to the repo. Harness: $SP/lanes/P5/main.swift, built by
harness/build.sh into $SP/lanes/P5/bin-<v> (one binary per variant).

Input: $SP/au/au_mean.f32 (64 x 64 float32 LE, row-major, mean of all 63 550 patterns of
Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5, computed by $SP/au/meanpat.py). Load as
DiffractionPattern(qy: 64, qx: 64, pixels:), centerQX = row, centerQY = column. Centre guess for all annuli:
row 28.47, column 34.43. Annuli (inner, outer, px): [5,13], [13,21], [21,30], [30,38], and each widened by 1 px on both
sides: [4,14], [12,22], [20,31], [29,39].

## Registered prediction P5 (verbatim, written before any P5 run)

REGISTERED PREDICTION P5 (write it verbatim into $SP/lanes/P5/report.md before running): "on the mean pattern of
Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5 (polycrystalline Au rings), HEAD and candidate (a) choose the same
model on each ring annulus tried and agree to 0.01 px and 1e-3 rad."

P5 wording as registered in the record: "P5, real data: on the mean pattern of `Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5`
(polycrystalline Au rings), HEAD and candidate (a) choose the same model on each ring annulus tried and agree to 0.01 px
and 1e-3 rad."

No other prediction is registered for this lane. b and ab are information only.

## Method (what was run)

- Harness: $SP/lanes/P5/main.swift. Per annulus: fit1D(maximumResidual: 0.4) and fitBestAvailable (default arguments),
  built four times by harness/build.sh (head, a, b, ab) into $SP/lanes/P5/bin-<v>, run on au_mean.f32, logs in logs/<v>.log
  (build logs in logs/build-<v>.log; all four builds exit 0). Numbers printed with %.9g.
- The verdict uses only the fitBestAvailable (default-argument) lines. The acceptSparseCoverage run is printed only when the
  default call throws insufficientAngularCoverage; that never happened here (occupied bins 31 to 36 of 36; the degeneracy
  bound is 30), so no INFO-ONLY line exists in any log.
- Input check: 4096 finite values, min 36.5777779, max 147709.875 (logs/head.log header line). Centre passed as
  centerQX = 28.47 (row), centerQY = 34.43 (column).
- Diagnostic only (not a verdict input): a copy of the candidate-(a) file with one stderr line per fitAmorphousRing
  call, in $SP/lanes/P5/dbg/ (build-dbg.sh, out.log, err.log). Its stdout is byte-identical to logs/a.log (checked with cmp),
  so the trace describes the same run. It shows which annuli candidate (a) actually changed.
- compare.py and tables.py (in $SP/lanes/P5/) generate the tables below from the logs; nothing is transcribed by hand.

## Candidate (a) start actually used (from dbg/err.log)

| annulus | half-maximum ring-sigma start (px) | HEAD start (px) | effect of (a) |
|---|---|---|---|
| A1 5-13 | 1.35117 | 2.0 | start changed; output identical to 9 digits |
| A2 13-21 | 1.87075 | 2.0 | start changed; output moves by about 1e-5 px |
| A3 21-30 | nil (no crossing on both sides) | 2.25 | HEAD's start used |
| A4 30-38 | nil | 2.0 | HEAD's start used |
| W2 12-22 | nil | 2.5 | HEAD's start used |
| W3 20-31 | nil | 2.75 | HEAD's start used |
| W4 29-39 | nil | 2.5 | HEAD's start used |
| W1 4-14 | not reached | - | refused at the conic stage (see below) |

## Results per annulus, HEAD (fitBestAvailable, default arguments; the fit1D seed is in the second column)

| annulus | fit1D seed: model, residual, b/a | head fitBestAvailable: model | a (px) | b (px) | b/a | theta (rad) | centre row, col (px) | dist from guess (px) | normalizedResidual | occupied bins |
|---|---|---|---|---|---|---|---|---|---|---|
| A1:5-13 | conic, 0.375697306, 0.9900 | profile | 10.422237 | 10.122452 | 0.9712 | 2.44430 | (30.0049, 33.7270) | 1.69 | 0.115695341 | 36 |
| A2:13-21 | conic, 0.223694909, 0.9781 | profile | 17.863104 | 17.357863 | 0.9717 | 1.61008 | (29.8534, 33.6822) | 1.57 | 0.125026031 | 36 |
| A3:21-30 | conic, 0.193510411, 0.9699 | profile | 24.971826 | 24.558360 | 0.9834 | 2.10457 | (30.1765, 33.7491) | 1.84 | 0.0551157691 | 36 |
| A4:30-38 | conic, 0.124340376, 0.9974 | profile | 39.015624 | 36.515667 | 0.9359 | 2.41449 | (29.9250, 33.8603) | 1.56 | 0.103413695 | 31 |
| W1:4-14 | threw, resid -, refused | THREW excessiveResidual(0.42733626730998897) | - | - | - | - | - | - | - | - |
| W2:12-22 | conic, 0.293540479, 0.9790 | profile | 16.983985 | 16.722431 | 0.9846 | 2.25712 | (30.1554, 33.5883) | 1.88 | 0.0946845833 | 36 |
| W3:20-31 | conic, 0.239385955, 0.9854 | profile | 25.801106 | 25.346435 | 0.9824 | 1.93558 | (30.1371, 33.7363) | 1.81 | 0.0572061374 | 36 |
| W4:29-39 | conic, 0.154301392, 0.9855 | profile | 57.624637 | 55.000677 | 0.9545 | 2.04103 | (30.0862, 33.9153) | 1.70 | 0.0784186319 | 32 |

Head profile parameters (fitBestAvailable, default arguments):

| annulus | I0 | I1 | centralSigma | innerSigma | outerSigma | background | flags |
|---|---|---|---|---|---|---|---|
| A1:5-13 | 328069.092 | 68021.155 | 2.80453329 | 1.70240704 | 1.35486524 | 25042.1759 | none |
| A2:13-21 | 738549.375 | 35990.6504 | 0.25 | 4.30395321 | 2.04792739 | 10790.5815 | I0 at intensityLimit 5 x global max; centralSigma at 0.25 floor |
| A3:21-30 | 738549.375 | 14874.0666 | 7.7570018 | 1.06791854 | 4.88847117 | -453.820391 | I0 at intensityLimit 5 x global max |
| A4:30-38 | 16616.3651 | 0 | 19.192679 | 0.25 | 5.09830126 | 3657.02259 | innerSigma at 0.25 floor; I1 = 0 |
| W2:12-22 | 738549.375 | 43804.0055 | 5.08407342 | 1.63255178 | 3.25700438 | 2656.64733 | I0 at intensityLimit 5 x global max |
| W3:20-31 | 358146.44 | 27661.472 | 10.0355322 | 1.78631812 | 62 | -23027.1146 | outerSigma at 2 x outer |
| W4:29-39 | 156421.663 | 5830.57059 | 10.8846873 | 78 | 1.75500026 | -103.092866 | innerSigma at 2 x outer |

Differences from head (fitBestAvailable, default arguments; theta difference mod pi, meaningful here because every head b/a differs from 1 by more than 1e-3):

| annulus | variant | model | model same | abs da (px) | abs db (px) | centre distance (px) | abs dtheta (rad) |
|---|---|---|---|---|---|---|---|
| A1:5-13 | a | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A2:13-21 | a | profile -> profile | yes | 1.01e-05 | 9.4e-06 | 7.28e-07 | 1.67e-06 |
| A3:21-30 | a | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A4:30-38 | a | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W1:4-14 | a | refused (head and a) | yes | - | - | - | - |
| W2:12-22 | a | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W3:20-31 | a | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W4:29-39 | a | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A1:5-13 | b | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A2:13-21 | b | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A3:21-30 | b | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A4:30-38 | b | profile -> conic | NO | 5.67 | 3.26 | 1.15 | 1.34 |
| W1:4-14 | b | refused (head and b) | yes | - | - | - | - |
| W2:12-22 | b | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W3:20-31 | b | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W4:29-39 | b | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A1:5-13 | ab | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A2:13-21 | ab | profile -> profile | yes | 1.01e-05 | 9.4e-06 | 7.28e-07 | 1.67e-06 |
| A3:21-30 | ab | profile -> profile | yes | 0 | 0 | 0 | 0 |
| A4:30-38 | ab | profile -> conic | NO | 5.67 | 3.26 | 1.15 | 1.34 |
| W1:4-14 | ab | refused (head and ab) | yes | - | - | - | - |
| W2:12-22 | ab | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W3:20-31 | ab | profile -> profile | yes | 0 | 0 | 0 | 0 |
| W4:29-39 | ab | profile -> profile | yes | 0 | 0 | 0 | 0 |

## Verdict for P5 (candidate a, registered)

HELD, as registered, on the wording "same model on each ring annulus tried, agree to 0.01 px and 1e-3 rad".

- Model: the same on all eight annuli. Seven annuli give a profile fit on HEAD and on (a). W1 [4,14] is refused by both
  with excessiveResidual(0.4273) at the conic stage, so no profile step runs there. Both refuse the same way, so this
  agreement is by outcome, not by a fit.
- Worst differences of (a) from HEAD: |da| = 1.01e-05 px, |db| = 9.4e-06 px, centre distance 7.3e-07 px, |dtheta| =
  1.67e-06 rad, all on A2 [13,21]. Every other annulus is bit-identical to 9 significant digits.
- Thin coverage, stated plainly: (a)'s new start is used on two of the eight annuli (A1 and A2). On the other five that
  reached the profile stage the helper returned nil, so HEAD's start ran, and "agreement" there holds by construction, not
  as evidence about (a). The theta comparison is meaningful on every annulus: every HEAD b/a differs from 1 by at
  least 0.015 (the closest is W2, 0.9846).

## Verdict for b and ab (information only, not registered)

- b: changes one annulus, A4 [30,38]. HEAD's profile (ring sigma at 0.25 px floor, I1 = 0) is refused with
  ringWidthAtFloor, and the conic fallback is returned: |da| 5.67 px, |db| 3.26 px, centre 1.15 px, |dtheta| 1.34 rad.
  The other seven annuli are identical to HEAD.
- ab: identical to b on A4, and identical to (a) on A2 (the 1e-5 px movement). So ab = b plus (a)'s A2 effect.
- Whether the conic (b/a 0.997, theta 0.61 rad) is the right answer on A4 is not decided here: there is no truth, and a
  near-circular conic has a weakly determined theta.

## Odd things seen on HEAD (for the owner and for the diagnosis, not decided here)

1. A4 [30,38] is the record's dead-ring signature on real data. HEAD accepts the profile fit (normalizedResidual 0.103,
   under the 0.22 cap) with I1 = 0 and innerSigma at the 0.25 floor: the model is a broad central blob (centralSigma 19.2 px)
   plus a constant, so a, b and theta carry no ring information. Candidate (a) does not change it, because its start is
   nil there and HEAD's start runs. Candidate (b) refuses it.
2. W4 [29,39]: HEAD's profile gives a = 57.6 px, b = 55.0 px, with innerSigma at its upper bound 78 = 2 x 39 px. The conic
   gives 33.0 and 32.6 px. The fitted ring lies outside the annulus and is accepted (normalizedResidual 0.078). Neither
   (a) nor (b) changes it: (b) tests the lower floor only.
3. W3 [20,31]: outerSigma at its upper bound 62 = 2 x 31 px; accepted (normalizedResidual 0.057).
4. I0 pinned at intensityLimit = 5 x global max = 738549.375 (A2, A3, W2): the central Gaussian is railing against its bound.
   A2 also has centralSigma at its 0.25 px floor.
5. Centre drift: every HEAD profile centre sits about 1.6 to 1.9 px from the guess (28.47, 34.43), at about (30.0, 33.7).
   The conic seeds sit within about 0.8 px of the guess. Which centre is right is not decided here.
6. Anisotropy: conic seeds give b/a 0.970 to 0.997; HEAD's profile fits give 0.936 to 0.985. A polycrystalline cubic
   specimen should give near-isotropic rings, so this is either real or an artefact of the beam stop and wire. Not decided here.
7. A1 [5,13]: the conic seed residual is 0.376, above the 0.2 publication cap. The profile route (residual 0.116) is what
   gets published; that is the design, but it means HEAD's answer here does not rest on a conic that passed the cap.

## Not run

- No run on other data, no truth comparison, no sparse-coverage run (not needed: no coverage refusal occurred).
- No repo change, no application build, no drive, no push. The held patches were not applied to the repo.
- The P5 prediction was written into this file before main.swift was built and run (file order: report.md, then main.swift,
  then the four builds and runs).
