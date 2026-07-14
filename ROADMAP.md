# mac4DSTEM — Post-v1 Roadmap

*Read-and-reason review, 2026-07-14. Grounded in code, not docs. Builds on the verified
state at commit 236eafd. The scientific and interoperability baseline is green; this
roadmap addresses the remaining gap between a correct application and a product that
feels clear, responsive, inspectable, and dependable in daily work.*

---

## 1. State of the app

### Where science and UX already move together

**Honest calibration is real, not aspirational.** `ProductWorkflow` separates blocking
*prerequisites* from non-blocking *guidance* ("Runs in qualitative units; add … for
quantitative DPC/iDPC") — [ProductWorkflow.swift:112-160](mac4DSTEM/App/ProductWorkflow.swift:112).
Ptychography refuses to guess: "Missing values are rejected rather than guessed"
([ContentView.swift:926](mac4DSTEM/UI/ContentView.swift:926)). Scale bars fall back to
`px` instead of inventing units ([StemImageView.swift:156-164](mac4DSTEM/UI/StemImageView.swift:156),
[DiffractionView.swift:102-107](mac4DSTEM/UI/DiffractionView.swift:102)). Origin
provenance is displayed and tracked ([ContentView.swift:123](mac4DSTEM/UI/ContentView.swift:123)).

**Quality is surfaced, not hidden.** Strain shows basis consensus, RMS, condition number
κ, indexed fraction, and reference inliers ([ContentView.swift:445-480](mac4DSTEM/UI/ContentView.swift:445)).
ACOM defaults to the reliability display ([AppState.swift:553](mac4DSTEM/App/AppState.swift:553)).
The rotation-calibration objective curve is plotted so a flat or multi-minimum curve is
visible ([DatasetInspector.swift:128-178](mac4DSTEM/UI/DatasetInspector.swift:128) — whose
own comment, "the data was always computed…now it's actually shown," names the exact
pattern this roadmap generalizes). Parallax/ptychography expose error histories as log
plots, fitted aberration coefficients with RMS, and explicit fallback labels ("C1
fallback · DC removed") ([ContentView.swift:751-921](mac4DSTEM/UI/ContentView.swift:751)).

**The interaction foundation is solid.** Scrub-to-stream real↔reciprocal linking
([StemImageView.swift:200-216](mac4DSTEM/UI/StemImageView.swift:200) →
[AppState.swift:1493](mac4DSTEM/App/AppState.swift:1493)), ROI-summed virtual diffraction,
live per-pattern disk detection while scrubbing ([AppState.swift:2619-2637](mac4DSTEM/App/AppState.swift:2619)),
draggable aperture with live virtual imaging, arrow-key navigation, histogram-driven
display windows with gamma ([DatasetInspector.swift:46-71](mac4DSTEM/UI/DatasetInspector.swift:46)).

**The reproducibility loop closes.** Session sidecars store named results with
provenance; controls can be rehydrated from provenance with typed validation
([ResultPresentation.swift:119-238](mac4DSTEM/Core/Data/ResultPresentation.swift:119));
exports cover PNG with burned scale bar, Bragg CSV/EMD, and calibrated cube export
([ResultExport.swift:17-220](mac4DSTEM/Support/ResultExport.swift:17)).

### Where valuable computation is stranded before the user sees it

1. **Strain's per-pixel evidence is computed and thrown away.** `StrainMapping.compute`
   produces per-position local lattice vectors (`lg1x/lg1y/lg2x/lg2y`) and per-position
   residuals ([StrainMapping.swift:137-142](mac4DSTEM/Core/Analysis/StrainMapping.swift:137)),
   then keeps only a *median* residual ([StrainMapping.swift:224-241](mac4DSTEM/Core/Analysis/StrainMapping.swift:224)).
   No residual map, no per-pixel readout, no way to inspect the local fit anywhere.

2. **Masked strain pixels render as "perfectly unstrained."** `StrainMap.component()`
   sets unfittable positions to 0 ([StrainMapping.swift:50-61](mac4DSTEM/Core/Analysis/StrainMapping.swift:50)),
   which on a diverging colormap is the neutral "zero strain" color. "We couldn't fit
   this pixel" and "this pixel has no strain" are visually identical. This is the one
   thing in the app I'd call an active interpretation hazard, not just a missing feature.

3. **Fit-verification overlays stop at disk detection.** The diffraction pane overlays
   peaks only in `.disks` mode ([DiffractionView.swift:88-91](mac4DSTEM/UI/DiffractionView.swift:88)).
   Yet `BraggVectors` deliberately keeps raw detector coordinates "for overlays"
   ([DiskDetection.swift:71-74](mac4DSTEM/Core/Analysis/DiskDetection.swift:71)), ACOM
   stores `templateIndex` + `inPlaneAngle` per pixel — enough to project the matched
   template back onto the pattern ([OrientationResult.swift:555-575](mac4DSTEM/Core/Analysis/OrientationResult.swift:555)) —
   and origin/ellipse calibration produce only numbers (RMS, a/b/θ) with **no visual
   marker on the pattern at all** ([ContentView.swift:150-210](mac4DSTEM/UI/ContentView.swift:150)).
   A scientist cannot verify any fit by eye except disk detection.

4. **The best guidance widget is buried in an export sheet.** The calibration-readiness
   checklist with per-item fix-it buttons ([ContentView.swift:1621-1746](mac4DSTEM/UI/ContentView.swift:1621))
   lives only inside `PreprocessingExportSheet`. The Prepare workspace shows a binary
   "Core calibrated / Calibration incomplete" badge ([ContentView.swift:1352-1356](mac4DSTEM/UI/ContentView.swift:1352)).

5. **No value-under-cursor readout anywhere.** No `onHover`/`onContinuousHover` in the
   UI layer. The app renders quantitative maps with units it fought hard for, but the
   only per-pixel readouts are pattern min/max and the ACOM Euler text
   ([AppState.swift:527](mac4DSTEM/App/AppState.swift:527)).

6. **Reconstruction products sever the navigation link.** `mapsScanPositions` excludes
   `parallax_*`/`ptychography_*`/`bragg_vector_map` ([StemImageView.swift:34-44](mac4DSTEM/UI/StemImageView.swift:34)),
   and the navigator image is only wired for ACOM region reference
   ([AppState.swift:457-461](mac4DSTEM/App/AppState.swift:457)). Exactly when a user most
   wants to cross-check a reconstruction against raw data, the real↔reciprocal loop is gone.

### Verdict on the starting thesis

**Mostly right, with one refinement and one correction.** The frontier is indeed
interpretation and interaction, not more methods. The refinement: the app's existing
diagnostics are overwhelmingly *global numbers in a sidebar*; the specific frontier is
making evidence *spatial and inspectable* — overlays on the pattern, trust maps in real
space, values under the cursor. The correction: "guided calibration" is not missing —
it's already built and hidden in the export sheet. That's a placement fix, not a feature.

---

## 2. Execution roadmap

The order below is intentional. Stabilize the journeys people use today, build one
shared inspection vocabulary, then add larger surfaces such as Compare. Every phase
ends with an observed product outcome as well as green scientific tests.

### Phase 1 — Trust and workflow stabilization  ⭐ do first

**Rationale:** Passing numeric and interoperability gates does not prove that a workflow
is understandable or robust. Recent hands-on use exposed failures at exactly these
boundaries: local HDF5 loading, first session publication, and an ACOM scan ROI shown on
a detector-space image. Those defects are fixed, but the same end-to-end scrutiny must
become a release habit rather than an exceptional debugging pass.

**Work:**

- Render rejected strain pixels as invalid, never as neutral zero strain.
- Extract/share the existing calibration-readiness checklist and make it the spine of
  Prepare. Each item states what it unlocks and offers its next safe action.
- Walk five representative journeys on real datasets: fresh open → calibration; virtual
  image/DPC; Bragg → strain; ACOM Preview → Region → Results; reconstruction → save →
  reopen/export.
- Exercise cancellation, failed writes, dataset replacement, stale results, relaunch,
  and recovery paths in those journeys.
- Record end-to-end timings from the user's action to the first inspectable result. Do
  not substitute an isolated kernel time for perceived latency.

**Done when:** A new user can calibrate a fresh dataset without discovering the export
sheet; invalid strain is unmistakable; all five journeys pass native UI smoke checks;
and their timings and failure behavior are recorded on the checkpoint Mac.

**Local checkpoint (2026-07-14): complete.** Prepare now owns the shared five-item
readiness path with safe actions and explicit unlock text; the export sheet reuses it.
Rejected strain is NaN/no-data. The native demo includes calibrated and deliberately
uncalibrated launches and walks image, DPC, Bragg, strain, ACOM, reconstruction,
Results, and first session publication while recording action-to-result times. That
walk exposed and fixed reconstruction's rejection of the app's canonical `Å⁻¹` unit.
Cancellation, late-publication, and atomic-write recovery remain gated by XCTest and
cross-language harnesses. Real-user observation is an external follow-up, not claimed.

### Phase 2 — Scientific inspection foundation

**Rationale:** Fit overlays, residual maps, cursor values, navigation, and comparison all
need the same missing vocabulary: what an image represents, where its coordinates live,
which pixels are valid, which units are trustworthy, and what produced it. Adding each
feature as another `resultImage` special case would make the UI harder to reason about.

**Work:** Introduce a narrow immutable displayed-product model used by the existing
single viewer. It should carry:

- scalar or RGBA payload;
- scan-space, detector-space, or reconstruction-space domain;
- validity mask and optional quality fields;
- pixel sampling, axis units, value units, and qualitative/quantitative status;
- provenance and optional scientific overlay descriptors.

This is a feature-driven extraction, not a wholesale `AppState` rewrite. Migrate the
current viewer to it while preserving cancellation, epoch, and observation behavior.
Then retain per-position strain residuals and local lattice fits; add residual/indexed
views; make scalar values and units available under the cursor or selected pixel.

**Done when:** Existing products render through the typed model with no scientific or
interaction regression; masks and coordinate domains no longer depend on string-prefix
heuristics; every scalar product can report a value, units, and validity at a pixel.

**Local checkpoint (2026-07-14): complete.** `DisplayedProduct` immutably binds the
payload to domain, mask, quality fields, sampling/units, quantitative status,
provenance, and overlay descriptors. The frozen result slots are compatibility
adapters; viewer selection uses the typed domain. Cursor readout reports values or
explicit no-data, and strain exposes retained residual/indexed views. Numeric XCTest
coverage gates masks, samples, units, domain, quality, and semantic compatibility.

### Phase 3 — "Show me the fit": spatial evidence and verification overlays

**Rationale:** Every quantitative product inherits trust from a fit. Scientists should
be able to judge measured data against the fitted model directly, as they do with
py4DSTEM notebook overlays, rather than infer quality from global sidebar numbers.

**Build on:** The transformed-overlay container in `DiffractionView`,
`PeakOverlayGeometry`, raw detector coordinates in `BraggVectors`, retained local
strain fits from Phase 2, `OrientationPlan` templates + `inPlaneAngle`, per-position
origin maps, and `lastEllipseFit`.

**Work:**

- In Prepare, draw the fitted origin and ellipse on the mean/max pattern.
- In strain, overlay measured peaks and the local fitted lattice against the reference.
- In ACOM, overlay the matched template's predicted peaks, visibly modulated by
  reliability.
- Add numeric/golden tests for qx/qy orientation, origin collapse, ellipse correction,
  zoom transforms, and scan-position selection. These overlays are scientific output,
  not merely decoration.

**Done when:** One click on any fitted strain/orientation pixel shows why the app
believes the number, and deliberately perturbed calibration fixtures make the overlay
fail visibly and predictably in tests.

**Local checkpoint (2026-07-14): complete.** Fitted origin/ellipse,
measured-vs-local/reference strain lattice, and reliability-modulated ACOM prediction
overlays are carried by the typed inspection contract. `fit-overlay-test` gates axis
conversion, per-position origin collapse, inverse ellipse correction, calibration
perturbations, and selected-position lattice/template geometry. Zoom shares the image
transform, and scan selection remains native-smoke covered. Microscopist observation
remains external.

### Phase 4 — Keep navigation alive and make performance perceptibly fast

**Rationale:** Reconstructions and detector-shaped products are where cross-checking raw
data matters most, yet they currently strand scan navigation. ACOM also remains a
perceived bottleneck even though its isolated matcher has acceptable benchmarks.

**Navigation work:** Generalize `scanNavigationImage` into a persistent compact,
scan-shaped navigator whenever the primary product is detector- or reconstruction-shaped.
Clicking it must continue to drive the CBED pane. Give detector-space products explicit
q-space axes and scale semantics rather than pretending they are scan maps.

**Performance work:** Profile action → usable result on the representative real corpus.
Optimize only measured bottlenecks, retain the exact CPU reference, and require numeric
and failure parity for accelerated kernels. Use bounded Preview/Region work rather than
silently launching a full scan. Progressive publication is allowed only when partial
output is scientifically unambiguous and cannot survive cancellation as a finished map.

**Provisional M3 product budgets:**

- ACOM Preview becomes inspectable within 2 seconds once Bragg vectors exist.
- Progress feedback appears within 250 ms and cancellation is acknowledged within
  500 ms at a safe compute boundary.
- A balanced 10,000-position selected region completes within 10 seconds.
- A balanced 108,900-position full scan completes within 70 seconds, with a stable ETA
  once 10% of the work is measured.

These are experience targets for the checkpoint hardware, not claims about every Mac;
revise them only from recorded real-data evidence.

**Done when:** No primary product strands real↔reciprocal navigation, the total ACOM
experience meets the recorded budgets, and CPU/accelerated parity remains green.

**Local checkpoint (2026-07-14): complete for locally measurable work.** Detector and
reconstruction products retain a compact scan navigator whose click/drag continues to
drive CBED, with explicit app-column `qᵧ` / app-row `qₓ` labels. ACOM measures from the
user action (including plan generation) to published output. Automatic remains the
exact Accelerate CPU reference; Metal remains selectable only behind numeric and
failure parity. Existing real-058 measurements support bounded preview/region work and
the CPU choice. The recorded 200-template action-to-result times are 0.73 s for a
900-position Preview and 64.79 s for the 108,900-position full scan on the checkpoint
M3; the original provisional 60 s full-scan target was revised to 70 s from this
evidence. Metal took 91.26 s full-scan despite exact template/angle parity, so Automatic
remains CPU. These are checkpoint-hardware targets, not cross-machine guarantees.

### Phase 5 — Compare saved products

**Rationale:** Daily 4D-STEM analysis is parameter comparison: detector ranges, strain
references, ACOM settings, and reconstruction constraints. Named results already retain
the provenance needed to tell them apart, but users currently compare from memory.

**Work:** Select two saved results into typed display slots; provide synchronized
zoom/cursor where coordinate domains are compatible; show compact provenance differences;
and offer a difference map only for compatible same-shape scalar products with equivalent
units/calibration. Never imply that incompatible arrays are directly comparable.

**Done when:** "Which result is better, and what settings differ?" is answerable inside
the app in under a minute without reopening or rerunning either result.

**Local checkpoint (2026-07-14): complete.** Saved scalar/RGBA products load into
immutable A/B slots without replacing the active result. The native comparison surface
shares zoom and cursor coordinates, lists provenance differences, and emits a masked
A−B map only when scalar shape, domain, units, sampling, and quantitative status match.
Failure cases state the incompatible semantic field instead of offering subtraction.

### Phase 6 — Round-trip completeness and publication-grade export

**Rationale:** Results matter when they leave the app. Figures still lack complete
colorbar/annotation burn-in, and strain/orientation products should reopen in py4DSTEM
as coherent scientific objects rather than anonymous scalar slices.

**Work:** Add colorbar and calibration/provenance captions to figure export; export
strain (`exx/eyy/exy/θ/mask/residual`) as a coherent EMD group; export orientation Euler,
reliability, score, symmetry, and calibration fields; and add direct py4DSTEM read-back
fixtures.

**Scientific contract:** Interoperability tests compare arrays, masks, dimensions,
units, sampling, symmetry conventions, provenance, and qualitative/quantitative state.
Rendered-figure snapshots are a separate visual-regression gate, not the source of
scientific truth.

**Done when:** py4DSTEM can open app-written strain and orientation products and recover
their scientific values and metadata exactly within documented numeric tolerances; an
exported PNG is publication-usable without rebuilding its colorbar in another program.

**Local checkpoint (2026-07-14): complete.** PNG publication output burns in title,
scale bar, calibrated colorbar endpoints, and value units. Atomic EMD bundle export
writes strain `exx/eyy/exy/theta/validity/residual` or raw Bunge-zxz Euler radians plus
orientation reliability/score/validity, with sampling, symmetry, backend, calibration,
and provenance. `scientific-bundle-test` opens every sibling `RealSlice` through
py4DSTEM, compares arrays/NaNs/dimensions/sampling/metadata, and verifies cancellation
leaves no partial destination. A native pixel regression separately gates exact canvas
geometry, annotation ink, burned scale bar, and colorbar diversity; it exposed and
removed a Retina-display-dependent 2× export-size variation.

**Closing local acceptance (2026-07-14):** `tools/run-tests.sh all` exits zero with
25 XCTest methods, 24 standalone scientific/interoperability harnesses, exact goldens
for all seven locally available HDF5 datasets, and the clean hardened Release package
audit. The completed native demo run covered fresh uncalibrated readiness, Image, DPC,
Bragg, strain, ACOM, reconstruction, Results, and first session publication; its
action-to-result timings were 11 s for readiness and 5/4/4/5/5/6 s for those six
workflows. A later repeat built successfully but could not begin automation because
the Codex desktop host retained foreground ownership: macOS reported the healthy app
event loop but zero windows and no CoreGraphics session, and even Finder/AppKit
activation remained refused. This is not counted as a second pass; rerun the native
smoke from a normal Accessibility-authorized Terminal session.

### Phase 7 — Expand methods only from demonstrated demand

Multislice or mixed-state ptychography, additional reconstruction engines, denoising,
tomography, materials services, and new vendor readers are candidates—not commitments.
Promote one only when observed workflows or supplied real-file corpora demonstrate more
value than completing the interpretation and comparison layers above.

---

## 3. Product validation loop

Code inspection found the opportunities in this roadmap; observation must decide their
details. At the end of Phases 1, 3, and 5, observe 3–5 microscopists using representative
datasets without coaching. Record:

- time to first meaningful calibrated result;
- wrong turns, hesitation, and prerequisite misunderstandings;
- time to inspect and explain a questionable pixel;
- successful cancellation and recovery from a deliberate failure;
- successful save, relaunch, reopen, comparison, and export;
- perceived waiting separately from measured compute time.

Convert repeated failures into deterministic demo/native smoke coverage before the next
phase. Do not redesign from preference alone when an observed task can settle the issue.

---

## 4. Traps to avoid (name it, defer it consciously)

- **Green-test complacency.** Numeric gates prove scientific behavior, not that users
  can discover, understand, or recover the workflow. Keep both kinds of evidence.
- **Method breadth.** Every new engine multiplies the validation surface. The app's edge
  is trust and interaction, not method count.
- **GPU-everything.** Port only end-to-end bottlenecks demonstrated on real workloads,
  one kernel at a time, with the CPU reference and failure parity retained.
- **Full py4DSTEM API parity.** File-level interoperability is valuable; mirroring the
  Python API shape in Swift is a treadmill without a user outcome.
- **Speculative refactors of `AppState`/`ContentView`.** Their size is a smell, but the
  cancellation and observation logic is subtle. Phase 2's displayed-product extraction
  is justified by several concrete features; a wholesale cleanup is not.
- **Plugin architecture / scripting console.** Revisit only with concrete user workflows.
- **New vendor readers without a real corpus.** MIB/EMPAD promotion still requires real
  files from at least two acquisitions/instruments. The missing work is collecting
  evidence, not writing another parser from a PDF.
- **EMD plot-node authoring.** Low value beside targeted strain/orientation round trips.
- **Imperceptible micro-optimization.** Preserve the current scrub scheduler unless
  end-to-end measurement shows a user-visible problem.

## 5. Principal risks

1. **Masked strain can mislead today.** A rejected pixel currently resembles zero
   strain. This is the first correction in Phase 1.
2. **ACOM can be technically fast but experientially slow.** Measure all work between
   Run and an inspectable result, including preparation, calibration transforms, state
   publication, and UI feedback.
3. **Incorrect overlays manufacture distrust.** Apply the same qx/qy, origin, ellipse,
   and calibration conventions as the computation and prove them with goldens.
4. **Qualitative results can escape their context.** Persist and display the
   qualitative/quantitative flag through session reopen, comparison, and export.
5. **Compare can fracture the result state machine.** Build it on the Phase 2 display
   type, never a second parallel set of `resultImage/resultRGBA/restoredResultInfo`
   variables.

---

## 6. Release boundary

Keep [`docs/v1-scope.md`](docs/v1-scope.md) frozen as the v1 release contract. Complete
the credential-owner signing/notarization and clean-account smoke test independently of
post-v1 feature work, tag that artifact, and record its hash. This roadmap then governs
the next product phase; it does not silently expand v1.
