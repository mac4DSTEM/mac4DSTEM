# Slot 2 lane X — preprocessing export: stride, detector crop, hot-pixel filter (X2) and the 28 GB export parity (X1), 2026-10-01

The implementer's report, verbatim (Sonnet 5.5; scratch logs named here were not retained). Supervisor's gate: unit 1354 / 0 / 4 = 1358 reconciled with 1358 `func test` on an isolated HEAD + X copy (`unit-X.log`, GATE_EXIT=0), `preprocessing-export-test` exit 0, core 0, inventory 0 on the tree. The refuter's two notes were applied as comments after that gate (no code change).

# Lane X report (X2; X1 pending SSD)

## Summary
X2 done: the Preprocess & Export sheet gains scan stride, a detector crop and an optional, default-off hot-pixel filter (py4DSTEM filter_hot_pixels, mask stored in the file's provenance); proven bit-for-bit against py4DSTEM's own crop_R/thin_R/crop_Q/bin_Q/filter_hot_pixels chain in a gated harness (6 mutations red) plus 5 unit tests (5 mutations red).
X1 done: the app's export of the raw 060 DM4 at bin 4 with the filter at thresh 8 finds EXACTLY the 15 positions and matches py4DSTEM's file to <= 1.14e-4 relative at all 108 900 x 4096 values; with the filter off the same 15 positions differ by 0.27-790x. NOT bit-identical (the brief's prediction was wrong; float32 summation order, as the 09-30 record said).
Gates: build-1 EXIT=0, test-1 EXIT=0, harness-3 EXIT=0, core-4 EXIT=0, inventory-2 EXIT=0.

## Inventory (2026-10-01)
- Sheet: mac4DSTEM/UI/ExportSheet.swift ("Preprocess & Export DataCube"; form: calibration readiness, real-space crop (toggle + 4 steppers), integer Q bin stepper (sum, trim remainder = py4DSTEM bin_Q), output preview). Writes via AppState.exportCalibratedDataCube (Support/ResultExport.swift:32) -> BraggVectorEMDWriter.writeCalibratedDataCube (Core/Data), options `CalibratedDataCubeExportOptions` (scanY, scanX, qBin, tileRows) in Core/Data/BraggVectorEMDTypes.swift.
- Before X2 it offered: scan crop, Q bin (sum, float32, atomic rename, tile-bounded). No stride, no detector crop, no hot-pixel filter.
- Output: canonical py4DSTEM EMD (datacube_root/datacube/data float32, chunk [1,1,qy,qx]), calibration transformed (qSize*bin, origin (x+.5)/b-.5, probe/ellipse /bin, origin maps cropped), `DataCubeDerivation` JSON attribute (source file, scan/detector offsets, total bin) + replay recipe. Opens in the app as any h5 cube (H5Reader.discoverPrimaryDataset) and in py4DSTEM (py4DSTEM.read).
- Existing gates: tools/preprocessing-export-test (writer vs py4DSTEM read, scan crop + bin 2), tools/reduced-export-test, tools/preprocess-crop-bin-test (load-time bin). tools/dm4-parity-probe --parity compares the app's DM4 sum-bin with a py4DSTEM file (diagnostic, needs the SSD).

## py4DSTEM facts verified (References/py4DSTEM-dev, commit f050d207)
- thin_data_real preprocess.py:315-346: out = floor(R/N) per axis, positions i*N from the (already cropped) origin, R pixel size x N (l.338).
- crop_data_diffraction preprocess.py:123-136: data[:, :, Qx_min:Qx_max, Qy_min:Qy_max] (max exclusive; Qx = first detector axis).
- bin_data_diffraction preprocess.py:155+: trims remainder off the END of the (cropped) extent, then sums.
- filter_hot_pixels preprocess.py:349-460: mean over scan; 21-px neighbourhood (3x3 + arms at +-2) via np.roll (WRAPS), ind_compare=1 -> second brightest; mask = mean - that > thresh; each masked pixel replaced in row-major order, in place, by np.median of its 3x3 window CLIPPED at edges (later pixels see earlier replacements).
- Order for the owner's file: bin then filter (parity-28gb doc). Export order implemented: crop R -> stride -> crop Q -> bin -> filter.

## Changes (so far, 2026-10-01)
- Core/Data/HotPixelFilter.swift (new): py4DSTEM filter_hot_pixels port (mask from mean pattern, 21-px wrap window, clipped 3x3 median, in place row-major). DEVIATION: mean in Double.
- Core/Data/BraggVectorEMDTypes.swift: options gain scanStride, qCropY/X, hotPixelThreshold; summary gains hotPixels; DataCubeDerivation gains scan_stride / hot_pixel_threshold / hot_pixels (optional, absent when unused; detector offset now includes the export crop).
- Core/Data/BraggVectorEMDWriter.swift: crop R -> stride -> crop Q -> bin -> filter; two-pass for the filter (mean pass over exactly the exported patterns, then write); rSize x stride; origin shifted by crop offset then bin; frame net uses cropped extent.
- Support/ResultExport.swift (exportCalibratedDataCube only): recipe omitted by name when stride/crop; status line adds hot-pixel count; progress units.
- UI/ExportSheet.swift: Scan stride row, Detector crop (toggle+4 steppers), Hot pixels (toggle + threshold field); preview shape/trim use them.
- pbxproj exception list + tools/lib/sources.manifest (export group): HotPixelFilter.swift registered (outside the stated write-set, required).

## Predictions (2026-10-01, before the harness runs)
P1 harness fixture (src [6,7,12,14]; scanY 1..<6, scanX 0..<7, stride 2, qCrop rows 1..<11 cols 2..<13, bin 2, thresh 20, planted hot pixels incl. an adjacent pair, an edge pixel that only a clipped (non-wrapping) window would flag): file shape [2,3,5,5]; with filter ON: bit-identical (float32) to py4DSTEM thin_R/crop_Q/bin_Q/filter_hot_pixels(20) on the same data, mask = py4DSTEM's mask, 3 hot pixels found ([1,2],[1,3],[2,0] out frame ... edge A not flagged under wrap? see fixture), origin maps = ((v-offset)+0.5)/2-0.5 at the strided positions, R size 2.5*2. With filter OFF: bit-identical to the unfiltered py4DSTEM chain and differing from the ON file exactly at the masked positions.
- AMENDMENT 2026-10-01 (new line; P1's mask text above was muddled): the fixture's py4DSTEM mask is exactly {(1,2) hot pixel, (4,4) corner}; the adjacent dimmer pixel (1,3) is NOT flagged (second-brightest comparison); the opposite-edge pair (2,0)/(2,4) is NOT flagged because np.roll wraps (a clipped window would flag (2,0)). Prediction for `tools/preprocessing-export-test/run.sh`: exit 0, prints "native checks passed" and "stride/crop/bin/hot-pixel parity with py4DSTEM passed"; file ON == py4DSTEM chain bit for bit; ON and OFF differ at exactly (1,2),(4,4).
- AMENDMENT 2026-10-01 (run harness-1b: EXIT=133, "X2 mask []"): the 5x5 binned detector let the planted pixels shield each other through np.roll's wrap (py4DSTEM ITSELF found "No hot pixels detected" on it, checked in Python) — a fixture error, not a port error. Fixture enlarged to src [6,7,20,24], crop rows 2..<18 cols 3..<22, bin 2 -> 8x9 detector, trim 1 column. New prediction: py4DSTEM mask = {(2,3) hot, (7,8) corner}; (2,4) dimmer neighbour and the (3,0)/(3,8) opposite-edge pair unflagged; run.sh exit 0.

## Tests / mutations on tools/preprocessing-export-test (harness; mutated source, run-dbg.sh = run.sh with stderr)
Green (harness-2.log) EXIT=0 on the corrected fixture. Mutations (each applied, run, restored; cmp-verified):
| mutation | red? | log | what failed |
|---|---|---|---|
| mask window clamps instead of wrapping (np.roll) | red EXIT=133 | mut-nowrap.log | X2 mask [[2,3]] (corner lost) |
| compare with brightest (ind_compare 0) | red EXIT=133 | mut-indcompare0.log | X2 mask [] |
| even-count median not averaged | red EXIT=1 | mut-median_nonclipped_even.log | ON file != py4DSTEM chain |
| stride count ceil instead of floor | red EXIT=133 | mut-stride_ceil.log | X2 shape [3,4,8,9] |
| origin without crop-offset shift | red EXIT=1 | mut-origin_noshift.log | origin map assert_allclose |
| R pixel size not scaled by stride | red EXIT=1 | mut-rsize.log | R pixel size 5.0 |

## Predictions 2026-10-01 (before build-1 and test-1)
build-1: EXIT=0. PreprocessExportTests (5 methods): all green; each of the 5 goes red on its mutation (wrap->clamp & ind_compare->0 break test 1; `>` -> `>=` breaks test 2; even-median averaging dropped breaks test 3; ceil stride breaks test 4; dropping the new JSON keys' optionality (always encode stride) breaks test 5).

## Tests: mac4DSTEMTests/PreprocessExportTests.swift (5 methods) — result: build-1.log EXIT=0; test-1.log EXIT=0 (5/5 passed, counted from the xcresult by method name)
| test | mutation | red | log |
|---|---|---|---|
| testMaskComparesWithSecondBrightestAndWrapsAtTheEdge | window clamps instead of wrapping | red ([21] != [21,71]) | test-mutA.log EXIT=65 |
| testReplacementIsTheClipped3x3MedianInPlace | even-count median not averaged | red (6.0 != 5.5) | test-mutA.log |
| testStrideKeepsFloorOf... | stride count ceil | red ([1,4] != [1]) | test-mutA.log |
| testProvenanceNamesStrideAndMaskOnlyWhenUsed | JSON key hot_pixels renamed | red | test-mutA.log |
| testThresholdIsStrictlyGreaterThan | `>` -> `>=` | red ([14] != []) | test-mutB.log EXIT=65 |
Files restored by cmp after each run. (Prediction stated before: all five red on those mutations; held. Note test 1's own prediction said ind_compare->0 also breaks it; that mutation was exercised on the harness instead.)

## X1 predictions (2026-10-01, before any 28 GB run; the SSD is mounted, raw file 28 556 340 121 bytes confirmed)
The brief predicts bit-identical. docs/archive/v4/parity-28gb-2026-09-30.md already measured that the app's row-major float32 4x4 sum differs from numpy's in the last bits at 54 % of values (max 1.1e-4 absolute on a block spanning -145..+246; every other position <= 1.1e-4 relative at scale max(|b|,1)); the export writer accumulates in the same row-major order. So I predict NOT bit-identical:
- X1-ON (bin 4, thresh 8): MASK = exactly the 15 positions (1,12) (5,44) (7,21) (9,5) (15,37) (22,54) (25,16) (31,56) (32,32) (38,48) (42,10) (48,26) (48,51) (56,43) (61,3); PER PIXEL: every one of the 4096 positions has max relative <= ~1.1e-4 (the 15 filtered ones included, since a median selects an existing neighbour whose own rounding differs by the same last-bit amount); "bit-identical in every pattern" count well below 4096 (~ the pre-measured 54 % of values differ); no pattern differs by more than rounding.
- X1-OFF: the same 15 positions lead the per-pixel list with max relative 0.27-790 each, differing in 91 443-97 340 patterns; every other position <= 1.1e-4.
- Footprint: tens of MB (anonymous), as the 09-30 record (10 -> 22 MB); ON takes ~2 raw reads (mean pass + write pass), ~2-4 min cold each, OFF ~1.

## Runs (X1; heavy lock, one job; DM4_PROBE_RSS_LIMIT_MB=60000; raw on /Volumes/PL_SSD_2TB exFAT; reference = References/training_dataset/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5)
Command: tools/dm4-parity-probe/run.sh --export-parity "<raw 060 DM4>" "<abs ref .h5>" --bin 4 [--thresh 8]   (new mode; scratch export under $TMPDIR deleted after the compare)
| run | log | exit | export time | mask found | patterns compared / bit-identical | max abs / max rel | footprint |
|---|---|---|---|---|---|---|---|
| filter ON thresh 8 | x1-on.log / x1-on.exit | ON EXIT=0 | 171 s (2 raw passes) | 15: (1,12)(5,44)(7,21)(9,5)(15,37)(22,54)(25,16)(31,56)(32,32)(38,48)(42,10)(48,26)(48,51)(56,43)(61,3) | 108 900 / 0 | 0.3125 / 1.14e-4 | 135 MB after export, 138 MB through the compare (RSS 27 GB = mapped file pages) |
| filter OFF | x1-off.log / x1-off.exit | OFF EXIT=0 | 16 s (file cached) | none | 108 900 / 0 | 255 594 / 790 | same |
Per pixel, ON: all 4096 positions <= 1.14e-4 relative (two at 1.1e-4 in one pattern each; the 15 filtered positions are NOT outliers: a median takes an existing neighbour, whose own sum differs from numpy's only in rounding).
Per pixel, OFF: the same 15 lead (790, 763, 553, 5.32, 3.94, 3.0, 2.9, 2.8, 2.35, 2.2, 1.81, 1.74, 1.6, 1.17, 0.272), each differing in 91 443-97 340 patterns and the file equal to the 3x3 median of the app's binned raw in every one of them; every other position <= 1.14e-4. This reproduces docs/archive/v4/parity-28gb-2026-09-30.md's table, now through the export path rather than the LoadView bin.
Prediction check: mask held exactly; per-position <= ~1.1e-4 held (1.14e-4, slightly over my "~1.1e-4"); "not bit-identical" held and contradicts the brief; footprint "tens of MB" was low (135-138 MB: the 1.78 GB write tile pipeline + HDF5 chunk cache), still bounded and flat.
Gating: the 28 GB comparison stays `diagnostic` (needs the SSD); the GATED half is tools/preprocessing-export-test (scientific list), now pinning the filter/stride/crop against py4DSTEM on a fixture. (X1's "gated harness" cannot run in CI.)
Not bit-identical because the writer sums each 4x4 block row-major in float32 and numpy sums in another order. Making the export bit-identical to a numpy file would mean reproducing numpy's reduction order: not attempted (Gate-D-ish owner call; the doc measured it is rounding only).

## Runs (X2)
| command | log | exit |
|---|---|---|
| tools/preprocessing-export-test/run.sh (corrected fixture, green) | harness-2.log, final harness-3.log | 0 / 0 |
| same, first fixture (5x5 detector, error mine: py4DSTEM itself found no mask) | harness-1b.log | 133 |
| xcodebuild build (dd = $SP/X/dd) | build-1.log | 0 (two "failed with exit code 0" noise lines) |
| xcodebuild test -only-testing:mac4DSTEMTests/PreprocessExportTests | test-1.log | 0, 5/5 by method name |
| tools/run-tests.sh core | core-1/2 (EXIT=1: type-check budget on a 14-argument DataCubeDerivation init, fixed by assigning the new fields after init), core-3 EXIT=0, core-4 EXIT=0 | 0 |
| tools/run-tests.sh inventory | inventory-1.log, inventory-2.log | 0 / 0 |

## Diagnosis (Gate D)
No Gate D trigger: new feature behind a default-off flag, defaults byte-identical to before (stride 1, no crop, no filter: the default path is the old arithmetic, the harness's first scenario still passes unchanged). It does not move any existing number. The filter is a port pinned to py4DSTEM, with the one scientific claim (bin-then-filter order, mask) verified on the owner's real cube. The one place I suspected a mechanism and refuted it: my own first fixture, where the harness "failed" (mask []): candidate (a) port bug, candidate (b) fixture bug. Refuting observation: py4DSTEM's own filter_hot_pixels printed "No hot pixels detected" on the identical array. (b) survived: on a 5x5 binned detector np.roll's wrap puts every planted pixel inside another's 21-pixel window.

## Deviations from the brief
- X1: brief predicted bit-identical; measured not (<= 1.14e-4), see above; the 09-30 record had already said so.
- Mean pattern accumulates in Double (py4DSTEM: float32 sequential); noted in the file header as DEVIATION. The 15-position result shows no consequence on the real cube (mask identical for the thresh 8 plateau).
- The hot-pixel pass costs a second read of the source (28 GB: 171 s vs 16 s cached, i.e. 2 cold reads). An alternative (filtering from a re-read of the written file) would have been more code.
- Also edited outside the stated write-set because the registration requires it: mac4DSTEM.xcodeproj/project.pbxproj (Core exception list), tools/lib/sources.manifest (export group), and ResultExport.swift only inside exportCalibratedDataCube.
- When stride > 1 or a detector crop is on, the replay recipe is OMITTED by name in the status line (its frame table knows the bin only). Not silently.
- Sheet: stride and hot-pixel threshold clamp rather than refuse when a tighter crop shrinks their range (effective values, `stride`/`bin` in ExportSheet).

## UI cost (ExportSheet, rows / pt; Form .grouped, scrolls inside the existing LayoutPolicy.exportSheet band, no numeric .frame literal added)
Off-state (defaults): +1 row (Scan stride, inside "Real-space crop") +1 row (Crop detector toggle, section renamed "Diffraction crop and binning") + a new "Hot pixels" section = header + 1 row => ~ +4 rows, about +110 pt at ~28 pt/row. All on: +4 detector steppers, +1 threshold row, +caption of ~3 lines => about +9 rows / +260 pt. Ideal sheet height 700 pt: the calibration readiness block above it varies; the Form scrolls. NOT driven on screen (rules: no launching): UNVERIFIED ON SCREEN. Threshold field uses OptionalNumericField (NumberEntryField -> DecimalEntryFormat, German "0,5" path), default 8.

## Proposed doc lines
- status handoff: "X2 landed (uncommitted until gated): Preprocess & Export has scan stride, detector crop, optional hot-pixel filter (py4DSTEM filter_hot_pixels port, default off, mask in provenance); gated in tools/preprocessing-export-test vs py4DSTEM (bit-for-bit) + PreprocessExportTests (5). X1: export of the raw 060 DM4 at bin 4 + filter 8 = exactly py4DSTEM's 15 positions, <= 1.14e-4 rel everywhere, not bit-identical (float32 order). On-screen drive of the sheet: unverified."
- open-items: (1) the export's float32 sum order is not numpy's (rounding only, 1.14e-4 relative max on the 28 GB cube); (2) hot-pixel mean in Double vs numpy float32 (DEVIATION); (3) replay recipe is dropped for strided or detector-cropped exports; (4) ExportSheet unverified on screen.
- plan Log line: "2026-10-01 Slot 2 lane X: X2 (stride, crop_Q, filter_hot_pixels port) and X1 (28 GB export parity: mask = the 15, <= 1.14e-4) done; the brief's bit-identical prediction refuted by the known float32 summation order."

## Open questions for the supervisor
- Should the export match numpy's reduction order to be bit-identical? (Not done; costs a changed accumulation in a hot loop.)
- The ExportSheet still needs the owner's / a scratch-build drive (Unverified-on-screen row).
- ReplayRecordFrameMap could learn stride/crop-offset roles; for now the recipe is omitted.

## git status --short
 M mac4DSTEM.xcodeproj/project.pbxproj
 M mac4DSTEM/Core/Data/BraggVectorEMDTypes.swift
 M mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift
 M mac4DSTEM/Support/ResultExport.swift
 M mac4DSTEM/UI/ExportSheet.swift
 M tools/dm4-parity-probe/main.swift
 M tools/dm4-parity-probe/run.sh
 M tools/lib/sources.manifest
 M tools/preprocessing-export-test/main.swift
 M tools/preprocessing-export-test/run.sh
 M tools/preprocessing-export-test/verify_py4dstem.py
?? mac4DSTEM/Core/Data/HotPixelFilter.swift
?? mac4DSTEMTests/PreprocessExportTests.swift
(Other lane's files, if any, would appear here too; none were present at the end of my run.)
