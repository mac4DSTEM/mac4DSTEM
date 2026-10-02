# Lane D report (Gate D) — 2026-10-02
## Summary
Preview real space is black because the graphene cube's patterns are each normalised to unit sum, so "total detector intensity per position" is constant (1 ± 1e-8); Float(total) rounds all to 1.0, span = 0, normalized() returns 0 everywhere. Display code is fine; the quantity has no contrast.
Fix: in DatasetPreviewBuilder.make, when the total is constant (relative span < 1e-5), the real-space image uses a central detector window sum instead, and summary says so. Preview-only; nothing stored/exported.

## Diagnosis (Gate D)
1. Claim: preview real-space image is solid black on twisted_bilayer_graphene.hdf5.
2. Reproduction ($SP/D/repro.py -> repro.log, repro2.log, repro3.log; py4dstem env python, h5py present): file = ds (101,101,128,128) float64. Swift stride: byteBudget 64 MiB / (128*128*4) = 1024 affordable, 10201 total -> step ceil(sqrt(9.96)) = 4 -> 26x26 sample. Per-position sum, Double accumulate then Float: min 1.0 max 1.0 (float32), 0 non-finite, p1/50/99 = 1/1/1; (v-lo)/span is 0/0 -> NaN in numpy; in Swift guard span>0 fails -> every pixel 0.0 = black. In float64 the spread is 1.26e-8 (repro2.log), below float32 resolution (6e-8) so it cannot be recovered by stretching: the sum is 1 by construction (pattern0 sum 0.99999999813, repro.log).
3. Candidates: (a) colormap/display window stale or gamma -> refuted: the preview value array is itself constant (above), a display cannot show contrast that is not there; (b) one outlier hot pixel stretching the span -> refuted: min = max, 0 non-finite; (c) pre-normalised data (patterns unit-sum) -> SURVIVES, confirmed by pattern0 sum = 1 and ds max 5.8e-4 (repro.log); (d) the drive's "0.9955-0.9994" is not the preview total (that is 1.0 exactly): a central 64x64 window sum on the same sample is 0.9978-0.9999 (repro3.log), i.e. the number the drive read is probably another readout; unresolved, immaterial to the mechanism.
   Central window sums do carry contrast: 32 px side rel. span 0.065, 16 px 0.154, 8 px 0.21 (repro3.log).
4. Prediction of fix: graphene preview shows a gray image with full-range contrast; a cube with non-constant totals (demo cube) is bit-identical to before.
5. Fix: DatasetPreview.swift only (builder + summary). 6. Test: PolishDTests.

## Predictions (2026-10-02, before runs)
- Run 1 (fixed code, PolishDTests): 2 tests green (EXIT=0).
- Run 2 (mutation: constantTotal forced false): testUnitSumPatternsGetAViewableCentralWindowImage RED (realSpaceIsCentralWindow false; EXIT=65), the other green.
- Run 3 (reverted): green.

## Changes
- Core/Analysis/DatasetPreview.swift: builder accumulates total (Double) and a central-window sum (middle eighth of each detector axis); if total's spread <= 1e-5*mean the image is the central window, `realSpaceIsCentralWindow` = true and `summary` appends " · real space: central detector window (total intensity is constant)". Otherwise bit-identical to before (Float(total)). New init param defaulted, PromotionCommitTests caller unchanged. DEVIATION note inline. PendingLoad.swift not touched (it calls normalized() on preview.realSpace, so is fixed through the data).
## Tests (new file mac4DSTEMTests/PolishDTests.swift; folder is file-system-synchronized, no pbxproj edit)
- testUnitSumPatternsGetAViewableCentralWindowImage: mutation `constantTotal = false && ...` -> RED EXIT=65 (test-2.log, this test failed, other passed); reverted -> GREEN EXIT=0 (test-3.log).
- testAVaryingTotalIsStillTheTotal: pins no behaviour change for non-constant totals.
## Runs
- test-1.log: PolishDTests + DatasetPreviewTests EXIT=0 (a first run failed to compile, duplicate `mean`; fixed). test-2 RED 65, test-3 GREEN 0. core.log EXIT=0, inv.log EXIT=0. Full build is covered by the test build (EXIT=0). Predictions held.
## Measurements: see repro.log / repro2.log / repro3.log (numbers quoted in Diagnosis).
## Deviations from brief: none; PendingLoad.swift needed no change. Unverified on screen (never launched the app); the 16 px central window on graphene gives rel. span 0.15 in python (repro3.log), not run through Swift on the real file.
## Proposed doc lines
- open-items: close "preview real space black on graphene" (cause: unit-sum patterns -> constant total; fixed by central-window fallback, labelled in summary). Status: unverified on screen.
## Open questions for supervisor
- The drive's "0.9955-0.9994" did not reproduce as the preview total (1.0 exactly); it resembles a 64x64 central-window sum (0.9978-0.9999). Source of that Info number unidentified.
- Window size (1/8 per axis) and 1e-5 threshold are my choices; confirm or adjust. Refuter should check the claim that data is unit-sum per pattern.
## git status --short (my files)
 M mac4DSTEM/Core/Analysis/DatasetPreview.swift
?? mac4DSTEMTests/PolishDTests.swift

## Corrections (refuter) — 2026-10-02
Predictions (before runs): run A (all fixes) PolishDTests 4 tests green EXIT=0. Mutation 1 (constantTotal forced false) -> testConstantTotals... and testRoundingLevel... RED, EXIT=65. Mutation 2 (disk moved to detector corner: index filter uses dx=index%qx, dy=index/qx without centring, i.e. centre (0,0)) -> testConstantTotals... RED (argmax 0 not 15) EXIT=65. Mutation 3 (bound without the factor, spread <= 0) -> testRoundingLevel... RED. All reverted -> green EXIT=0.
Results (predictions held): testB-1.log EXIT=0 (first attempt failed to build on another lane's ProductDataExport.swift missing import, then fixed by that lane; rerun green); mutation1 forced-false RED 65 (2 tests); mutation2 disk at detector corner RED 65 (testConstantTotals... argmax); mutation3 bound=0 RED 65 (testRoundingLevel...); revert -> testB-green.log EXIT=0 (4 PolishD + DatasetPreviewTests). core2.log / inv2.log EXIT=0.
Applied: M1 bound spread <= 2*2^-24*max sum|p| (DEVIATION comment says why); M2 disk = circle at (qx/2,qy/2), r=min(qx,qy)/4 via new Core func defaultBrightFieldRadius (comment names AppState+Open ~428 as the twin; that file is outside my write-set, so two sites, each naming the other — the AppState+Open side still needs a comment/use by the supervisor); M3 summary " · real space: bright-field disk sum (each pattern's total is constant)"; flag renamed realSpaceIsBrightFieldDisk; M4 argmax==15 and exact 16/128 assertion; M5 exact-dyadic constant fixture, 1-ulp (true) and 4-ulp (false) boundary tests.
Display-only consequence: PendingLoad.fetchDefaultSingleDP picks the brightest preview pixel; on unit-sum data this was (0,0) (all equal), now the brightest bright-field-disk position. State in the commit.
Out of scope note from refuter: default annulus inner 0 excludes the exact centre pixel (fillRadial strict r2 > rIn2); my disk includes it (<=), so it is not literally the same pixels as the virtual-detector pane. Suggest one open-items line.
Files: M mac4DSTEM/Core/Analysis/DatasetPreview.swift ; ?? mac4DSTEMTests/PolishDTests.swift
