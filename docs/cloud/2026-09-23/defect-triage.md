# Triage of the 2026-09-09 register's open claims: proposal, 2026-09-23

This answers the open item "119 unverified defect claims … triage order owed" (`docs/open-items.md`). **The triage order is a proposal. The owner decides.**

## Scope and method

- **Claims covered:** the 121 clusters in `docs/archive/2026-09-09-review/register.json` whose disposition is `new` (113) or `possible repeat` (8). The open-items count is 119 because D002 and D003 were closed on 09-09; they are included here and come back as FIXED.
- **Who checked them:** four independent read-only verifier agents, about 30 claims each. Each one read the code at HEAD `075c044`, searched `docs/` and `git log` for the claim's ID, and gave a verdict, file:line evidence, whether a fix could move a scientific number (Gate D), an effort (S/M/L) and a priority (1–3).
- **Read-verified, never executed.** This Linux container has no Swift toolchain. Every verdict comes from reading source, and no claim here was reproduced by running the app. The owner's own rule applies: each claim that can move a scientific number is its own Gate D, and none should be fixed from this list.
- **Independent checks by the lead session** of the four priority-1 claims are below. The other 117 verdicts are one verifier's reading each and have not been cross-checked. Treat them as leads.
- **Machine-readable:** `docs/cloud/2026-09-23/defect-triage.json` holds all 121 rows with full evidence.

## Summary

| Verdict | n |
|---|---|
| CONFIRMED | 83 |
| PARTLY | 23 |
| FIXED | 6 |
| GONE | 5 |
| REFUTED | 3 |
| CANNOT_TELL | 1 |

- **Gate D:** 31 rows flagged, 29 of them CONFIRMED or PARTLY.
- **Priority:** 4 at 1, 35 at 2, 82 at 3.

The verifiers confirmed far more claims than the register's warning ("a large share of automated review claims are wrong") would suggest. Many confirmations are of latent traps: code that behaves as claimed but that no in-app caller reaches today. Each row's evidence says which.

## Priority 1: confirmed, and able to corrupt a result silently or crash on plausible input

| ID | Sev | Verdict | Gate D | Effort | Claim | Evidence (read-verified at HEAD) |
|---|---|---|---|---|---|---|
| D021 | HIGH | CONFIRMED | yes | S | Float32 running sum saturates: whole-stack mean collapses on ordinary-sized datasets | stack.reduce(0, +) on [Float] accumulates in Float32 and only converts to Double afterwards (ParallaxPreprocessing.swift:422). The stack values are normalized to about 1 with 1.0 padding (:369, :414-415), so the running sum stops growing near 2^25 (≈33.5M). Stacks are allowed up to ~134M elements (1 GiB resident, :127, :356-361). Example: a 256x256 scan with 32 px padding and ~700 BF pixels (58M elements) gives stackMean ≈0.57 instead of ≈1. The same pattern appears at ParallaxAlignment.swift:445. py4DSTEM uses numpy's pairwise mean. |
| D031 | HIGH | CONFIRMED |  | S | A session save silently publishes a stripped sidecar when the existing file cannot be opened, destroying BraggVectors, saved results, the replay record and the labels | When the sidecar exists but H5Fopen fails, existingID is quietly nil (BraggVectorEMDWriter.swift:1423-1428). A missing root group is also tolerated (:1449-1452). The rewrite then carries forward no results, replay record, labels or braggvectors (:1448-1498), and the temp file is atomically renamed over the original (:1082-1085). One plausible trigger: another process holds the sidecar open for writing (HDF5 file lock). |
| D070 | MEDIUM | CONFIRMED |  | S | DPC colour-wheel traps (hard crash) on a single non-finite centre-of-mass value | colorWheelRGBA computes hue = atan2(cy,cx) with no finiteness check (DPC.swift:173-181) and hsvToRGB does Int(h6) (:188), which traps on NaN; a NaN value also traps in UInt8(r*255). A pattern containing a +Inf pixel (e.g. gain-normalised data with a dead pixel) gives sumI=Inf and comX=Inf/Inf=NaN in CenterOfMass.metal:57-66. No loader sanitises non-finite pixels, so switching DPC display to Color wheel on such data crashes. |
| D101 | MEDIUM | CONFIRMED | yes | L | The app's CoM component order is transposed relative to py4DSTEM, so the R–Q rotation it reports and exports is the negative of py4DSTEM's — and of its own parallax-fitted rotation | The app transliterates py4DSTEM's rotation/curl formulas with x = column (RotationCalibration.swift:138-164; CenterOfMass.metal:49-64) while reading axes as (Ry,Rx,Qy,Qx) (DatasetDescriptor.swift:39-42), which negates the angle. This is now a tracked open item, 'App R-Q rotation is -py4DSTEM's ... QR_rotation crosses the boundary unconverted' (docs/open-items.md:24-38, reopened 2026-09-23), measured +80.0 vs -80.1 deg on a real file. QR_rotation is imported (AppState+Open.swift:469) and exported (BraggVectorEMDWriter.swift:1690-1697) unconverted. Not a repeat of core-analysis-physics-06. The parallax-rotation part of the claim is not verified here. |

**Lead-session checks on these four:**
- **D021.** `ParallaxPreprocessing.swift:422` and `ParallaxAlignment.swift:444-447` do call `reduce(0, +)` on `[Float]`, which sums sequentially in Float32.
  - numpy reproduction: 58 M float32 samples of N(1, 0.3), summed sequentially in float32, give a mean of **0.579** instead of **1.000** (float64). Exact 1.0 values give 0.289, because the sum saturates at 2²⁴.
  - `stackMean` feeds the reference image (`ParallaxPreprocessing.swift:437`, `ParallaxAlignment.swift:466`) and normalises the error (`:445`, `:479`), so this moves a scientific number. **Gate D.**
  - Whether a real session reaches ≈ 17–34 M stack elements depends on scan size, padding and bright-field pixel count. That has not been measured.
- **D031.** Read at `BraggVectorEMDWriter.swift:1423-1453`: when `h5fopen` of the existing sidecar fails, `existingID` is nil, and the rewrite carries nothing forward. Confirmed by reading. The trigger (for example an HDF5 file lock held elsewhere) has not been reproduced.
- **D070.** Read at `DPC.swift:173-189`: there is no finiteness check before `atan2`, and `Int(h6)` on NaN is a Swift runtime trap. Confirmed by reading. The claim that nothing upstream sanitises a ±Inf pixel is the verifier's; the lead session did not check it.
- **D101.** This is the R–Q sign item already open in `docs/open-items.md`. See `rq-sign-convention.md` in this folder.

## Priority 2, Gate D: confirmed and real; any fix can move a number

| ID | Sev | Verdict | Gate D | Effort | Claim |
|---|---|---|---|---|---|
| D004 | HIGH | CONFIRMED | yes | M | Learned detector: the edge-exclusion rule is applied to each 256 px model window, so on detectors > 256 px there are blind bands at every window seam where no window will accept a peak |
| D006 | HIGH | CONFIRMED | yes | S | A multi-`data_` CIF is silently merged into one crystal: cell parameters from the last block, atom sites and symmetry operations concatenated from all of them |
| D015 | HIGH | CONFIRMED | yes | M | A file- or sidecar-supplied probe radius permanently freezes `minPeakSpacing`: the later measured radius is never adopted, because the "user has not chosen one" guard cannot tell an app-seeded value from a user edit |
| D017 | HIGH | CONFIRMED | yes | S | `publishProduct` takes the product's pixel size from the CURRENT analysis mode, so the scan-domain detector-disagreement map is published and exported with the Bragg map's reciprocal Å⁻¹/px |
| D019 | HIGH | CONFIRMED | yes | M | A single non-finite pixel in a diffraction pattern silently returns zero peaks for that whole pattern |
| D023 | HIGH | CONFIRMED | yes | S | Empty scan positions inject Float.greatestFiniteMagnitude into the clustering-scale median |
| D025 | HIGH | CONFIRMED | yes | S | Selected-area diffraction circle mask is half a pixel off-centre from the ROI drawn on screen |
| D030 | HIGH | CONFIRMED | yes | S | Exported dim vectors pair a defaulted step of 1 with a real physical unit, manufacturing a calibration that was never measured |
| D035 | HIGH | PARTLY | yes | M | Scan-fastest DM4 reads the detector pair in the opposite order from the detector-fastest branch, and the only test covering it is circular |
| D037 | HIGH | CONFIRMED | yes | M | A detector smaller than 256 px whose beam is off-centre is silently truncated by the learned frame — part of the detector is never searched |
| D073 | MEDIUM | CONFIRMED | yes | S | fit1D reports didNotConverge when the seed is already at (or reaches) the optimum |
| D077 | MEDIUM | CONFIRMED | yes | M | Default alignment schedule drops py4DSTEM's repeat pass at the smallest bin |
| D088 | MEDIUM | CONFIRMED | yes | S | Re-referencing wipes `originProvenance` to `.geometricDefault` while a valid recorded mean origin survives and silently becomes the reference origin |
| D098 | MEDIUM | CONFIRMED | yes | S | `to_counts` is applied to the cropped window in Swift and to the whole native pattern in Python — an unmarked deviation that gives each >256-px window its own dose scale |
| D135 | LOW | CONFIRMED | yes | S | The CIF importer's family-classification tolerance is 1000× looser than the model validation it feeds, so a band of cells is rejected with a generic message that hides the real reason |

## Priority 2, no Gate D: confirmed and real, a fix does not move a number

| ID | Sev | Verdict | Gate D | Effort | Claim |
|---|---|---|---|---|---|
| D018 | HIGH | CONFIRMED |  | S | Disk-detection staleness signature and recipe omit the probe kernel's identity, so a Bragg map made with a different kernel is reported as current |
| D020 | HIGH | CONFIRMED |  | S | Hexagonal IPF colour key labels ⟨10-1̄0⟩ and ⟨11-2̄0⟩ the wrong way round — green and blue are swapped against the crystallography |
| D024 | HIGH | CONFIRMED |  | M | Every full-cube VirtualDetector pass runs on the main actor: AppState never wraps them in Task.detached, and `nonisolated async` inherits the caller's actor under this project's settings |
| D033 | HIGH | CONFIRMED |  | M | DM4 parsing has unguarded trapping Int conversions and an unbounded field loop — a corrupt or desynchronised tag tree kills or hangs the process |
| D038 | HIGH | CONFIRMED |  | S | A learned-inference failure on the live overlay is silently answered with CLASSICAL rings while the picker still says Neural net |
| D040 | HIGH | CONFIRMED |  | M | Hand-clicked disk-centre labels are written with `frame: "native"` but are captured in the loaded view's frame, so labels clicked on a cropped or binned view name the wrong detector pixels and scan positions |
| D043 | HIGH | CONFIRMED |  | S | ApertureOverlay's accessibility representation builds a Slider whose ClosedRange can be inverted, trapping the process |
| D044 | HIGH | CONFIRMED |  | S | Pan clamp is still the dead Metal shader's rule, so a zoomed pane can only pan 1/zoom of the way to the image edge |
| D045 | HIGH | CONFIRMED |  | S | A DPC unit test turns a total DPC failure into a skip, on the always-available in-memory demo fixture |
| D046 | HIGH | CONFIRMED |  | M | The ACOM Metal-vs-CPU parity gate compares in-plane angles modulo π, so a 180° divergence in the user-selectable "Metal GPU" backend passes while printing "Metal choices exact" |
| D049 | HIGH | CONFIRMED |  | S | `strain-frame-test` generates its golden from whichever py4DSTEM is installed (0.14.17 here) while asserting source-locks against the 0.14.19 pin; its own error text claims a PYTHONPATH that run.sh never sets |
| D060 | MEDIUM | CONFIRMED |  | M | `Package.swift`'s header says the app target still compiles Core/ and Session/ directly; the project file says it does not, and the 78-path exception list that makes that true is hand-maintained and ungated |
| D065 | MEDIUM | PARTLY |  | M | A promote-and-replay from a detector-cropped or binned rehearsal refuses its own strain/ACOM steps: the executor writes re-referenced disk parameters, the staleness check compares them against the un-re-referenced recipe |
| D071 | MEDIUM | CONFIRMED |  | S | Learned-detector runs record min_absolute_intensity, subpixel and upsample_factor in provenance although refine() applies none of them |
| D078 | MEDIUM | CONFIRMED |  | S | Alignment working-memory guard counts three stacks; six are live |
| D096 | MEDIUM | CONFIRMED |  | S | Rehydrated upsample_factor from a sidecar has no upper bound and reaches an Int(Double) conversion that traps |
| D099 | MEDIUM | CONFIRMED |  | S | Strain staleness ignores the manual g-vector basis, which is an input to the computation |
| D106 | MEDIUM | CONFIRMED |  | M | The frozen hand-labelled test set that is the sole evidence for the shipped 0.7 threshold exists only in a `/private/tmp` worktree |
| D150 | LOW | CONFIRMED |  | S | A session with no recorded origin makes `apply` invent an aperture centre in the wrong frame and can emit a false "beam is not inside this diffraction crop" refusal |
| D152 | LOW | CONFIRMED |  | S | Region-radius Slider forms an inverted range on a scan whose larger axis is a single pixel |

## Priority 3, still open (minor, latent or cosmetic)

| ID | Sev | Verdict | Gate D | Effort | Claim |
|---|---|---|---|---|---|
| D008 | HIGH | CONFIRMED |  | S | The shipped detector's public record claims 20 000 training steps; the retained training log shows the 90-minute cap fired at step 6 500 |
| D016 | HIGH | PARTLY |  | S | A replayed DPC step reports `.published` while publishing nothing — the promote run's summary attests to a result that was never produced |
| D027 | HIGH | CONFIRMED |  | M | CIF importer applies whatever symmetry-operation list the file happens to contain, with no completeness or consistency check |
| D028 | HIGH | CONFIRMED |  | S | ACOM CPU matching silently returns an unmatched or partially unmatched orientation map when a per-worker matcher cannot be built — no failure flag, unlike its DiskDetection twin |
| D032 | HIGH | CONFIRMED | yes | S | `hasEllipse` admits a non-positive semi-axis, so a degenerate ellipse is applied to every Bragg vector while readiness reports "No detector-distortion correction" |
| D036 | HIGH | PARTLY |  | M | The unit gate's end-to-end fixture and every gated `probeSize` fixture are square and centre-symmetric, so an rx/ry or qx/qy swap is undetectable |
| D048 | HIGH | PARTLY |  | S | The "AppState never net positive" rule measures two file paths, so AppState growth in any additional `extension AppState` file is invisible — and 630 such lines already exist on ml/disk-detector |
| D052 | MEDIUM | CONFIRMED | yes | S | `ProbeKernel.synthetic` and the trench in `ProbeKernel.measured` use `y < py/2` for the wrapped (fftfreq) coordinate, where the flat route and NumPy use `(py+1)/2` — one row and one column carry the wrong radius on odd-sized detectors |
| D066 | MEDIUM | CONFIRMED |  | M | iDPC integration and the Bragg-vector-map histogram run on the MainActor, the same shape as the P1 freeze this repo already diagnosed one layer up |
| D067 | MEDIUM | CONFIRMED |  | S | CIF import runs the whole parse, symmetry expansion and O(n²) family verification synchronously on the main actor, with no cancellation |
| D069 | MEDIUM | CONFIRMED |  | S | A signature that cannot be built is reported as "not stale", the same verdict as "matches on every key" |
| D072 | MEDIUM | CONFIRMED | yes | S | Parabolic subpixel refinement runs in Float32 where py4DSTEM explicitly upcasts to float64, with no DEVIATION note |
| D074 | MEDIUM | CONFIRMED |  | S | Ellipse calibration cannot be cancelled; the cancellation token only discards the finished result |
| D075 | MEDIUM | CONFIRMED |  | M | normalizedResidual carries two incommensurable definitions in one field, gated by near-identical thresholds |
| D079 | MEDIUM | PARTLY | yes | S | Parallax and ptychography use the raw aperture centre as the diffraction origin, bypassing `Calibration.referenceOrigin` — the one derivation the type says every caller must use |
| D080 | MEDIUM | PARTLY | yes | M | Parallax and ptychography refuse to run without an R–Q rotation calibration that neither pipeline ever reads |
| D083 | MEDIUM | CONFIRMED | yes | S | `StrainMapping.compute` scores a manual basis over a different observation population than an automatic one (`minRadius: 0` vs the default 2), so the exported `basis_support_fraction` means two different things |
| D084 | MEDIUM | CONFIRMED |  | S | `MetalEngine`'s six compute pipelines are unsynchronized `lazy var`s on a nonisolated process-wide singleton |
| D085 | MEDIUM | CONFIRMED |  | S | The azimuthal blur width is a plan-generation parameter but a hard-coded literal in the matcher, so template and experimental images can be built with different kernels |
| D086 | MEDIUM | PARTLY |  | S | Polar deposition converts a radius to an Int bin index with no finiteness or magnitude guard — a runtime trap on a bad Q calibration |
| D087 | MEDIUM | PARTLY |  | S | writeCalibration silently discards per-position origin maps that fail its validity test, while the export path refuses on the same condition |
| D090 | MEDIUM | PARTLY |  | M | The demo fixture is square on every axis and declares a symmetric origin, so nothing built on it can catch a scan- or detector-axis transposition |
| D091 | MEDIUM | CONFIRMED |  | S | Synthetic demo calibration is stamped .importedFile, so fabricated numbers are labelled as read from a file |
| D093 | MEDIUM | CONFIRMED |  | L | The whole resident-cube path in FourDArray/ResidentCube is unreachable in the shipping app — no caller ever requests .resident |
| D094 | MEDIUM | PARTLY |  | S | The diffraction-pattern LRU is bounded by pattern COUNT, not bytes, and nothing in the app ever clears it |
| D095 | MEDIUM | CONFIRMED |  | S | H5Reader.readProbe materialises the entire probe dataset from file-declared dims, then discards all but slice 0 |
| D097 | MEDIUM | CONFIRMED |  | S | EMPAD and MIB whole-cube reads open, seek, read and close a fresh FileHandle for every single diffraction pattern |
| D100 | MEDIUM | PARTLY | yes | S | The GPU threadgroup argmax and the CPU argmax break ties in different directions, contradicting the shader's own "identical to the reference path" claim |
| D103 | MEDIUM | PARTLY |  | S | The main-thread regression guard exists only for the learned detector; the classical full-scan path — the shipped default and the one that actually froze the app — has none, and the build cannot catch a lost `nonisolated` |
| D104 | MEDIUM | CONFIRMED |  | S | The learned parity gate skips rather than fails on any Core ML load error, and falls back to the repo copy of the asset so a bundle-packaging regression is invisible |
| D105 | MEDIUM | PARTLY |  | S | Every learned-detector parity test silently XCTSkips when the asset cannot load, because the guard tests only that the .mlpackage DIRECTORY exists |
| D107 | MEDIUM | CONFIRMED |  | S | The py4DSTEM source lock is verified by HEAD only — a dirty or de-gitted `References/py4DSTEM-dev` is accepted as "lock present" |
| D108 | MEDIUM | CONFIRMED |  | S | `fetch-py4dstem.sh` verifies nothing once the checkout exists: no content check without `.git`, and no check at all when HEAD already equals the lock |
| D111 | MEDIUM | CONFIRMED |  | S | The C5 AppState/ResultExport growth gate is blind whenever HEAD is a docs-only commit, which is this repo's normal closeout shape |
| D113 | LOW | CONFIRMED |  | S | `LearnedDiskDetector.heatmaps` reads the Core ML output as densely packed and never checks its strides or channel count |
| D115 | LOW | PARTLY | yes | M | The shaders are compiled with -fmetal-math-mode=fast, which voids the NaN reasoning written into OriginMeasure.metal and the NaN robustness OriginCalibration claims for the statistics it consumes |
| D116 | LOW | CONFIRMED |  | S | ActivityLog's two drop rules are textual heuristics that can silently discard a real event |
| D117 | LOW | CONFIRMED |  | S | `AppState.sessionInventory` carries an orphaned doc comment describing a property that was deleted, contradicting the comment directly below it |
| D118 | LOW | PARTLY |  | S | productWorkflowReadiness probes the app bundle on the filesystem every time a view body reads it |
| D121 | LOW | CONFIRMED |  | S | `applyDPCDisplay` returns nil for two different facts — "the display was published" and "this did not run" |
| D123 | LOW | CONFIRMED |  | S | PendingLoad owns a security-scoped URL and a live read Task but has no deinit; release depends entirely on two AppState call sites |
| D124 | LOW | PARTLY | yes | M | Quantitative iDPC forces a square scan step even when the two scan axes are sampled differently |
| D125 | LOW | CONFIRMED |  | S | The sampled-preview label the file's own invariant I4 calls load-bearing prints "every 32th position" |
| D126 | LOW | CONFIRMED |  | S | DatasetPreview.make reports two non-allocation failures as FourDError.allocationFailed |
| D127 | LOW | CONFIRMED |  | S | Full-scan progress fractions can be delivered out of order, and the tile coalescer admits the regression |
| D128 | LOW | CONFIRMED |  | S | fit2D and fitOrigin(included:) index by width*height without checking the array actually has that many elements |
| D129 | LOW | CONFIRMED |  | S | OriginCalibration.run is dead in the app and duplicates tiledRun's calibration logic |
| D130 | LOW | CONFIRMED | yes | S | Q high-pass envelope is applied although py4DSTEM's aberration_correct ignores it |
| D131 | LOW | CONFIRMED |  | S | ProbeKernel.measured traps on a non-finite origin where its sibling .flat returns nil |
| D132 | LOW | CONFIRMED |  | S | RotationCalibration.solve reads 2*width*height floats from com without checking its length |
| D134 | LOW | PARTLY |  | M | Blocking whole-cube compute and the on-screen MTKView renders share one MTLCommandQueue, so a long dispatch serialises ahead of the display command buffers |
| D136 | LOW | CONFIRMED |  | S | A singular metric tensor silently yields latInv = latReal — a reciprocal lattice in Å instead of Å⁻¹, with no error |
| D138 | LOW | CONFIRMED |  | S | Restoring an RGBA result map computes width*height*4 after a guard that only bounds width*height |
| D139 | LOW | CONFIRMED |  | S | Preserved results are re-keyed by kind, so two saved results whose kind attribute is missing collapse into one and the second is dropped without a word |
| D140 | LOW | PARTLY |  | M | An orphaned result_* node is copied as an opaque 'external object' and then collides with a new result of the same kind, wedging every future save |
| D141 | LOW | CONFIRMED |  | S | Result and calibration array sizes are taken from the file with no upper bound, so a damaged sidecar traps on allocation instead of erroring |
| D142 | LOW | CONFIRMED | yes | M | `originFitIsSane` passes vacuously when no probe radius is set, and the reciprocal-metrology gate does not require one |
| D143 | LOW | CONFIRMED |  | S | `CalibrationInvalidation.Field.probeRadius` and `.ellipse` are never produced, so two session-restore guards can never fire |
| D144 | LOW | CONFIRMED |  | S | DM4Error.unsupportedDataType is never thrown; an unsupported pixel type is reported to the user as "no datacube found" |
| D145 | LOW | CONFIRMED |  | S | FourDArray.scanTile validates only the tile's element count and row range, not its declared scan/detector extents |
| D146 | LOW | CONFIRMED | yes | S | H5 EMD dim-vector calibration infers pixel size from the first two samples only, with no uniformity check and a silent drop for descending axes |
| D147 | LOW | PARTLY |  | S | A sidecar with no recorded ptychography method is rehydrated as gradient-descent and reported as an applied setting |
| D148 | LOW | PARTLY |  | S | cancelCurrent() cannot distinguish "already cancelling" from "nothing was running", and the controller keeps reporting a live operation after cancel |
| D149 | LOW | CONFIRMED |  | S | `LearnedDetectionSession.prepare` has a check-then-await gap that can load and compile the Core ML model twice |
| D153 | LOW | PARTLY |  | S | A full-pattern log10 transform runs on the main thread inside a SwiftUI view body, for a histogram that is inside a DisclosureGroup collapsed by default |
| D154 | LOW | PARTLY |  | S | TB1StallProbeTests is inert everywhere: every test in the file skips on a hard-coded absolute path inside the owner's home directory |
| D155 | LOW | CONFIRMED |  | S | `tools/lib/python.sh`'s last-resort fallback accepts a `python3` with numpy but no scipy, contradicting the candidate loop it comments |

## Closed by this pass (FIXED, GONE, REFUTED, CANNOT_TELL)

| ID | Sev | Verdict | Gate D | Effort | Claim | Evidence (read-verified at HEAD) |
|---|---|---|---|---|---|---|
| D002 | CRITICAL | FIXED | yes | S | Ptychography scan positions ignore the calibrated R–Q rotation and transpose | Closed 2026-09-09 through Gate D with an independent refuter (docs/archive/closed-items-2026-09.md:533-545; docs/archive/2026-09-09-review/d002-d003-gate-d.md). At HEAD the positions are rotated about their mean by calibration.rotationRad and swapped on calibration.transpose (PtychographyPreparation.swift:184-200), with the axis mapping and the padding DEVIATION documented at :115-170. |
| D003 | CRITICAL | FIXED |  | S | H5Reader's three attribute readers read the whole attribute into a fixed-size scalar buffer — a multi-element HDF5 attribute overruns it | Closed 2026-09-09 (docs/archive/closed-items-2026-09.md:533-545). attributeIsScalar (H5Reader.swift:893-898) checks H5Aget_space element count == 1 and all three attribute readers call it (:982, :998, :1041). The same missing guard remains in the sidecar reader (BraggVectorEMDWriter.swift:2313, no h5agetSpace), which docs/open-items.md:282-286 tracks. |
| D010 | HIGH | FIXED |  | S | The triage's own port recipe for DiffractionEmbedding omits its build prerequisite, which exists only on the branch | Superseded: the C8 'stay on branch' decision was reversed 09-11 (docs/decisions.md:62) and the port happened. mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift and mac4DSTEMTests/DiffractionEmbeddingTests.swift are on main and wired (App/AppState+DiffractionGroups.swift). The triage doc is archive-only, so a missing prerequisite in its recipe no longer affects anything. |
| D011 | HIGH | FIXED |  | S | The C8 decision to strand the four pure engines rests on a claim the branch's own files and gate rows contradict | Superseded: docs/decisions.md:62 records '09-08 C8 engines stay on branch (reversed 09-11)'. The engines are on main: Core/Analysis/Precipitates/{PrecipitateReflections,PrecipitateSegmentation,PrecipitateStatistics}.swift and Core/Analysis/DiffractionEmbedding.swift. |
| D013 | HIGH | CANNOT_TELL |  | S | The accessibility crash — the one finding status.md names as able to block v3.0.0 — rests on two crash reports that do not exist on this machine | Moot at HEAD: the accessibility crash no longer blocks a release (owner decision 2026-09-11, docs/open-items.md:527), and the entry now says the two crash reports' evidence 'aged off 2026-09-15' (:532-533). Whether they existed on the owner's machine on 09-09 cannot be checked from the repo. Only a new reproduction under an AX client would settle it. |
| D054 | MEDIUM | GONE |  | S | Disk-centre labels written by a branch build are silently erased by any main build, and vice versa — the two designs use different sidecar attribute names | The competing branch design is gone: ml/disk-detector is absent from origin (git ls-remote lists only main and cloud/2026-09-23-precipitate-objects) and its DiskLabelStore design is recorded as superseded by Session/DiskCentreLabels.swift (docs/archive/git-cleanup-2026-09-17.md:70). main uses one attribute, mac4dstem_disk_centre_labels (BraggVectorEMDWriter.swift:34), and preserves it across rewrites (:1491-1500, :1642-1644). Only a sidecar written by an old branch build could still lose labels. |
| D057 | MEDIUM | GONE |  | S | `ml/disk-detector` is 26 commits BEHIND main as well as 27 ahead; its `tools/` tree would resurrect three harnesses main deleted and a 105-line-stale `sources.manifest` | ml/disk-detector no longer exists on the remote: git ls-remote --heads origin returns only main (075c044) and cloud/2026-09-23-precipitate-objects. The main-only directive (CLAUDE.md) and docs/archive/git-cleanup-2026-09-17.md:70,90 record the branch's audit and deletion. |
| D059 | MEDIUM | FIXED |  | S | CONTRIBUTING.md tells public contributors every Core/ change needs a parity fixture; CLAUDE.md explicitly says the opposite, and recent Core/ sessions followed CLAUDE.md | CONTRIBUTING.md no longer says every Core/ change needs a parity fixture: its rules section (CONTRIBUTING.md:61-67) now defers to CLAUDE.md Hard rules (Gate D, Gate B, DEVIATION notes), and grep finds no 'parity fixture' requirement. The clone is shallow, so the commit that changed it cannot be named (last commits touching the file include ee0706c). |
| D061 | MEDIUM | GONE |  | S | Consolidation gate C3 is marked CLOSED but its stated exit criterion fails again on the current status.md, so `/pickup` with no target would re-take a closed gate | The consolidation plan exited 2026-09-11 and now lives only at docs/archive/consolidation-plan.md (C3 CLOSED at :572). /pickup reads docs/status.md and treats closed consolidation gates as history (.claude/skills/pickup/SKILL.md:12,25-28), so a no-target pickup can no longer take C3. |
| D062 | MEDIUM | FIXED |  | S | The crash reports that are the sole evidence for the repo's top open item are not on this machine | The doc now says the evidence is gone: docs/open-items.md:531-533 says 'Two crash reports, evidence aged off 2026-09-15, suspect named', and the item is no longer the top open item (it sits under Accessibility, deferred by owner decision 2026-09-11). Whether the reports exist on any machine cannot be checked from this repo. |
| D110 | MEDIUM | GONE |  | S | Merging ml/disk-detector today red-lines main's own inventory gate, and taking the branch's tools/run-tests.sh would silently delete three of its checks | The ml/disk-detector branch no longer exists (git branch -a lists only main, the current cloud branch and one claude/ branch). docs/archive/git-cleanup-2026-09-17.md:70 audited it as fully re-landed, superseded or retired, and the main-only directive rules out a merge. |
| D120 | LOW | REFUTED |  | S | `publishRestoredProduct` is the one publish site that does not bump `resultVersion`, and every display cache is keyed on it | publishRestoredProduct itself calls replaceProduct without a bump (AppState.swift:345-358), but all four call sites bump right after: Support/ResultExport.swift:803/813 then :825, and AppState+Open.swift:979/989 then :996. Every display cache keyed on resultVersion is invalidated. At most a latent footgun for a future caller. |
| D122 | LOW | REFUTED |  | S | Colormaps.lutRGBA traps (not returns garbage) for count <= 1 | count=1 gives t=0/0=NaN, and sample() then fails every comparison and returns (1,1,1) (Colormaps.swift:26-55), so it yields white with no trap. count=0 returns an empty array. Only a negative count traps (array allocation, :12), and every caller passes a constant 44, 128 or 256. |
| D133 | LOW | REFUTED | yes | S | Analytic aperture kernel and the mask path disagree on the exact-centre detector pixel when inner radius is 0 | The analytic kernel (VirtualAperture.metal:52, strict r2 > rIn2) is used only for the .annulus shape (AppState+ResultPresentation.swift:258-262 -> VirtualDetector.tiledRun -> run :532-542). The mask path for .annulus uses the same strict test (VirtualDetector.swift:583-585, includeInnerBoundary false), so the two agree on the centre pixel at inner=0. The only difference is .circle (inclusive, :580-582) versus annulus-with-inner-0, which follows py4DSTEM make_detector (virtualimage.py:635 circle vs :649-651 annulus); the BF preset maps to .circle (AppState+ResultPresentation.swift:169). |
| D151 | LOW | GONE |  | S | The Bragg-peak CSV export carries no units, no calibration and no frame, so a CSV from a cropped or binned view is indistinguishable from a full-extent one | The Bragg-peak CSV export no longer exists at HEAD: grep -i csv over mac4DSTEM/ and mac4DSTEMTests/ finds only the header comment at ResultExport.swift:5. docs/architecture.md:105,144 still describe a CSV export, which is stale. The claim was a repeat of support-export-08 (docs/archive/2026-08-31-review/README.md:80, "narrowed"). |

## Proposed order (the owner decides)

1. **D021, D070, D031**, each as its own session. D021 goes through Gate D.
2. **D101** follows the owner's R–Q decision (`rq-sign-convention.md`).
3. **Priority 2 without Gate D:** these are mostly single-file S fixes (crashes on edge input, staleness gaps, provenance). The owner's "break every new test first" rule applies to each.
4. **Priority 2 with Gate D:** one Gate D per row, in the owner's science priority order.
5. **Priority 3:** fold into whichever session next touches the file. Mark the closed rows in the register.
