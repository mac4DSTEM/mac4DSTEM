# Gate D — learned detector above 256 px: D098 dose scale, D004 seam bands, probe anchor, 2026-09-30

Trigger: moves the learned detector's peak set on detectors > 256 px. Pre-registered 2026-09-29 before any code change
(scratchpad `prereg.md`, not retained). Code: `Core/ML/LearnedDiskDetector.swift` (`nativeCountScale`, `modelInputs(countScale:)`,
`edgeMargins`, `detectAll`), `Core/Analysis/DiskDetection.swift` (`refine(edgeMargins:)`). Tests: `LearnedWindowedDetectionTests`
+ `LearnedWindowedFixture` (deterministic float32 pattern: lattice a = 80 px at 12°, disks r = 12, beam 0.9, Poisson-like noise at
20 000 counts). Owner constraint: ≤ 256 px (one window) byte-identical. Independent refuter: **owed**. Logs: `b/…` = session
`eb2a2d51…` scratchpad, `85a5f653…/b/…` = the earlier session's (2026-09-29); neither is retained, so the numbers are here.

## D004 — a band at every window seam was searched by neither window
- **Diagnosis.** `refine` applied `edgeBoundary` (eb = qMin/24) window-relative on all sides. The ACTUAL overlap is 256 − step
  (origins spread evenly), not the nominal `windowOverlap`; where it is < 2·eb, [o_i + 256 − eb, o_{i+1} + eb) is rejected by both.
  q = 1024: overlap 64 < 84 → 20 px bands at 214, 406, 598, 790 (+20, x and y); Si_SiGe 448×480 (eb 18): 32 < 36 → x ∈ [238, 242).
- **Prediction / refutation.** 1024 disks planted in the bands: band recall ~0 before, ≈ interior after, one peak per disk; 512
  (overlap 128) bit-identical. Band recall still ~0 after → diagnosis wrong.
- **Fix.** Detector-edge sides keep eb; a side shared with a neighbour takes min(eb, overlap/2), so a pair's accepted intervals
  touch. Overlap ≥ 2·eb → eb (nothing moves); window count unchanged ("overlap ≥ 2·eb" rejected: 484 vs 81 windows at q = 2048).
- **Result** (HEAD vs change, `b/r0-measure.log` vs `b/r1-measure.log`): 1024² seed 1 113/153 found, band 0/40 → 153/153, 40/40;
  seed 2 113/153, 0/40 → 152/153, 39/40; precision 1.0 throughout. 448×480 synthetic, seeds 1–2: 29/30, band 0/1 → 30/30, 1/1.
  512² control: 37/37, peak lists bit-identical. Real Si_SiGe (10 patterns 448×480, counts, max 36 897): 318 → 320 peaks, both
  new ones (positions 0, 8) in x ∈ [236, 244) (15 → 17). Attribution (`85a5f653…/b/m1-d004only.log`, `m1-d098only.log`): D004
  alone equals the full change on every fixture; D098 alone equals before on every fixture.

## D098 — each 256-px window was dose-scaled by its own maximum
- **Diagnosis.** `modelInputs` ran `toCounts` (float pattern with max ≤ 1 → max 20 000) per window; `evaluate.py:48-50` scales
  the NATIVE pattern once, then fits. A beam-less window was inflated to the beam's dose; a count pattern's window with max ≤ 1
  was scaled at all.
- **Refutation.** c0[p]/c0[q] of two overlap pixels depends on the scale (log1p is not linear); equal already → wrong. Measured on
  the scan's own input (400 px, beam in one of four windows; `85a5f653…/b/m3-mutC.log`): per-window 1.303 in the three beam-less
  windows vs 1.486 with the beam; one scale → 1.486 in all four. Count pattern (max 500): 1.194 per-window vs 4.25 unscaled.
- **Fix.** `nativeCountScale` (largest finite value) once per native pattern, shared by its windows; one window passes nil = old rule.
- **Peak-level result: none observed.** The only peak-level exercise is 1024² (origins 0, 192, 768 beam-less): null. The 512²
  faint-lattice runs (1 … 0.02, bit-identical) cannot exercise D098 — the beam at (256, 256) puts beam pixels in all nine
  windows (supervisor). Si_SiGe is counts (a no-op by construction). The input now matches the training convention; the peak
  effect on real float data > 256 px is unmeasured (none to hand).

## Probe/pattern anchor (open item) — measured, no change
The clamped probe crop differs from training's `fit_offset` only for a probe < 128 px from an edge of a > 256 detector. 512²,
beam at x = 90 and at (90, 90), 2 seeds: clamped 35/35 and 34/34; `fitOffset` crop (`m1-anchor2`) the same disks, sub-pixel
positions moved (the kernel's frame moves too); a crop at each window's origin (`m1-anchor3`) loses 5 of 320 real Si_SiGe peaks.
Probe channel ZEROED (`b/m2-measure.log`): all 26 measured peak lists bit-identical to the unzeroed run, ≤ 256 px included.
Pre-registered rule: no difference → no change. An observation on these fixtures, not a claim that the net ignores the channel.

## ≤ 256 px byte-identity
SHA-256 over every peak's (x, y, intensity) bits, HEAD vs change (`b/r0-measure.log`, `b/r1-measure.log`): 16 committed 128-px
patterns 7534c028… (295 peaks), 250² central 0a17fcde… (13), 256² 4c0c50bd… (13), 250² beam at x = 200 a8ebd679… (9), 200×256
2116d8a7… (11): identical. `85a5f653…/b/before.log`, m1-*, m3-green, m5-final, r0, r1 and m2 give the same five (the m3 mutant runs carry none).

## Gates
- Green: `LearnedWindowedDetectionTests` 11, `LearnedDiskDetectorTests` 8, `LearnedDiskDetectorGateBTests` 9,
  `LearnedDetectionSessionTests` 10, `LearnedDiskDetectionScanTests` 8 = 46 passed, exit 0 (`b/g2-green.log`).
- Red on mutation (exit 65): A margins = eb everywhere → 4 margin/seam tests; B scan passes no margins → seam; C scan passes no
  scale → both scan dose tests; D `modelInputs` ignores `countScale` → those + the pure ratio test; E one window gets the native
  scale → single-window test (`85a5f653…/b/m3-mut{A..E}.log`; the test file changed since only in comments, two `first ?? -1`
  guards and a `nonisolated` collector). F `refine` ignores `edgeMargins` → refine + seam tests; G `nativeCountScale` reads
  non-finite pixels → its pure test (`b/g-mutFG.log`, `b/g2-mutF.log`). The 512 control has no mutant by design.

## Residuals
- ≤ 256 px keeps the per-frame scale: a < 256 detector with an off-centre probe (frame drops columns) is scaled by the crop's
  maximum, not the native one as `evaluate.py` does — kept by the byte-identity constraint (a test pins it). Owner.
- Above ~960 px the interior margin is overlap/2, not eb (q = 2048: 16 px vs 85); recall that near a window edge is unmeasured.

## Independent supervisor (Fable, 2026-09-30): COMMIT
All six points HOLD: both defects shown on true HEAD (1024² band 0/40; D098's per-window ratio 1.303 vs 1.486 is the log1p
arithmetic); a replica over q 257…2048 × four overlaps × five edge boundaries finds 87 822 seam gaps before, 0 after, window
count untouched; ≤ 256 px hashes identical in every run that carries them; > 256 px movement is D004 only (Si_SiGe +2 peaks,
both in the band, every other peak bit-identical); every new test red on its mutation. Unexplained, not a regression: 1024²
seed 2 misses one band disk (152/153) — likely the half-open ownership rule; a per-window candidate dump would settle it.
