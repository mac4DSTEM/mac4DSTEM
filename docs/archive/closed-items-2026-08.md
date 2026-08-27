# Closed items — 2026-08 archive

Moved here **verbatim** from [`docs/open-items.md`](../open-items.md) on
2026-08-26 (M1's tidy session, T3), enforcing that file's own rule that
closed items do not stay there. Each entry appears exactly as it last stood
in the live file; where something live leans on one, the live file carries
a tombstone pointing here. **History, not guidance.** One mechanical change
was made in the move: relative links inside entries are re-based to this
file's location so they keep their original referents (two links to
`s1-sidecar-under-the-sandbox.md`); no other characters changed.

---

## Blocker on L3, created by L2 — closed 2026-08-18

### ~~Blocker on L3, created by L2~~ — **CLOSED 2026-08-18**

`ResidentCube` carries its `LoadSpecification` and `matches` compares it, so two
crops of equal extent at different offsets — identical `filePath`, `datasetPath`
and `shape` over disjoint pixels — cannot be confused for one another. Pinned in
`tools/virtual-detector-residency`; reverting `matches` to shape-only fails it
1/1.

**Amended 2026-08-18, after the reader threading landed and an adversarial
review checked this claim.** The first version of this entry said
`FourDArray.resident(for:)` "is the compute-side accessor that applies the
check". It is not, and the difference matters to anyone reading it as a live
guard: `FourDArray.view` is now a `let`, and the array is the only thing in the
app that constructs a `ResidentCube` — from its own view — so the specification
comparison is **tautological at every call site**. It is always comparing a
value with itself.

What actually closes the blocker is structural, and it is stronger than a
runtime check: **a different specification means a reopen**, which means a
different `FourDArray` holding a different buffer, so one array can never hold a
buffer for a crop other than its own. The live guard inside `resident(for:)` is
`describesThisView`, which refuses a descriptor that is not this array's view —
a stale one from a previous dataset, or a synthetic one built for a sub-range.
The specification comparison stays as defence in depth against a future stage
that makes the view mutable, and both it and `ResidentCube.matches` now say so
in the code.


---

## Free-space preflight in tools/run-tests.sh — done 2026-08-18 (S0)

- **A free-space preflight in `tools/run-tests.sh`** — **DONE 2026-08-18 (S0).**
  `require_free_space`, 8 GB for the `xcodebuild` modes and 4 GB for the
  harness-only ones, failing with "need N GB free for X, have M GB" before any
  build starts. The floors are margin, not measurement; the reasoning and the
  zsh `local path` trap that broke the first version are in the code comment.

---

## Strain presented in the diffraction frame — closed by S8, 2026-08-25

- ~~Strain is computed and exported in the DIFFRACTION frame, labelled only
  εxx/εyy/εxy, and displayed over scan coordinates.~~
  **Closed by S8, 2026-08-25** (owner decision: scan frame, live-derived).
  The stored map stays detector-frame; display and export re-express it in
  the scan frame from the CURRENT calibration (`Core/Analysis/
  StrainFrame.swift`, the `applyDPCDisplay` pattern — a later rotation
  calibration updates what is shown, never silently desyncs), matching
  py4DSTEM's own split: calibrated Bragg vectors are rotated before the fit
  when `QR_rotation` exists (`braggvectors.py:528–545`), and without it
  py4DSTEM warns and stays detector-frame. With no measured rotation the app
  presents detector x/y and SAYS so — controls row, burned caption
  (`strain_frame=detector`), and provenance (`strain_frame_reason`). Every
  strain carrier now names the frame from one composition site
  (`strainFrameProvenance`); the caption additionally carries
  `qr_rotation_deg`. Pinned by `tools/strain-frame-test` (vendored
  `get_rotated_strain_map` executed live + refit-from-rotated-vectors ground
  truth + hand answers; NC1–NC5 negative controls) and 30 unit tests, each
  observed failing under a discriminating mutation. **DEVIATION recorded in
  `StrainFrame.swift`:** py4DSTEM's median reference
  (`get_reference_g1g2`) is not rotation-equivariant on majority-free
  mixtures, so its calibrated rotate-then-fit path differs there from its
  own tensor-rotation path (up to ~2×10⁻² strain at 37.2° on the NC5
  fixture — εxy the largest; and the −64° "sign-opposite reference pair" is
  basis relabeling PLUS ~0.22 px of median drift superimposed, per the Gate
  B reviewer's re-measurement);
  the app's presentation keeps the measurement identity. **Known residual
  (Gate B finding 5):** a strain result RESTORED from a pre-S8 sidecar
  carries its saved provenance verbatim, which has no frame keys — its
  display and re-export are frame-silent (honest-by-omission; the pixels
  are provably detector-frame since no rotation path existed when they were
  saved). Synthesizing `strain_frame=detector` at the restore site would be
  a true claim if anyone wants it closed. On-screen verification: Track B
  rows **F1.28/F1.29** (queued; nothing seen on screen yet).

---

## Physical iDPC did not require a quantitative origin fit — closed by S7, 2026-08-25

- ~~Physical iDPC does not require the origin fit to be quantitative.~~
  **Closed by S7, 2026-08-25:** both call sites now ask one owner
  (`App/SessionGates.originQuantitativeRefusal`, which IS
  `Calibration.originFitRefusal`); a refused fit renders qualitative iDPC and
  the DPC controls quote the refusal (`AppState.idpcOriginFitRefusal`).
  Track B row F1.25 drives it on `downsample_Si_SiGe_exp`.

---

## DPC.integrateIDPC returned a zero-filled image — closed by S7, 2026-08-25

- ~~`DPC.integrateIDPC` returns a zero-filled image on invalid input.~~
  **Closed by S7, 2026-08-25:** every failure throws a typed `DPC.IDPCError`
  naming the precondition; `applyDPCDisplay` clears the image and presents on
  a throw; `tools/idpc-test` gained the negative controls.

---

## Tile read errors reported as an FFT failure — closed by S7, 2026-08-25

- ~~Disk-detection tile read errors are reported as an FFT failure.~~
  **Closed by S7, 2026-08-25:** the tiled `detectAll` returns nil only on
  cancellation and otherwise throws `DiskDetection.FullScanError` naming the
  scan rows and the underlying error; `runDiskDetection` reports it verbatim.
  `TiledDiskDetectionErrorTests` pins the attribution with a failing source.

---

## Promote and the recovery record disagreed about frames — fixed 2026-08-24 (S5)

  - ~~**Promote and the recovery record disagree about frames.**~~
    **FIXED 2026-08-24 (S5).** `DatasetRecoveryRecord` now carries the load
    specification its coordinates are expressed in; the restore applies a
    position only in its own SCAN frame and inside the extents — it **never
    clamps** (the clamp was the fabrication) — and a successful promote
    re-stamps the record so the persisted pair describes the promoted view.
    Pinned by `SessionReplayTests` frame-rule tests, each observed failing
    under a discriminating mutation; old persisted records without the frame
    still decode (pinned on the production coder).

---

## Burned-in caption truncated on exported figures — closed by S7, 2026-08-25

- ~~The burned-in caption on exported figures truncates.~~ **Closed by S7,
  2026-08-25:** the caption wraps and the figure grows to hold it, and the
  full provenance record additionally travels as machine-readable PNG
  metadata (a JSON `Description` chunk beside `Title`/`Software`) —
  `AppState.exportedImageProvenanceRecord` / `pngProperties`, round-trip
  pinned through a real file by `ExportProvenanceTests`. Track B row F1.24.

---

## A sidecar that opens fine could fail to restore — closed 2026-08-19 (S1)

- ~~**A session sidecar that provably opens fine can still fail to restore.**~~
  **CLOSED 2026-08-19 in S1.** Cause: the 2026-08-14 bundle-identifier change
  (`1e5727d`) gave the app a new, empty sandbox container, so no session bookmark
  resolved and the fallback read of the derived sibling was refused by the sandbox
  — **observed at 09:34:27, `errno = 1`/EPERM**, not inferred. Fixed by the seam
  `App/SessionSidecarLocator.swift`. The full investigation — five hypotheses, the
  pre-registration written before its answer was known, and the two refutations
  that changed the outcome — is in
  [`docs/archive/s1-sidecar-under-the-sandbox.md`](s1-sidecar-under-the-sandbox.md).

  **Three things it turned up are still open and unowned — the next three items.**

---

## A save after a failed crop restore erased the crop — closed by S7, 2026-08-25

- ~~A save after a FAILED crop restore erases the sidecar's crop and
  mislabels its preserved results (S5 Gate B-lite F9).~~ **Closed by S7,
  2026-08-25:** `SessionGates` (S7's seam) records the failed restore on
  both branches — the does-not-fit branch used to report only into the
  `statusText` channel S1 measured as unreadable, and now also renders in
  the dataset inspector — and `sidecarRewriteRefusal()` blocks all three
  rewrite entry points (calibration save, result save, result removal)
  with the failure and its remedy named. The unreadable case's remedy
  works now too: a same-file pick in **Change…** re-grants access instead
  of being discarded (F1.3h's shape). Track B rows F1.26/F1.27; the flag
  is session-scoped and clears on reopen, pinned with mutations by
  `SessionGatesTests`.

---

## Save Calibration never persisted the access grant — fixed 2026-08-19 (Track B F1.3h)

- ~~**"Save Calibration to Session Sidecar" wrote the file but never persisted
  the access grant.**~~ **FOUND BY TRACK B F1.3h AND FIXED, 2026-08-19.** Of the
  two publish paths, only `saveCurrentResultToSessionSidecar` stored a bookmark,
  so a calibration save granted access for that launch alone and the next launch
  hit the C10 failure again — while S1's own refusal message named that very path
  as the remedy. Both paths now share one `rememberSidecarGrant`. **No automated
  test could have caught it** (it needs a save panel and a real HDF5 write, and
  the defect was a missing call, not wrong logic) — the narrative is in
  [`docs/archive/s1-sidecar-under-the-sandbox.md`](s1-sidecar-under-the-sandbox.md).

---

## No way to rename or relocate a sidecar — fixed 2026-08-24 (S4)

- ~~**Once a sidecar grant exists there is no way to rename or relocate it.**~~
  **FIXED 2026-08-24 (S4).** Both affordances the item asked for landed:
  **File ▸ Save Session Sidecar As…** and a **Change…** button beside the
  sidecar name in the inspector. The panel opens prefilled with the current
  location; an existing sidecar is **copied** to the new URL (never moved —
  the original is deliberately not deleted), the seam is retargeted via
  `adopt` + `remember`, and a failed copy reports which half happened rather
  than pretending either way. File half pinned by
  `mac4DSTEMTests/SidecarRelocationTests` (6 tests, each observed failing
  under a discriminating mutation). **Gate A caught a destructive defect in
  the first version:** the same-file guard compared path strings, so a
  case-only rename on default APFS (or a symlink alias) would have
  remove-then-copy **deleted the only sidecar**; the guard now compares
  `fileResourceIdentifier`, pinned by a symlink-alias test that reproduced
  the deletion against the mutation. Gate A also added the inventory
  re-read after a retarget (so a failed copy shows an empty section rather
  than the old file's results under the new name). **Known residual, stated
  in the status message:** a retarget made before any save exists has no
  file to bookmark, so it survives only until the next dataset change — the
  first real save persists it. The stranded
  `calibrationData_bullseyeProbe.mac4dstem.h5` on the Desktop can now be
  brought home by the owner through the new menu item. **Unverified on
  screen:** Track B rows **F1.20** (the affordance) and the resurrected
  F1.3i check behind it.

---

## Opening a sidecar directly dumped a 60-line path wall — fixed 2026-08-24 (S4)

- ~~**Opening a `.mac4dstem.h5` sidecar directly dumps a 60-line wall of tried
  paths and never says what the file actually is.**~~ **FIXED 2026-08-24 (S4),
  with two recorded limits and one open owner question.**
  `H5Reader.discoverPrimaryDataset` now checks `mac4dstem_session_schema`
  before answering "no dataset" and throws a dedicated
  `H5Error.sessionSidecarOpened` — one sentence naming the file as a session
  sidecar and suggesting the sibling (`<stem>.h5`) when the name follows the
  convention; and `noDatasetFound`'s path wall is capped at 8 + "and N more"
  for every other file of that shape. Pinned by
  `mac4DSTEMTests/SidecarRecognitionTests` (fixtures written by the
  production writer; the recognition test failed against the first, wrong
  implementation — the attribute lives on `braggvectors_root`, not the file
  root — and again under a revert of the writer fix below).
  **Found while fixing it:** the writer only stamped the schema attribute
  when result nodes existed, so a **calibration-only sidecar carried no
  identity marker at all** — exactly the 8.9 kB file the owner double-clicked
  twice. The stamp is now unconditional (nothing reads it to mean "has
  results"; the inventory reads `mac4dstem_result_nodes`).
  **Gate A refuted three parts of the first version, all fixed in-session:**
  (a) the suggested sibling asserted a `.h5` extension the naming rule never
  guaranteed — a `.dm4` user would have been sent hunting for a file that
  never existed; the suggestion is now the extensionless stem. (b) the
  format literals were duplicated reader/writer "because nine harnesses
  compile the reader without the writer" — true of a new file, not of
  `Core/Data/HDF5Types.swift`, already on every relevant source list, where
  `SessionSidecarFormat` now holds them once. (c) the new error case would
  have **re-broken `real-data-acceptance` exactly the way #43 did** (its
  catch matched only `noDatasetFound`, and the checked-in training sidecars
  carry the attribute); the harness now skips the new case under the same
  input-not-error rule. **Limit:** sidecars written before S4 with
  calibration only remain unrecognisable — they get the capped list, not
  the sentence. **Still open, owner decision (TB1):** a distinguishing
  extension for sidecars, or excluding `*.mac4dstem.h5` from the open
  panel's default filter — a naming-convention change S4 had no mandate to
  make. Track B row **F1.21**.

---

## Configurator: crop cost unsaid, direct beam croppable — fixed 2026-08-24 (S4)

- ~~**The configurator never says what a detector crop COSTS, and it will let
  you crop the direct beam off the detector without a word.**~~
  **FIXED 2026-08-24 (S4).** The panel now carries the crop-vs-bin cost caption
  (crop cuts angular *range*; bin coarsens angular *sampling*, costing the
  sub-pixel disk positions strain is fitted from), and a detector crop that
  excludes the sampled preview's brightest region **disables Load** with a
  refusal naming the beam's position and the crop's extent —
  `PendingLoad.directBeamRefusal`, pinned by
  `mac4DSTEMTests/PendingLoadConfiguratorTests` (gate-inversion,
  finite-filter and flat-guard mutations each observed failing). **Gate A
  strengthened it three ways before it landed:** the gate consults
  `LoadView.readDetectorCrop` — the rectangle actually read, bin trim
  included — never the requested crop (a beam in the trimmed remainder, or
  dropped by a bin's edge trim with no crop at all, is now refused; both
  cases pinned); the gate is enforced in `commitPendingLoad` itself, not
  only by the Load button's `.disabled`; and a **flat** mean pattern
  (vacuum/flat-field) counts as no evidence rather than a beam at (0,0),
  which would have blocked every crop of a calibration cube. **Stated
  limit, not hidden:** the beam proxy is the mean pattern's brightest
  pixel, so a beam-stopped or hot-pixel acquisition could still be refused
  a legitimate crop with no override. **Owner question, queued for TB1:**
  should such a refusal offer a "load anyway"? (S7's policy-owner seam is
  also where this gate and `CalibrationReReference`'s should become one
  policy with two severities.) Track B rows **F1.17/F1.18**; F1.7 is
  superseded by F1.18 (the invalidation it watched for is now unreachable
  from the configurator). The original analysis table follows for the
  reasoning record.

  Found by the release owner driving the build, 2026-08-19 — his question was
  "why is cropping in there at all, instead of only 2x/4x binning?", which is
  the right question to ask of a control that explains neither of its two
  reductions.

  Both reductions are correct and both mirror py4DSTEM
  (`crop_data_diffraction` / `bin_data_diffraction`,
  `References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:139,155`), but they
  trade against **different** things and the panel presents them as siblings:

  | | reduces | costs | right when |
  |---|---|---|---|
  | detector **crop** | angular RANGE (max scattering angle) | any scattering outside the box | the useful disks sit in a sub-region of a much larger detector |
  | detector **bin** | angular SAMPLING (resolution) | sub-pixel disk-position precision, so strain precision | you need the full angular range but it is oversampled |

  So they are not alternatives: strain mapping wants crop-not-bin (binning
  directly degrades the disk-position precision the strain basis is fitted
  from), while a wide-annulus ADF wants bin-not-crop (cropping cuts exactly the
  high angles the signal lives at). The panel says neither.

  **The safety hole is the sharper half.** `CalibrationReReference.apply` already
  refuses well when the beam falls outside a crop — it nils the origin and names
  the reason ("the direct beam is not inside this diffraction crop. Widen the
  crop or re-fit the origin on this view"), for both the fitted map and the
  aperture centre. But that is a **re-reference** of an existing calibration. On
  a **first open there is no calibration to invalidate**, so nothing fires: you
  drag a detector rectangle that excludes the direct beam, the load succeeds
  silently, and the geometric-default centre lands wherever the box happens to
  be. That is the exact configuration the screenshots were taken in.

  **→ S4** (configurator finish). Two things, both small: say what each reduction
  costs, and check the sampled preview's own brightest region against the
  detector rectangle at configure time, so cropping the beam out is refused
  *before* the load rather than discovered after it. The preview is already
  sampled and already on screen; nothing new has to be computed.

---

## No way to stop a dataset load in progress — built 2026-08-18

- ~~**No way to stop a dataset load in progress.**~~ **BUILT 2026-08-18**, the
  same day it was requested during the Track B pass. A Cancel sits on the
  loading card next to the progress it cancels; the open unwinds at its next
  checkpoint and the app returns to the welcome screen.

  **A cancelled load is not remembered** (release owner's decision): you
  cancelled because it was the wrong file, so promoting it to the top of Recents
  is backwards. `rememberOpenedDataset` therefore moved to *after* the whole-cube
  pass, so a cancel at any point leaves Recents untouched — rather than writing
  the entry early and trying to undo it.

  The invariant the teardown is written against is **a half-loaded dataset that
  looks loaded**. `hasDataset` is `descriptor?.is4D`, and every workspace view is
  gated on the descriptor, so clearing it is what returns the app to the welcome
  screen; the rest is releasing what was allocated. Pinned by
  `mac4DSTEMTests/DatasetLoadCancellationTests`.

  **Two assertions were removed from that test for being vacuous, and the gap is
  real.** `residency.isResident`, `residency.byteCount` and
  `loadedView.isFullExtent` are all already in their post-discard state after a
  demo open — residency is dormant by decision, a demo load is full extent — so
  asserting them passed whether or not the teardown touched them. Controls proved
  it: deleting the residency release and the `loadedView.reset()` left the test
  green. Both are still released, because a real cancelled open *can* hold a
  resident buffer and a cropped view. **Pinning that needs a fixture that reaches
  those states first**, which the demo path cannot — the honest gap, recorded
  rather than covered by an assertion that looks like coverage.

  **Unverified on screen.** Nobody has cancelled a real load: checklist row
  F1.1d. The interesting case is a slow network open, which is where the button
  earns its place.

---

## #36 — no progress indication while a datacube loads — fixed 2026-08-06

- ~~**#36 — no progress indication while a datacube loads.**~~ **Fixed
  2026-08-06** by `load-pipeline-plan.md` stage L1, and **confirmed on the real
  app** on a 3.96 GB cube (patterns and MB both counting, bar advancing).

---

## #43 — acceptance gate broke on a saved training-dataset session — fixed 2026-08-18

- ~~**#43 — the acceptance gate breaks if a session is saved for a training
  dataset.**~~ **FIXED 2026-08-18.** Reproduced first (exit 133, a page-long
  stack trace after two real cubes had already printed PASS), then fixed at the
  half that mattered: `real-data-acceptance` now treats a file with no datacube
  as an **input**, not an error. It catches `noDatasetFound` only, skips with a
  one-line `SKIP:`, and continues; anything else — unreadable file, malformed
  dataset — still throws, because quieting those would be widening a gate.

  **The glob was deliberately left alone.** Excluding `*.mac4dstem.h5` would
  have worked and would also have made the skip path dead code on this machine;
  keeping it means every run exercises the skip. Same reasoning the plan applies
  to L4's edge-remainder path — a rare untested path is worse than a common one.

  Two guards keep the skip from swallowing a real failure, and both were
  verified by control: a run where **everything** skips fails with "no file
  produced a report" (forced by globbing only the sidecars), and a run missing a
  real cube fails `compare.py`'s count check (forced by dropping one from the
  glob). Result now: **exit 0, four cubes golden, two sidecars skipped.**

---

## Eight standing build-warning classes — cleared by the S3 rider, 2026-08-19

- ~~Eight standing build-warning classes, two of them errors-in-waiting under
  the Swift 6 language mode (surfaced 2026-08-18 by the first full rebuild in
  weeks).~~ **All cleared by the S3 rider, 2026-08-19 — a fresh clean
  `build_macos` now reports zero warnings.** The fixes, for the pattern they
  set: `Residency`, `ResidencyAdmission`, `DatasetPreviewBuilder` and
  `DatasetDescriptor` marked `nonisolated` (pure data/math types that MainActor
  default isolation was isolating away from their nonisolated callers — the
  `DatasetDescriptor` marker also fixes the synthesized `Equatable`/`Hashable`
  conformance, the Swift-6-mode error); the no-op `await` removed
  (`loadPushdown` is sync); and the `DatasetResidency` progress callback now
  captures `[weak self]` on BOTH closures — weak only inside traded the
  mismatch warning for a Swift-6-mode captured-var error, so the shape
  `buildDatasetPreview` already used is the one that satisfies both. The
  lesson stands: **warm incremental builds re-emit nothing**; only a clean
  build can verify a warning claim either way.

---

## Detector-frame recipe replay after a reduced rehearsal — closed by S10, 2026-08-26

  - **Detector-frame recipe parameters do not replay after a detector-reduced
    rehearsal → S10.** A recipe recorded on a detector crop or bin carries
    view-frame apertures, pixel sigmas, g-vectors and Å⁻¹/px scales; mapping
    them to the full detector is the inverse of `CalibrationReReference.apply`
    (positions `x_src = (x_view + 0.5)·b − 0.5 + offset`, lengths ×b,
    per-pixel scales ÷b) — fabrication-shaped math that belongs beside
    `transformedCalibration` under S10's Gate B, not in a Gate A session.
    Until it lands, the planner refuses those steps by name and the promote
    caption says so before the click. **The release claim's "binned view
    re-runs unchanged" is NOT met for detector-reduced rehearsals until S10
    delivers this** — S19's claims restatement must check.

---

## Two L3 residuals (export re-reference / tile offset) — closed by S10 / S2

- **Two L3 residuals from the 2026-08-18 adversarial review, both unreachable
  today and both reachable the moment L5's configurator lands.**
  **(a)** `BraggVectorEMDWriter.transformedCalibration` rescales the origin,
  `qSize` and the probe radius by the *export* bin only; it knows nothing about
  `view.specification.detectorCrop`, and its origin-map shape check now compares
  against the *view* extent, so a source-extent map would fall silently through
  to an empty array. The export currently **refuses** a cropped view rather than
  carrying that defect; the refusal is lifted by L3's calibration re-reference,
  not before. ~~**(b)** `FourDArray.tile(yRange:from:)` — the read offset out of a
  resident buffer — is only ever exercised at `lowerBound == 0` by
  `tools/load-spec-test`, so a bug in that offset would not be caught there.~~
  **CLOSED 2026-08-19 (S2), and the residual as written was wrong.** Deleting
  the offset (`start: base` instead of `start: base + yRange.lowerBound *
  floatsPerScanRow`) does leave `tools/load-spec-test` at exit 0 — that half is
  reproducible — but `tools/virtual-detector-residency` goes **red** on the same
  breakage (`DP statistics [max]: differs at index 0 — resident 279.5537, tiled
  1055.2793`), because `tiledDPStatistics(maximumTileRows: 2)` reaches
  `lowerBound > 0`. So the offset was covered all along, **at full extent only**.
  What was genuinely missing, and what `tools/two-spec-analysis-test` now adds,
  is exhaustive `(lower, upper)` coverage **under a scan crop**, where the
  resident path and the reader's own crop offset compose. Found by Gate B when it
  refused to accept S2's stated justification for the case.


---

## The configurator's preview panes rendered nothing — closed 2026-08-27

Moved here from [`docs/open-items.md`](../open-items.md) on 2026-08-27, at the
closeout of the TB1 sitting that fixed it, under that file's own rule that
closed items do not stay there. Verbatim, except that relative links are
re-based to this file's location. The live file keeps a tombstone: the defect
is closed, but two residuals it names are still open.

- ~~**The configurator's preview panes render NOTHING on screen.**~~ —
  **DIAGNOSED AND FIXED 2026-08-27 (Gate D).** Open since 2026-08-18, through
  three wrong diagnoses. **The cause is one number:** inside SwiftUI's sheet the
  hosted `MTKView`'s `CAMetalLayer` is left at **`contentsScale == 0`**, and a
  layer at scale 0 cannot display a drawable — so the pane stays exactly the
  background colour.
  Fixed by `MetalImageView.ScaleAwareMTKView`, which sets
  `layer.contentsScale` from the window's `backingScaleFactor` in
  `viewDidMoveToWindow` **and** `viewDidChangeBackingProperties` (the second for
  the display-move case, which was latent for every image surface in the app).

  **Why it survived three rounds of diagnosis: every internal signal reads
  healthy while it happens.** `MTKView` derives `drawableSize` from the WINDOW's
  backing scale, not from the layer's `contentsScale`, so the instrument found —
  on the blank panes — `bounds=(276,220)`, `drawable=(552,440)`,
  `rpd=true`, `cd=true`, **`tex=true`**, `hidden=false`, `alpha=1.0`,
  `layerOpacity=1.0`, in the `SheetPresentationWindow`. The app was encoding and
  presenting correct frames into a layer that could not show them.

  **The measurement that settles it** (`NSLog` probe, 2026-08-27,
  `trial_m1.log`): `contentsScale = 0.0` on both blank panes against a window
  `backingScaleFactor` of 2.0, and `2.0` on the pane that rendered. **Stated
  honestly after the Gate B read: that is ONE instrumented cold open** — the
  only run in which the value was read at all. The first version of this entry
  said "perfect correlation across every run", which the retained logs do not
  support.

  **Two corrections from the Gate B second reader, who was briefed to refute
  and did.**

  1. **"A layer created outside a window comes up with `contentsScale == 0`" is
     WRONG, and it was in four places** (this entry, the F1.3b row, the
     `MetalImageView` doc comment, the test file). Measured on this machine: a
     detached `MTKView(frame: .zero, device:)` reads **1.0**. The 0 was only
     ever observed on a view ALREADY in its window, through
     `AppKitPlatformViewHost`. **What writes the 0 is not identified.** The fix
     targets an observed state whose producer is unknown — which is exactly why
     `matchWindowScale`'s `!=` guard matters, since the repair is coupled to
     that unidentified writer.
  2. **The causal leg was missing and is now supplied — and it makes the
     diagnosis stronger than it was.** Everything here was correlation,
     intervention and reversal; nothing showed that imposing scale 0 on a
     WORKING layer reproduces the symptom. The reviewer built that positive
     control outside the app: three plain-AppKit `MTKView`s encoding the same
     clear pass, one untouched, one pinned to `contentsScale = 0`, one to `1.0`.
     The untouched and the **wrong-but-nonzero 1.0 both render**; only 0 renders
     the window background, with `drawableSize` correct in all three. That kills
     the strongest surviving alternative — "the assignment works because ANY
     layer mutation forces a recomposite, and 0 is a marker of something else" —
     because a wrong nonzero scale would then blank too, and it does not.

  **What the pre-registered Gate D diagnosis got wrong, recorded so the next
  reader does not re-walk it.** The written diagnosis was "the two
  sampled-preview `MTKView`s never present a frame" — refuted by its own
  pre-registered discriminator. The colour census was the useful half and it
  was right: the blank panes sample **exactly the sheet background**
  (RGB 30,29,29 in dark appearance, one distinct colour across the whole
  276x220pt box), never the `MTKView` clear colour (15,15,18), which killed
  "drew but no texture" and "clamped to the top LUT entry" in one measurement.

  **Two recorded "facts" were wrong and both had been reasoned from:**
  1. *"The single-position pane renders while the two sampled-preview panes do
     not, through the same view type"* — treated as the central structural
     discriminator on 2026-08-27, and it is **a race, not a split**. Same build,
     same dataset, ten minutes apart: one run had pane 3 rendering, the next had
     **all three blank**. Pane 3 wins when its host happens to be created at a
     moment AppKit has already propagated backing properties.
  2. *"The panes are blank WHITE"* — appearance-dependent. The invariant is
     "identical to the sheet background", which is what the census measures.

  **And the hypothesis dismissed FIRST was the right family.** 2026-08-18
  recorded "`MetalImageView` does not draw inside a sheet" and struck it as
  "WRONG — it is not a hosting problem", on the grounds that the crop rectangle
  is a sibling in the same `ZStack` and draws. **That reasoning does not hold:**
  the crop rectangle is a SwiftUI `Rectangle`, drawn by SwiftUI's own renderer.
  It shows the sheet composites SwiftUI content; it says nothing about whether a
  hosted `MTKView`'s Metal layer is composited. The same non-sequitur then
  justified 2026-08-27's "the Metal-image-views account is dead". The lesson is
  narrow and reusable: **a sibling of a different KIND is not a control.**

  **Evidence, five cold opens each, scored by colour census rather than by
  eye** (`downsample_Si_SiGe_exp.h5`, panes reported as distinct-colour counts):

  | build | pane 1 | pane 2 | pane 3 |
  |---|---|---|---|
  | with the fix | 194 | 266 | 205 — **5/5** |
  | negative control: `layer?.contentsScale = scale` removed, nothing else | **1** | **1** | 205 — **3/3 red** |

  **What that table is worth, and its limits** (Gate B, and they are real). The
  discriminator is sound: a blank pane is exactly the sheet background
  `(30,29,29)`, which neither colormap can produce. But **the replicates are not
  independent** — `trial_f1/f2/f3.png` are byte-identical, as are `n1/n2/n3`, so
  "5/5" is two distinct images and "3/3" is one. The harness is near-
  deterministic and does not sample the race; what actually covers the race is
  the ordering evidence above, not the repeat count. And **the census counts
  colours, not correctness**: a stretched image scores the same 194/266, and in
  the `f` runs it WAS stretched — only the letterbox measurement caught that.

  **The ablation** — corrected chronology, 2026-08-27: a COMPOUND repair
  (`releaseDrawables` + `contentsScale` + a deferred re-arm, all in
  `viewDidMoveToWindow`) was written first and went green 5/5 against a matched
  5/5-red control with the whole re-arm removed. Its parts were then removed one
  at a time, which is what identifies the load-bearing line: `needsDisplay`
  alone (3/3 red), `releaseDrawables()` + `needsDisplay` (3/3 red, one run with
  all three panes blank), a deferred `DispatchQueue.main.async` re-arm (4/4
  red), and `contentsScale` alone (4/4 **green**). It works alone; nothing else
  does. *(The earlier wording here — "three narrower repairs were tried first" —
  described the reverse order and was corrected by the Gate B read.)*

  **The best single datum in the set, found by the reviewer and missed by the
  session that produced it:** `trial_v4d.log` reproduces the `singleDP`-first
  creation ordering — the ordering behind the ONE pre-fix run where all three
  panes were blank (`trial_v2c.log`) — **with the fix in, and its census is
  green.** So the repair was exercised against the worst observed ordering, not
  only the common one. Across 21 pre-fix runs the creation order predicts the
  outcome with no exceptions, which is the race in point 1 above, measured.

  **Still NOT established, listed because the Gate B read insisted on it:**
  (a) what writes the 0 — the producer inside SwiftUI's hosting path is
  unidentified, and the repair's `!=` guard is coupled to it; ~~(b) WHICH override repairs the sheet~~ —
  **CLOSED the same evening, and the prediction was wrong.** Each override was
  removed in turn and driven: **only `viewDidMoveToWindow` → 3/3 green; only
  `viewDidChangeBackingProperties` → 3/3 green.** Either one suffices. The
  pre-registered prediction was that B would go RED, on the reasoning that
  backing properties do not change during a sheet presentation so that hook
  never fires at the moment that matters. AppKit does deliver it; `MTKView`
  simply does not use it to update `layer.contentsScale`, deriving
  `drawableSize` from the window instead — which is the same reason every
  internal signal read healthy. Two consequences: keeping both overrides is
  belt-and-braces rather than one repair plus one safeguard, and the retained
  unit test is worth MORE than claimed, since
  `testAChangeInBackingPropertiesIsFollowed` drives an override now shown
  sufficient in the real failure. None of this touches the core diagnosis, which
  the Gate B positive control established independently; (c) the regression scope beyond one
  screenshot of one workspace — the change swaps `ScaleAwareMTKView` in for
  EVERY `MetalImageView` in the app, and the only on-screen evidence outside
  the sheet is the Prepare workspace (CBED + virtual detector, both correct).

  **Unit coverage, and what it does NOT cover.**
  `mac4DSTEMTests/MetalLayerScaleTests` pins the repair;
  `testAChangeInBackingPropertiesIsFollowed` was verified to go red under a
  mutation of the one assignment. **Three attempts at a `viewDidMoveToWindow`
  test were written and thrown away because all three stayed GREEN under that
  mutation** — a plain AppKit window propagates the scale by itself, and
  assigning either 0 or a stale 1 to a layer-backed view already in a window
  does not stick. The `contentsScale == 0` state is reachable only through
  SwiftUI's host. That absence is documented in the test file itself rather
  than papered over. *(One log needs its own footnote: `unit2.log` shows a
  FOURTH test, `testEnteringAWindowGivesTheLayerThatWindowsBackingScale`,
  failing beside the retained one. That run is neither a mutation run nor a
  green baseline — both window tests CRASHED the test host, because `NSWindow`
  defaults to `isReleasedWhenClosed`, an over-release under ARC. Setting it
  false fixed both. Recorded because a reader comparing logs would otherwise
  read that failure as coverage the tests do not have.)*

  *Original entry (2026-08-27, the drive that produced the discriminators)
  follows.* **The configurator's preview panes render NOTHING on screen — the
  data behind them is verified healthy.** **Re-driven and captured 2026-08-27**
  by
  the assistant (Screen Recording granted), on
  `References/training_dataset/sim_Au_data_all_binned.h5` opened through
  *Open with Options…*, window 2200x1250. **Two refinements to the record
  below, both from the screenshot:**
  (1) the panes are **blank white**, not "a single flat colour" — the headers
  ("Scan — real space", "Diffraction — max", "Diffraction — single position")
  and their captions render, and the image areas render nothing at all;
  (2) **all three** panes are affected, including the single-position pane,
  which the 2026-08-25 record reported as drawing correctly. Everything else on
  the sheet is right: `Scan (Ry x Rx) 100 x 84`, `Detector (Qy x Qx) 125 x 125`,
  the binning control, and the Size block. The status line was still frozen at
  *"Sampling a preview · row 33 of 34"* after 60+ seconds, and the header said
  *"Sampled preview · every 3rd position · 952 of 8,400"* — consistent with the
  cosmetic dropped-final-tick diagnosis below, now observed twice. **F1.3b
  stays FAILED**, and the aspect-stretch decision stays blocked.

  **A discriminating observation, and it narrows the defect.** The release
  owner proposed that the single-position pane might be blank *by design*
  until a scan position is picked. Tested directly: clicking the centre of the
  (blank) real-space pane changed its caption from *"Pattern at scan (90, 21)"*
  to *"Pattern at scan (33, 21)"*. **The click registered, the selected
  position updated, the caption re-rendered live — and the pane stayed blank.**
  The hypothesis is refuted, and more usefully the layers separate: hit-testing,
  state and text rendering in that same sheet all work, while the Metal-backed
  image views draw nothing. With `TB1StallProbeTests` already pinning the data
  healthy headlessly, the defect looked bounded to the image views themselves.

  **That conclusion is REFUTED, same session, by a second dataset — and the
  refutation is the most useful observation of this drive.** The release owner
  tried `Open with Options…` on `downsample_Si_SiGe_exp.h5` and reported the
  single-position pane rendering; reproduced independently by the assistant
  (2026-08-27, same build, `every 4th position · 650 of 10,000`, scan (0, 136)):

  | pane | built from | renders? |
  |---|---|---|
  | Scan — real space | the sampled preview | **no** |
  | Diffraction — max | the sampled preview | **no** |
  | Diffraction — single position | a direct read of one pattern | **YES** — clear CBED, disk array, correct colormap |

  The split follows the sheet's own caption exactly: *"Real-space and max are
  built from the sampled positions only … The single-position pane is the
  recorded pattern at that scan position, exactly."* **The two panes derived
  from the sampled preview fail; the one that is not derived from it works —
  through the same view type.** A generic "the Metal image views are broken"
  account cannot survive that, and neither can "the sheet cannot draw".

  **Two further specifics for the next Gate D sitting:** (1) on Si_SiGe the two
  failing panes show **no frame or border at all** while the working pane has a
  clear one — consistent with those views being absent rather than drawing
  blank, which would put `realSpaceDisplay` / `maxDPDisplay` nil at
  `LoadConfiguratorView.swift:84` and contradict the 2026-08-25 reasoning that
  refuted that branch; (2) on **sim_Au all three panes are blank**,
  single-position included, so the behaviour is dataset-dependent too — any
  account must explain both files, not one.

  *Original entry (2026-08-25) follows.* **The configurator's real-space and
  diffraction-max panes render a single flat colour ON SCREEN — the data behind
  them is verified healthy.** Found on TB1 sitting 1 (2026-08-25, sim_Au, screenshots
  18:45–18:51); Gate D run the same evening narrowed it hard, and three
  candidate diagnoses died in order, each on primary evidence:
  (1) ~~"sampling stalls at row 33 of 34"~~ — the frozen status line is
  COSMETIC: the final progress tick is dropped when `finishDatasetLoading`
  clears `isLoadingDataset` before the tick's `@MainActor` hop lands
  (`previewProgressHandler`'s guard), and `statusText` retains the last
  line forever after. (2) ~~"the sampler throws and the `try?` at
  `AppState` swallows it"~~ — refuted by `LoadConfiguratorView.swift:84`:
  the panes render only when `preview`, `realSpaceDisplay` AND
  `maxDPDisplay` are all non-nil, and the screenshots show the panes'
  frames plus the summary line — everything was non-nil. (3) ~~"bad
  normalization again (the 08-18 mechanism)"~~ — refuted headlessly: the
  same `openFileForConfiguration` on the same file in the unit host builds
  both display images with **full 0→1 pixel spread in 0.6 s**
  (pinned with spread assertions in `TB1StallProbeTests`, 2026-08-25). What remains: the defect is in the
  **on-screen rendering of those two panes** (Metal-backed image views
  inside the sheet) — the single-position pane beside them drew, and the
  inspector thumbnails drew after load. Unreproducible headlessly; next
  session on this needs either the screenshot pipeline (a Screen Recording
  grant) or an owner probe. `TB1StallProbeTests` pins the healthy half so
  a data-side regression cannot masquerade as this. Blocks the
  aspect-stretch decision and F1.16's full pass.
