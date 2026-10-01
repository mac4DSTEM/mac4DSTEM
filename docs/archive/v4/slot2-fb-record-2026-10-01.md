# Lane F-B report (rows 9, 29, 24, 6) — started 2026-10-01
## Summary
All four rows reproduced red on HEAD (test-1.log), fixed, green (test-3.log, test-5.log EXIT=0), re-broken by reverting only the fixes (test-4.log: the 7 predicted tests red), core and inventory exit 0.
Row 9: one-token wrap fix on both axes. Row 29: one predicate (a>0, b>0, finite) feeding hasEllipse, readiness and both importers; a>=b NOT imposed on import (py4DSTEM _transform has no ordering).
Row 24: non-finite pixels median-filled in the Metal origin kernel and in FriedelOrigin; Row 6: MP importer runs verifyFamily (R-3m now refused like the CIF importer).

## Diagnosis (Gate D) — claims restated, candidates, refutations
Row 9. Claim: MatrixDFTCorrelation wraps the frequency as k < N/2 ? k : k-N; numpy/py4DSTEM (multicorr.py:186,195) use
ifftshift(arange(N)) - floor(N/2), whose middle bin on odd N is +(N-1)/2. Candidate causes of a wrong sub-pixel peak on odd axes: (a) the wrap
(this row); (b) the parabolic initial estimate; (c) the half-pixel rounding. Refuting observation for b, c: they are identical on even axes, and
an even-axis control (14x12) in the same fixture must pass on HEAD. Independent 1-D emulation (disk-detector env numpy, 2026-10-01): true shift
2.3, u=16: buggy wrap reads 2.1875 (N=11, N=13), correct wrap reads 2.3125 (grid 1/16) => the wrap alone moves the peak by 0.125 px.
Row 29. Claim: hasEllipse accepts b<=0 and a<0; readiness requires a>0&&b>0; correction applies e=b/a<=0 while the row reads "Not set".
Candidates: only hasEllipse differs from the readiness predicate; manual entry already refuses. Refutation of "importers are fine": H5Reader:815
and BraggVectorEMDWriter:961 adopt raw. a>=b: py4DSTEM's braggvectors._transform uses e=b/a with no ordering (braggvectors.py:505-507),
so a<b file ellipses are exactly corrected -> NOT refused on import (deviation from the row's "and a>=b"; manual entry keeps it).
Row 24. Claim: non-finite pixels displace the coarse seed (s > bestSum false for NaN), stop the refine (!(sumI>0) break), and poison Friedel.
Row 6. Claim: MP importer never runs verifyFamily; the R-3m test pins .hexagonal (wrong).

## Predictions (dated, before each run)
2026-10-01 RED run on HEAD (test files only, no fix): classes MatrixDFTCorrelationRow9Tests, CalibrationEllipseRow29Tests, OriginNonFiniteRow24Tests,
MaterialsProjectImportRow6Tests, MaterialsProjectImportTests.
- Row9: testRow9OddAxes... FAILS (odd-axis peak off by ~0.1 px > 0.03 tol); testRow9EvenAxesControl PASSES.
- Row29: testRow29NonPositiveAxes... FAILS (hasEllipse true for b<=0 / a<0); ValidEllipse and SemiMinorFirst PASS.
- Row24: Metal test FAILS (NaN in beam block: seed leaves the beam, origin far from clean ~ (2.5,2.5) block centre); Friedel test FAILS (NaN result).
- Row6: Pa-3 test FAILS (no throw on HEAD, returns .cubic); Genuine hexagonal PASSES; testRhombohedral...(re-pinned to throw) FAILS on HEAD.

## Runs (1) RED on HEAD — 2026-10-01
cmd: xcodebuild test ... -only-testing: Row9/Row29/Row24/Row6 classes + MaterialsProjectImportTests; log FB/test-1.log; EXIT=65; failure texts FB/red1-messages.txt.
Result vs predictions: all predicted failures red, all predicted controls green (Row9 even control, Row6 genuine hexagonal, Row29 valid + semi-minor-first).
Numbers: Row9 odd axes: row 2.1813 (13x11) / 2.1754 (14x11) for true 2.3 (tol 0.03); column 3.675 / 3.677 for true 3.6 — the 0.1 px
error the 1-D emulation predicted. Row29: a 19.5,b 0 / b -17.9 / a -19.5 give hasEllipse true and a corrected vector (3,4)->(1.11,-0.47) etc.
Row6: Pa-3 returns without throwing; re-pinned R-3m test: "did not throw". Row24 Friedel: NaN result. Row24 Metal: PREDICTION PARTLY REFUTED —
I predicted the seed would jump to the corner block; measured: the NaN pixel's block loses to a neighbouring block and the windowed CoM (max(NaN,0)=0)
converges 0.0034 px (x) / 0.0040 px (y) from the clean run; an Inf pixel gives NaN (inf sum wins the block, CoM sums inf). The defect is real but,
for one NaN in a plateau beam, tiny; the Inf case is the large one.

## Predictions 2026-10-01 (before run 2, fixes applied)
Run 2 = same 5 classes + CalibrationEllipseRow29 acceptedEllipse test + neighbours (ManualEllipseTests, CalibrationDisclosureTests, CalibrationReReferenceTests,
FitOverlayPresentationTests, ProbeSizeTests, MaterialsProjectSessionTests, DiskDetectionContractTests). Prediction: everything GREEN. Specifically
Row9 odd axes within 0.03 of (2.3, 3.6) (emulation says 1/16-grid value 2.3125, error 0.0125); Row24 Metal dirty == clean to 1e-4 (the NaN sits among 100-valued
neighbours so the median fill is exactly 100); Friedel dirty == clean to 1e-4 (same argument); Row6 throws .symmetryNotSupportedByStructure for R-3m Bi
(6-fold about c maps the R lattice to the reverse setting, no translation restores it) and Pa-3 (cubic), Mg stays hexagonal; no neighbour moves.
Risk: another MaterialsProjectImportTests fixture with a sloppy synthetic site set could start throwing (would be a finding, not silently fixed).

## Run 2 result (log FB/test-2.log, EXIT=65): 116 passed, 1 failed — all four rows' new tests + all neighbours green; the ONE failure is the risk I named:
MaterialsProjectSessionTests.testFetchReturnsMismatchForTheLiAl2CuVsT1Case — its fixture is four atoms (Li, 2 Al, Cu) in a cubic box with
Fm-3m written on it: no 3-fold axis, so verifyFamily correctly refuses it ("no 3-fold axis along <111>"). A synthetic-fixture defect the old
importer could not see; not a product regression. Fix is the fixture: replaced by the real Heusler Fm-3m cell (Li 4a, Cu 4b, Al 8c, a = 6.0 A).
Prediction for run 3 (2026-10-01): same set, all 117+ pass (the mismatch verdict still comes from space group 225 vs 191).

## Run 3 (log FB/test-3.log) EXIT=0 — the 12-class set, all green (prediction held).
## Mutation run 4, 2026-10-01 — prediction: reverting JUST each fix turns its tests red again, all five at once:
Row9 wrap back to `< N/2` (odd-axis test red, even control green); Row29 predicate back to abs(a)>min && no b>0 (NonPositiveAxes + acceptedEllipse red);
Row24 Metal pixelFilled returns raw (Metal test red) and Friedel finite() returns the raw pattern (Friedel test red); Row6 verifyFamily call removed
(Pa-3 + re-pinned R-3m red, MP Session LiAl2Cu fixture stays green). Classes: Row9, Row29, Row24, Row6, MaterialsProjectImportTests.
Run 4 result (log FB/test-4.log, EXIT=65): exactly the seven predicted tests red (Rhombohedral re-pin, Row24 x2, Row29 x2, Row6 Pa-3, Row9 odd); even control, genuine-hexagonal, valid-ellipse, semi-minor-first stayed green. Fixes restored (cmp against backups: same).
Prediction run 5 (final, fixes restored, 12-class set): EXIT=0.

## Run 5 (log FB/test-5.log) EXIT=0, 12 classes green after restore. core: FB/core.log exit 0; inventory: FB/inv.log exit 0 (echoed on their own lines).

## Changes
- Core/Compute/MatrixDFTCorrelation.swift: wrap `< (N+1)/2` on both axes (numpy ifftshift form, py4DSTEM multicorr.py:186,195).
- Core/Data/Calibration.swift: `acceptedEllipse(a:b:theta:)` is the one predicate; hasEllipse uses it; the readiness row's duplicate a>0/b>0 dropped.
- Core/Data/H5Reader.swift, BraggVectorEMDWriter.swift: ellipse adopted only through acceptedEllipse (a bad triple is refused whole).
- Shaders/OriginMeasure.metal: pixelFilled() (bit-test non-finite, median of finite 8-neighbours, 0 if none) in the coarse block sums and the CoM window. Param struct untouched.
- Core/Analysis/FriedelOrigin.swift: finite() sanitises the pattern in both origin entries (rule restated, not called, so tools/lib/sources.manifest friedel group still compiles without DiskDetection.swift).
- Core/Crystal/CIFImport.swift: verifyFamily private -> package. Core/Crystal/MaterialsProjectImport.swift: verifyFamily after classifyFamily, coarsestHalfStep 0.
- Tests: new MatrixDFTCorrelationRow9Tests, CalibrationEllipseRow29Tests, OriginNonFiniteRow24Tests, MaterialsProjectImportRow6Tests; MaterialsProjectImportTests R-3m re-pinned (hexagonal -> throws symmetryNotSupportedByStructure, reason in the comment); MaterialsProjectSessionTests LiAl2Cu fixture replaced with a real Heusler Fm-3m cell (old one had no 3-fold axis).

## Measurements / does a shipped number move
- Row 9: for EVEN axes the wrap is bit-identical (k < N/2 == k < (N+1)/2), so every even-detector multicorr result is unchanged. Only odd axes move (odd detector or odd crop reaching multicorrRefine / ParallaxAlignment.refinedPeak). Fixture: odd-axis error was ~0.12 px (2.181 vs 2.3, test-1.log) -> within 0.03. I did not run a shipped-dataset harness; DiskDetectionContractTests green (test-5.log).
- Row 24: finite data is untouched (helper returns v). Metal fixture: one NaN in a plateau beam moved the origin only 0.0034/0.0040 px (my "corner seed" prediction was wrong, recorded above); an Inf gives NaN origin.
- Row 6: moves IPF colours / orientation reduction of any trigonal or m-3 phase fetched from MP: they are now refused with the CIF importer's message instead of imported with the wrong symmetry.

## Deviations from the brief
- Row 29: a >= b not imposed for imported ellipses (reason above); manual entry still refuses a < b.
- Row 24: "count the fills into provenance" not done (no new surface / AppState / provenance key; ADR 049) — open question below. Fill rule is the median fill, GPU-side; a non-finite pixel in the Metal path is not counted.
- Row 29 "refuse by name": the importer refuses silently (no message surface in my write-set: PixelCalibration lives in FourDDataSource.swift). Fixture covers the predicate, not an H5 round trip (no EMD fixture written).
- UI readiness row: Calibration.swift's own readiness text only; no UI file touched.

## Proposed doc lines
- status: F-B rows 9/29/24/6 fixed (Gate D, red->green->red-by-revert->green); odd-axis multicorr, ellipse predicate, non-finite origin pixels, MP verifyFamily.
- open-items: (new) origin fills are not counted in provenance (row 24 tail); (new) an imported ellipse with b<=0 is dropped silently, no message.
- plan log: MP fixtures must be real structures now (verifyFamily); R-3m trigonal phases from MP are refused.

## Open questions for the supervisor
- Want a provenance count / status line for row-24 fills and a named refusal for row-29 files? Needs files outside the write-set (FourDDataSource.swift PixelCalibration note, AppState+Open).
- tools/lib/sources.manifest: no change needed (FriedelOrigin kept self-contained). Other tools that compile OriginMeasure.metal not checked.

## git status --short (my files only; the other M/?? entries belong to other lanes)
M Core/Analysis/FriedelOrigin.swift, Core/Compute/MatrixDFTCorrelation.swift, Core/Crystal/CIFImport.swift, Core/Crystal/MaterialsProjectImport.swift, Core/Data/BraggVectorEMDWriter.swift, Core/Data/Calibration.swift, Core/Data/H5Reader.swift, Shaders/OriginMeasure.metal, mac4DSTEMTests/MaterialsProjectImportTests.swift, mac4DSTEMTests/MaterialsProjectSessionTests.swift
?? mac4DSTEMTests/CalibrationEllipseRow29Tests.swift, MaterialsProjectImportRow6Tests.swift, MatrixDFTCorrelationRow9Tests.swift, OriginNonFiniteRow24Tests.swift
