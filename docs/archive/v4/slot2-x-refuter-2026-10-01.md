# Slot 2 lane X — Gate B refuter (Fable 5.1), 2026-10-01

# Gate B refuter — lane X (raw-data preprocessing export), 2026-10-01
Independent refuter (Fable 5.1, did not write the change). Read-only on the repo; scratch experiments under archive/v4/slot2-x-refuter-2026-10-01/
(driver.swift + HotPixelFilter.swift compiled standalone, compare.py, meandev.py; python = ~/miniconda3/envs/py4dstem, numpy 2.5.0).
py4DSTEM pinned at f050d207 (confirmed with git log in References/py4DSTEM-dev).

## Overall: HOLDS WITH CORRECTIONS (two inline notes; no number moves, no refuted claim)

### (a) filter_hot_pixels port fidelity — HOLDS, with one correction to the DEVIATION note
Evidence, line by line against preprocess.py:349-460:
- 21-pixel window: HotPixelFilter.swift:44-47 builds the 3x3 + (dy,±2) + (±2,dx) offsets; py4DSTEM's np.roll list (l.400-420) is the same set.
  Wrap: ((i+o) % n + n) % n at l.54-55 == np.roll modular indexing, including n < 5 where offsets alias (checked below down to 1x1).
- ind_compare: window[count-1-indCompare] (l.59) == diff_local_med[-ind_compare-1] (l.424). Strict ">" with Float(thresh) (l.48,60) ==
  `diff_mean - diff_compare > thresh` (l.427) under NEP 50 (numpy 2: weak Python scalar -> float32 compare).
- Mask order row-major (l.51-52) == np.nonzero order (l.439). Replacement: clipped 3x3 (l.78-79) == the slice clipping (l.443-452; the
  `elif` there is harmless because numpy slicing clamps anyway). In place, mask order, later pixels see earlier replacements (l.75-88) ==
  the inner zip loop (l.458-459). Even-count median (a+b)/2 in Float (l.85-87) == np.median -> np.mean of two float32 -> float32.
- EXPERIMENT (archive/v4/slot2-x-refuter-2026-10-01/compare.py, 400 random cubes, scan 2x2 so both means are exact; shapes (8,9),(3,3),(2,5),(1,7),(5,5),(4,4),(6,12),
  (2,2),(1,1),(3,2); integer values 0-5 with planted pixels 10-2000 incl. ADJACENT pairs; thresh in {0,1,2.5,8,20}): mask identical and
  output bit-identical to py4DSTEM's filter_hot_pixels in all 400 (155 non-empty masks, 0 failures). Edges, wrap, ties, adjacent masked pixels,
  1-pixel-wide detectors: all covered.
- NaN: Swift's sort is unspecified with NaN, numpy sorts NaN last. Not reachable from a counts detector; noted, not a must-fix.
- CORRECTION (the DEVIATION's magnitude, HotPixelFilter.swift:20-25): the note says a pixel is classified differently "only when its excess
  lies within the float32 accumulation error of thresh" — true in form, but the magnitude is not small. np.mean(axis=(0,1)) on a float32
  (Rx,Ry,Q,Q) cube accumulates sequentially in float32 over Rx*Ry patterns. Measured (archive/v4/slot2-x-refuter-2026-10-01/meandev.py, numpy 2.5.0, 108 900
  patterns): |mean32 - mean64| = 0.009 at pixel value 1e3, 0.15 at 1e4, 45-230 at 2e5. The 060 cube's binned central disk reaches
  2.5e5 (x1-off.log: max |Δ| 2.556e+05), so in the bright disk py4DSTEM's own float32 mean carries an error of tens to hundreds of counts
  against thresh 8: there, py4DSTEM's mask is partly an artefact of its accumulation and the port (exact Double) can legitimately differ.
  On the 060 cube the 15 positions matched (x1-on.log), but that is one dataset and the margin (smallest |excess - thresh| on either
  side) was not measured. The harness fixture (integer means, exact in both) cannot exercise this. The Double mean is the better science;
  keep it, but the note must say the magnitude and that mask identity with py4DSTEM is NOT guaranteed in the bright disk.

### (b) Operation order and stride semantics — HOLDS
- Order crop_R -> thin_R -> crop_Q -> bin_Q -> filter is exactly the call chain the harness feeds py4DSTEM (verify_py4dstem.py reference()),
  and bin-then-filter is the order of the owner's own file (parity-28gb doc; reproduced by X1's exact 15-position mask). py4DSTEM's
  functions are independent of order only where they commute; thin before crop_Q commutes, crop_Q before bin does not (the bin trims the
  remainder off the CROPPED extent: writer l.~290 cropY.count / qBin and discarded = cropY.count - outQY*qBin == bin_data_diffraction
  l.178-188 on the cropped data). A user who bins THEN crops in py4DSTEM gets a different file; the sheet states the order it uses ("after
  the bin" caption); the derivation records offsets in SOURCE pixels so the file is unambiguous either way.
- Stride: positions range.lowerBound + i*stride for i < count/stride (BraggVectorEMDTypes.swift positions()) == thin_data_real
  l.321-331 (Rshape // N, rx0 = rx*N from the cropped origin, no offset parameter in py4DSTEM). R pixel size x N == l.338. Writer refuses
  stride > min(count) (would give an empty axis in py4DSTEM); stricter, fine. Harness mutation stride ceil went red (mut-stride_ceil.log).
- Mean for the filter is over exactly the exported (cropped, thinned, binned) patterns (writer meanPattern()), as py4DSTEM's mean is over
  the cube at that point in the chain.

### (c) Calibration bookkeeping — HOLDS WITH CORRECTIONS (missing inline DEVIATION note)
- rSize x stride: right (thin_data_real l.338); identity at stride 1.
- qSize x bin, probe /bin, ellipse A,B /bin, theta/rotation/flip untouched: pre-existing and right (lengths vs angles).
- Origin: (v - cropOffset + 0.5)/bin - 0.5 with cropOffset for py4DSTEM qx = the app's first detector axis = qCropY.lowerBound
  (writer l.1404-1409). Sign and axis independently confirmed by the data path itself: the planted source pixel (6,9) lands at binned
  (2,3) under crop (2,3) and bin 2 — the same arithmetic the mask asserts (harness require(on.hotPixels == [[2,3],[7,8]])) — and the
  pixel-centre form gives (6 - 2 + 0.5)/2 - 0.5 = 1.75 for a block whose centre 6.5 -> 2.0. Consistent.
- Origin maps thinned at the kept positions and shifted (l.1437-1441); mean re-derived from the thinned maps; the frame net `inside`
  uses the cropped extent (l.1471-1472). Nothing in PixelCalibration (FourDDataSource.swift:68-104) is a pixel coordinate other than the
  origin; nothing is silently left in the old frame.
- CORRECTION: py4DSTEM's crop_data_diffraction (preprocess.py:123-136) resets only the dim vectors and leaves calibration.origin
  UNSHIFTED (and bin_data_diffraction l.191-203 likewise only scales Q pixel size). The export shifting the origin is therefore a
  deviation from py4DSTEM — the correct one — and the hard rule wants it inline. The writer has no DEVIATION note at l.1401-1409 (grep:
  the only DEVIATION hits are l.260, which refers to "this file's own DEVIATION note" that no longer exists, and l.1692). The harness
  checks the origin against the lane's own formula, not against py4DSTEM's post-crop calibration (which would be stale), so the deviation
  is real and currently undocumented in code.

### (d) Provenance and the recipe omission — HOLDS
- Omitting the recipe when stride > 1 or crop_Q is the honest option: ReplayRecordFrameMap has roles for the bin only; stamping a recipe
  in a frame the file is not in would be a silent lie. The status text (ResultExport.swift ~l.81) states the reason by name; the
  derivation still records scan_offset, scan_stride, detector_offset (source pixels, incl. the export crop x view bin, compose() in
  BraggVectorEMDTypes), detector_bin, so a reader can reconstruct every kept position. hot_pixel_threshold + hot_pixels present exactly
  when the filter ran (also when it found none: [] says "ran, found none"), absent otherwise; old files decode (test 5).
- With the filter on and stride 1 / no crop the recipe IS stamped; a filtered cube is in the same frame, so that is right.
- No other consumer of the derivation exists in the app (grep: only the writer, the two harness verifiers, and the new test), so a stale
  reader ignoring scan_stride is not a present risk; worth a line in open-items if a reader is ever written.

### (e) Tests and harness — HOLDS
- Unit (5 methods): each goes red on its stated mutation — test-mutA.log shows 4 failed, test-mutB.log 1 failed (** TEST FAILED **), and
  test-1.log / gate unit-X.log list all 5 passing by name. None is symmetric or vacuous: test 1 asserts a NON-EMPTY mask of exactly two
  specific pixels and relies on both the wrap and the second-brightest rule (a clamp or ind_compare 0 changes the set); test 2 brackets
  thresh from both sides; test 3 covers even and odd windows and the base offset; test 4 the floor; test 5 presence AND absence of keys.
- Harness: the fixture was repaired after py4DSTEM itself reported an empty mask on the 5x5 detector (harness-1b.log) — the correct
  reading (fixture error, refuted in Python, recorded as a dated amendment). The corrected fixture's mask is asserted in the verifier
  from py4DSTEM's own mask (not just the app's), the two files are compared bit-for-bit, and ON vs OFF differ at exactly the mask.
  6 harness mutations red (logs named). Reproduced green by the supervisor's gate (gate-X/harness-X.log HARNESS_EXIT=0) and by my own
  independent 400-case comparison above.
- X1 claim: metric is max |a-b| / max(|b|,1) per position (dm4-parity-probe/main.swift:216), as the report says. 1.14e-4 appears in
  x1-on.log at (2,51) and (6,49), one pattern each; "not bit-identical: float32 summation order" is the mechanism the 09-30 record already
  measured, and the prediction was written before the run with the contradiction of the brief stated. Honest. The one thing the X1 run
  does NOT establish is (a)'s margin (see above).

### (f) Default path bit-identical — HOLDS
- Writer: stride 1 -> scanYPositions == the range; rowsInTile = min(tileRows, remaining) as before; reducedTile with cropY0 = cropX0 = 0
  and empty mask is the old loop's arithmetic term for term (same summation order, same float32); progressBase 0 -> the old progress
  formula. transformedCalibration: rSize * 1.0 and ($0 - 0.0 + 0.5)/bin - 0.5 are IEEE-identical to the old expressions. Derivation:
  detectorOffset + 0 * viewBin; new keys absent when unused (test 5). ResultExport: reframesRecipe false -> the old exportableRecipe
  call; no suffix when threshold nil; totalUnits unchanged. ExportSheet defaults: stride 1, crop off (full ranges), filter off; the
  clamped `bin` equals the old stepper's range at defaults. The pre-existing harness scenario (crop + bin 2, no new options) still
  passes unchanged (harness-3.log "py4DSTEM round trip passed").

## Must-fix (both are inline notes; neither moves a number)
1. mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift ~l.1401 (transformedCalibration, the origin block): add an inline
   `DEVIATION:` note — py4DSTEM's crop_data_diffraction (preprocess.py:123-136) and bin_data_diffraction (l.191-203) leave
   calibration.origin unshifted/unscaled; this export shifts by the crop offset and applies (x+0.5)/b-0.5 so the origin is in the file's
   frame. Test that goes red: `tools/run-tests.sh inventory`'s DEVIATION grep cannot see it, so the check is: a harness assertion that
   py4DSTEM's calibration origin after crop_Q is NOT the file's (documents the deviation as a measured fact) — optional; the note is the rule.
   Also fix the dangling reference at l.260 ("this file's own DEVIATION note") or point it at the new note.
2. mac4DSTEM/Core/Data/HotPixelFilter.swift:20-25: amend the DEVIATION note with the measured magnitude (numpy float32 sequential mean
   over 1e5 patterns: ~1e-5 relative at 1e3-1e4, ~1e-3 relative = 45-230 counts at 2e5 vs thresh 8) and state that mask identity with
   py4DSTEM is guaranteed only where |excess - thresh| exceeds that error — i.e. not in the bright disk. Carry the same sentence into the
   report's Deviations and the proposed open-items line (2). Recommended, not required: have --export-parity print the margin
   (smallest |excess - thresh| among flagged and among unflagged positions) so the 060 match is a measured fact rather than a coincidence.

## Not must-fix, recorded
- NaN in the mean would make Swift's sort unspecified vs numpy's NaN-last; unreachable from a counts detector.
- A future reader of `mac4dstem_derivation` must honour scan_stride; none exists today.
- ExportSheet unverified on screen (the lane says so; the supervisor's drive).
(The driver binary is main.swift compiled with HotPixelFilter.swift from this commit: `swiftc -O -package-name refute main.swift ../../../../mac4DSTEM/Core/Data/HotPixelFilter.swift -o driver`, run from this folder.)
