# Code review & forward plan — 2026-07-19

Full-codebase review (compute, data, analysis, app state, persistence, UI,
tests, build configuration). Companion repo actions taken with this review:
`.DS_Store` litter and the empty `mac4DSTEM/HDF5/` directory removed, and the
README reduced from a 391-line checkpoint log to a product-focused document
(per the policy already stated in `development-history.md`). No Swift code was
changed — every code item below is scoped to land at a green
`tools/run-tests.sh` boundary, per ROADMAP Priority 3.

## Verdict

The codebase is in unusually good shape: no correctness bugs found in the
numerical core, no memory-safety or race defects, no `try!`/TODO debt.
Concurrency is disciplined (dataset-epoch + operation-token guards on every
publication path checked), py4DSTEM deviations are documented at the deviation
site, and calibration/result provenance is enforced in code rather than
aspirational. The items below are the gap between "excellent engineering" and
"a polished scientific product."

## A. Correctness / scientific-contract items

*All four items resolved 2026-07-19 (Milestone 1). A1: `calibrateEllipse` now
fits the raw-intensity Bragg-vector map built from stored peaks, collapsed
onto the mean origin with no ellipse applied (log-scaled, already-corrected
display pixels are no longer fit inputs). A2/A3: `DM4Reader.decode` throws
`.truncated` instead of returning zeros, cube sizing uses overflow-checked
arithmetic plus a mapping-coverage guard, and tag-tree recursion is capped at
depth 64; gated by the new `tools/dm4-robustness-test` harness (registered in
the scientific suite). A4: the strain reference mask is now derived from the
same `DetectorShape` as virtual diffraction via `VirtualDetector.makeMask`.*

**A1. Ellipse calibration fits the log-scaled display image.** ✅
`AppState.calibrateEllipse` (`App/AppState.swift:2496`) feeds `resultImage`
into the fit when in Disks mode, but that image is `log10(1 + BVM)` from
`showBraggMap` (`App/AppState.swift:2922`). The conic model is
intensity-weighted, so peak weighting deviates from py4DSTEM's fit on the raw
Bragg-vector map (ring positions unaffected; weighting is not).
*Fix:* fit the raw calibrated BVM, or add a `DEVIATION` note if log-weighting
is deliberate. *Gate:* `tools/ellipse-calibration-test/run.sh`.

**A2. Truncated DM4 files degrade to silent zeros.** ✅ `DM4Reader.decode`
(`Core/Data/DM4Reader.swift:112`) returns zero-filled buffers past EOF, and
`locateDatacube` accepts a declared byte count of 0
(`Core/Data/DM4Reader.swift:300`). A file truncated mid-cube "opens" and shows
blank patterns — the opposite of the app's explicit-failure philosophy.
*Fix:* throw `.truncated` when a requested slice exceeds the mapping; require
the blob length to match the cube. *Gate:* extend `tools/vendor-reader-test`.

**A3. Corrupt DM4 metadata can crash.** ✅ `ry*rx*qy*qx*elementSize`
(`Core/Data/DM4Reader.swift:299`) traps on Int overflow for absurd tag values;
`walkGroup` recursion is depth-unbounded. *Fix:* multiply via
`multipliedReportingOverflow`, cap recursion depth (~64), reject on either.

**A4. Half-pixel mismatch between strain reference mask and displayed ROI.** ✅
`realSpaceRegionShape` centers the circle at `selectedScan + 0.5`
(`App/AppState.swift:1768`); `realSpaceRegionMask` measures from the integer
position (`App/AppState.swift:1790`). Edge pixels can differ between what
virtual diffraction sums and what the strain reference uses. *Fix:* derive
both from one region predicate.

## B. Performance (ranked by user-perceived value)

*B1, B2, B5 resolved 2026-07-19 (Milestone 2). B1: both colorbar ranges now
cache their O(pixels) base scan behind the existing version-counter pattern.
B2: `detectCurrentPattern` coalesces via inFlight/pending like the aperture
drag. B5: `crossCorrelate` computes the complex product in place (ccRe/ccIm
populated only for multicorr) and the ACOM ring-sum uses contiguous
`vDSP_vadd` accumulation. Measured on the M3 checkpoint (Release harness,
repeats 5 / warmups 2): `acom_matching_medium_cpu` 59.93 → 14.32 ms (−76%),
`acom_matching_small` −61%, `acom_matching_medium_metal` −17%; disk paths
flat; every benchmark checksum bit-identical. B3/B4 remain open (Milestone 5).*

**B1. Cache the colorbar value ranges.** ✅ `patternDisplayedValueRange`
(`App/AppState.swift:826`) loops every CBED pixel — with a `log10` each in log
mode — on every SwiftUI evaluation; `resultDisplayedValueRange` recomputes
`minMax` similarly. Join them to the existing versioned caches
(`patternNormCache` pattern).

**B2. Coalesce live disk detection.** ✅ Each `diskParams` change spawns a
detached full-pattern detection (`App/AppState.swift:2838`); the request
counter discards stale *results* but the *work* still runs. Reuse the
`vdInFlight`/`vdPending` coalescing already built for aperture drags.

**B3. Overlap I/O and GPU in the tiled passes.** Every tiled operation copies
a tile into a fresh `MTLBuffer`, dispatches, and blocks (`waitUntilCompleted`)
before reading the next tile. Double-buffering (read tile N+1 while N
computes) should roughly halve wall-clock for whole-cube passes on I/O-bound
datasets. Verify with `tools/performance-baseline`.

**B4. GPU disk-detection correlation.** The 2026-07-06 assessment still
stands: whole-cube ops are bandwidth-bound and already fast; per-pattern CPU
FFT correlation is the big remaining lever (15 s for 725k peaks on the 058
baseline). A Metal (or MLX) batched-FFT correlation path, parity-gated like
the ACOM Metal backend, is the single highest-value performance project.

**B5. Small hot-loop items.** ✅ `crossCorrelate` copies two full arrays per
pattern (`re = ccRe; im = ccIm`); `OrientationMatcher.match` ring-sum is a
scalar strided loop next to an otherwise vectorized path.

## C. Architecture (unchanged direction, confirmed by review)

ROADMAP Priority 3 is correct as written; the review adds only ordering:

1. Extract **result publication** from `AppState` first (the
   `restoredResultInfo`/`navigationResultInfo`/`resultVersion` cluster is the
   most intertwined and most duplicated logic; `DisplayedProduct` is already
   the right seam).
2. Then **calibration state + provenance** (self-contained value cluster).
3. Then file-open/session orchestration.
4. ✅ *(2026-07-19)* Delete vestigial `AnalysisMode.isAvailable` (always true) and deduplicate
   the transform-matrix construction in
   `Calibration.ellipseCorrectedOffset`/`ellipseUncorrectedOffset`
   (`Core/Data/Calibration.swift:445`) on the next touch of those files.

Do not split `ContentView` speculatively; split per-workspace views as each
workspace next changes (the pattern `ProductWorkspaceViews` already follows).

## D. Design & usage plan — toward an appealing product

The scientific core is trustworthy; the product gap is now *feel*. Ordered by
impact per effort:

**D1. Forgiveness.** ✅ *(2026-07-19: fitted origin maps displaced by a manual center drag are retained in a superseded slot and recoverable via Restore Fitted Origin in Calibration; export honesty preserved.)* One accidental aperture-center nudge silently discards a
whole-scan origin fit (`updateAperture`, `App/AppState.swift:1566` — correct
in intent, harsh in effect). Add: (a) a status-bar undo for "manual center
superseded fitted maps," or (b) retain the fit and require an explicit
"switch to manual center" confirmation. Same review for every destructive
`didSet` (model/quality changes invalidating ACOM plans is fine; losing
measured calibration is not).

**D2. First-run experience.** The welcome window lists Open/Recents but the
app's strongest asset — guided readiness — only appears after opening a file.
Ship a small bundled demo dataset (or generate the demo fixture from the
welcome screen, which already exists behind `--demo-fixture`) and a 60-second
guided tour: open → calibrate → virtual image → Bragg → strain. A scientist
should reach a strain map without reading anything.

**D3. Progressive disclosure is done; visual hierarchy is next.** The
workspace shell is structurally right. Invest one focused pass in: consistent
8-pt spacing grid in the tools panel, a single accent color reserved for the
primary action per workspace, calmer secondary controls (labels at
`.secondary`, controls `.small`), and typographic rhythm in the inspector
(monospaced digits for all numerics — partially done). No new features;
polish only.

**D4. Result storytelling.** Results already carry
Quantitative/Relative/Exploratory/Categorical status — surface it as a
persistent colored badge on the viewer (not only in inspector text), and pair
every map with its quality field (strain ↔ residual, ACOM ↔ reliability) as a
one-click toggle rather than a separate display-mode choice. This is the
feature reviewers of scientific software will notice.

**D5. Colorbar/scale-bar polish.** B1's cached ranges also fix label jitter
during drags. Add the missing direct scattering-angle (mrad) CBED axis option
noted in the old README — the calibration machinery for it already exists
(`DPC.milliradiansPerDetectorPixel`).

**D6. Error empathy.** ✅ *(2026-07-19: zero-peak full scans and rejected strain now name the measured peak population and point at the acceptance funnel/Bragg-panel controls; the ACOM→Q-calibration route already existed in ACOMControlsView and was verified.)* Failure messages are honest but terminal
(`present(error)` → alert). For the three most common failures (no Bragg
peaks accepted, strain basis rejected, ACOM without Q calibration) route to
the existing diagnostics instead: open the acceptance funnel, highlight the
offending threshold, or link the calibration step. The funnel diagnostics
exist — connect them to the failure paths.

**D7. App icon / identity.** Present (recent "new icons" commit) but worth a
final pass against macOS 26 icon conventions before public release, plus a
product screenshot set for the README/website — currently there is no visual
anywhere in the repo for a deeply visual application.

## E. Suggested sequencing

| Milestone | Contents | Gate |
|---|---|---|
| 1. Contract fixes | A1–A4 | `run-tests.sh scientific` + extended DM4/ellipse harnesses |
| 2. Feel | B1, B2, D1, D6 | unit suite + UI smoke; no science changes |
| 3. First-run + polish pass | D2, D3, D5, D7 | UI smoke + hands-on walkthrough |
| 4. Result storytelling | D4 | ResultPresentation tests |
| 5. Throughput | B3, then B4 (parity-gated GPU correlation) | performance baseline + parity harnesses |
| 6. Extraction (continuous) | C1–C4, opportunistically with 1–5 | full aggregate gate |

Milestones 1–2 are small and unblock a confident public beta; 3–4 are the
visible product step; 5 is the headline performance claim ("interactive Bragg
detection"); 6 rides along. Release-owner actions (signing, notarization,
two-instrument vendor-reader validation) remain as listed in ROADMAP.

Ready-to-run session prompts executing this plan (four sequential milestones,
subagent delegation, per-milestone gates) are in
[`implementation-prompts-2026-07-19.md`](implementation-prompts-2026-07-19.md).
