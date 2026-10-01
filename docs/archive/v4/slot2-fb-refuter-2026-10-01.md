# Lane F-B — independent refuter (Gate D: the diagnosis, not the diff). 2026-10-01. Read-only; scratch in $SP/FB/refute/.
Reviewed: $SP/FB/report.md, the diff of the 14 files in $SP/gate-FB/files.txt, logs test-1/4/5, py4DSTEM at References/py4DSTEM-dev.

## Row 9 (odd-axis wrap in MatrixDFTCorrelation) — HOLDS
- Reproduction real: test-1.log red numbers 2.1813 / 3.6754 (13x11), 3.6771 (13x12), 2.1754 (14x11) for true (2.3, 3.6).
- Independent oracle ($SP/FB/refute/row9.py, py4dstem env): py4DSTEM's own `upsampled_correlation` on the identical spectrum
  returns [2.3, 3.6] on every shape; replacing only its wrap by `k < N/2` reproduces the Swift red numbers TO FOUR DECIMALS
  (2.1813/3.6754, 2.3038/3.6771, 2.1754/3.5954) and the `(N+1)/2` wrap returns [2.3, 3.6]. 14x12 even: all three identical.
  So the diagnosis (wrap, not parabola/rounding) is proven, and the fixed Swift is py4DSTEM-exact on this fixture.
- Faithful: multicorr.py:186 (`ifftshift(arange) - floor(N/2)`, columns) and :195 (rows); Swift now `< (N+1)/2` on both axes = same set.
- Magnitude on a real peak (Gaussian σ 1.5 px, 13x11): buggy 2.2835 vs py4DSTEM 2.3274 → 0.044 px; the fixture's 0.12 px is the worst case.
- Who reaches odd N: DiskDetector px/py = exact detector dims (DiskDetection.swift:775, ProbeKernel px = qx) → any odd detector or odd
  crop; ParallaxAlignment stack = scan + 32 padding (ParallaxPreprocessing.swift:398) → any ODD SCAN SIZE with upsample > 2 — this
  is the more common shipped path (odd scans are ordinary). Even axes are bit-identical (integer N/2 == (N+1)/2 for even N).
- Test: oracle is the numpy-frequency spectrum (same convention as the fix) — not circular, because py4DSTEM gives the same answer on
  it (above) and a convention-free real-space oracle agrees. Tolerance 0.03 vs a 0.12 px defect: catches the mutation (test-4 red).
- Completeness finding (outside the write-set, not a must-fix here): Core/Analysis/ProbeKernel.swift:207,209 has the same
  `y < py / 2 ? y : y - py` wrap for the trench's wrapped radius — on odd N the middle row/column reads distance (N+1)/2 instead of
  (N-1)/2. py4DSTEM builds that kernel on a centred meshgrid (probe.py:187-190), so it is not the same formula, but it is the same
  odd-N alias slip; register it as its own item. ProbeKernel.swift:274,276 and FFT2D.fftfreq:653 already have the right form.

## Row 29 (ellipse predicate) — HOLDS (one open item must be registered)
- Reproduction real: test-1.log — a 19.5 / b 0 gives hasEllipse true and (3,4) → (1.11, −0.47); b −17.9, a −19.5 likewise.
- py4DSTEM: `_transform` uses e = b/a with no ordering (braggvectors.py:505-507); its fit DOES order a ≥ b at output
  (elliptical_coords.py:78 `a, b = max(a, b), min(a, b)`), and `Calibration.set_ellipse` (calibration.py:592-598) validates nothing.
  So accepting an a < b file ellipse is what py4DSTEM's reader does; refusing it would be stricter than py4DSTEM. Lane's choice holds;
  manual entry keeping a ≥ b (CalibrationSession, the owner's 2026-09-28 decision) is untouched.
- Completeness: the correction is gated by hasEllipse at use, so the other adoption sites that still copy raw — AppState+Lineage.swift:411
  (replay), SessionCalibrationFramePolicy.swift:117 (sidecar), CalibrationReReference.swift:320 and BraggVectorEMDWriter.swift:1427
  (binning, sign-preserving) — can no longer apply e ≤ 0; readiness and correction now agree. Acceptable.
- Row asked for a NAMED refusal; the importers drop the triple silently. Better than HEAD (silent wrong correction → honest
  "No detector-distortion correction"), but the open item the report proposes MUST land in docs/open-items.md in the same commit.
- Tests go red on the predicate revert (test-4: NonPositiveAxes + acceptedEllipse). No symmetric-fixture issue (theta 0.4, vector (3,4)).

## Row 24 (non-finite pixels in both origin paths) — HOLDS
- Reproduction real but the SEED claim was over-stated and the lane said so: one NaN in a plateau moved the Metal origin 0.0034/0.0040 px
  (NaN block loses, CoM reads max(NaN,0)=0); Inf → NaN origin; Friedel → NaN. The row's "displaces the seed at every position" is
  the Inf/edge case, not the single-NaN case. Recorded correctly in the report ("prediction partly refuted").
- Fill rule vs DiskDetector.fillNonFinite (DiskDetection.swift:990-1014): same 8-neighbour set, same bounds, finite-only, sorted median,
  even-count average, 0 when none, neighbours from the ORIGINAL buffer (fillNonFinite defers writes; the Metal/Friedel versions read a
  const source) — equivalent. Metal insertion sort ascending, median index identical. Verified by inspection.
- Metal bit test `(bits & 0x7F800000) == 0x7F800000` is exactly "exponent all ones" = ±Inf or NaN; denormals (exponent 0) and −0 are
  finite and pass through unchanged. MTL_FAST_MATH = YES is on (pbxproj:438,503), so `isfinite()` could legally fold — the bit test is right.
- Both entry points of FriedelOrigin.origin sanitise (lines 44, 92); the only callers are OriginCalibration.swift:783 (prepared path)
  and tools/friedel-origin-test. No CPU fallback for measureOrigin exists (only MetalEngine.measureOrigins, two callers), so the kernel
  change covers every measured-origin path. OriginParams: 6 × 4-byte fields on both sides, untouched.
- Tests: the mutation (return raw) goes red (test-4, 4 assertions). Weakness: both fixtures put the NaN inside a 100-plateau, so the
  median is trivially 100 and a wrong rule (mean, 0-fill, nearest) would ALSO pass at 1e-4 in the Friedel case and nearly so in the
  Metal case. Not green for the wrong reason (the fill is exercised), but the median rule itself is untested — optional edge-pixel case.
- "Count the fills into provenance" not done (write-set/ADR 049); the report's open item must be registered.

## Row 6 (MP importer runs verifyFamily) — HOLDS
- Reproduction real: Pa-3 fixture imports as .cubic on HEAD; R-3m pinned .hexagonal on HEAD (test-1.log "did not throw").
- Faithful to the CIF importer: same call shape as CIFImport.swift:152-158 (classifyFamily → verifyFamily), run on the STANDARDISED
  sites (after `standardise`, MaterialsProjectImport.swift:795), halfStep 0 so the "unresolvable at written precision" branch is
  unreachable (resolutionLimited 0 < 5e-3) — correct for full-precision JSON. isSymmetry (CIFImport.swift:1177-1207) does search
  translations from every same-Z candidate, so "no translation restores the 6-fold for R-3m" is checked, not argued.
- Same answer as the CIF importer for the same structure: CIFImportTests:382-437 already pins trigonal-in-hexagonal-axes and Laue-6/m
  to symmetryNotSupportedByStructure. The two importers now agree.
- Which MP phases are now refused: every trigonal phase (R-3m, R-3c, P3₁21 …), every Laue-6/m hexagonal, every Laue-m-3 cubic
  (Pa-3, Pm-3, Im-3, Fm-3). Refusing beats HEAD's answer (a 12/24-operator reduction and an IPF key the phase does not have, silently).
  Question for the owner, NOT this row: monoclinic imports as `.identity` ("still usable for identification"); a trigonal or m-3 phase
  could be imported the same way instead of refused — a policy both importers share today.
- The LiAl2Cu session fixture was a fake cubic cell (4 atoms, no 3-fold) that only the new check could see — replaced by the real
  Heusler cell; the mismatch verdict still comes from 225 vs 191. Legitimate fixture repair, not a test weakened to pass.
- Tests red on removing the call (test-4: Pa-3 + re-pinned R-3m), controls (Mg P6₃/mmc) green.

## Gate evidence
- test-4.log: exactly the 7 predicted tests red by reverting only the fixes; test-5.log: 117 passed, EXIT=0 (12 classes).
- Re-run by the refuter: `tools/run-tests.sh core` exit 0 ($SP/FB/refute/core.log); `tools/run-tests.sh inventory` exit 1 —
  "UNCLASSIFIED acom-mirror-test": another lane's untracked tools/acom-mirror-test/, not F-B's files. The supervisor's inventory run
  must pass once that tool is classified; F-B's own earlier inv.log has no exit line inside it (exit was echoed to the terminal only).

## Overall: HOLDS — commit, with the must-fix list
1. docs/open-items.md gets the two items the report proposes (row-29 silent drop → named refusal; row-24 fills not in provenance),
   same commit (CLAUDE.md: docs are part of done).
2. Register ProbeKernel.swift:207,209 (same odd-N wrap alias in the trench) as a new item — not amended into row 9.
3. Inventory must be green at commit time (acom-mirror-test is another lane's classification debt).
Optional: a row-24 edge-pixel fixture where the median differs from the mean, to pin the fill rule itself.
