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


---

## Compaction, 2026-08-28 — four closed entries moved from the live file

Moved **verbatim** from [`docs/open-items.md`](../open-items.md), under that
file's own rule that closed items do not stay there. Each left a tombstone; two
of those tombstones name a live residual (an undriven Track B row).

- ~~**Colorbar and scale bar collide on tall, narrow maps.**~~ — **Fixed by
  S18, 2026-08-27.** Seen on a 200×50 scan with a display rotation applied:
  the `-0.04145 0 0.04145` colorbar and the `20 [pix]` scale bar stacked into
  each other at the foot of the pane, both bottom-anchored with no awareness
  of one another. They now share one `PaneBottomOverlay`
  (`UI/ScaleBarView.swift`) in both the result and diffraction panes:
  `ViewThatFits` keeps them side by side while both fit and stacks them when
  they do not, so the wide case is unchanged. The result pane's three
  trailing legends (colour wheel, IPF key, scalar colorbar) moved into that
  row's trailing slot as a `VStack`, structurally — they are mutually exclusive
  by construction, so the stack fixes no overlap between them and an earlier
  version of this entry wrongly claimed it did (Gate A, same day). **VERIFIED ON SCREEN 2026-08-27, on the original defect
  configuration** — `downsample_Si_SiGe_exp.h5` at 200 x 50 with a 90 degrees
  display rotation applied, the exact scan shape and orientation the collision
  was reported on. The bar and the legend sit adjacent at the bottom of the
  letterboxed image box, roughly 37pt apart, no overlap; the box measured
  ~274pt and the row correctly chose side-by-side (69 + 148 + 40 = 257 < 274),
  matching the derived arithmetic. The narrow branch was scored separately by
  squeezing a pane to its 171pt floor. **Track B row F1.32 PASSED**, both
  branches — which matters, because a fix that stacked them always would pass a
  glance at a narrow pane and waste a third of every normal pane's bottom
  edge.

- ~~**One remaining `contentVersion` staleness hazard.**~~ — **Fixed by S18,
  2026-08-27.** `UI/ProductWorkspaceViews.swift` passed a constant `0` (then at
  `:719`), so the comparison panel uploaded its texture once and never again —
  swapping products of the same shape showed the previous product's pixels
  under the new product's name. The panels are now built once in `init` as a
  `ComparisonPanel` (`:682`), whose version hashes the payload
  (`contentVersion:` now at `:805`). *(The other two instances of this class —
  both preview call sites hashing dimensions only — were fixed by S4 on
  2026-08-24 with `MetalImageView.contentVersion(of:)`, which S18 reused.)*
  **A third instance of the class was found while fixing it:** an RGBA payload
  renders through its packed bytes and carries an all-zero `pixels` array, so a
  version derived from `pixels` alone is identical for every same-sized RGBA
  product — a hexagonal IPF map and a DPC colour wheel of equal dimensions
  would have versioned the same. `ComparisonPanel.version` folds the bytes in;
  `ComparisonPanelVersionTests` pins both halves. Unverified on screen: Track B
  row F1.35.

- ~~**The dataset inspector's preview thumbnails are aspect-stretched.**~~ —
  **Fixed 2026-08-27, reported by the release owner from the inspector and
  verified on screen after the fix.** `DatasetInspector.swift:358` gave
  `MetalImageView` a height-only frame, and that view maps to normalized view
  UVs, so each thumbnail was stretched to the sidebar's full width: a
  **128x128 mean or max pattern was drawn about 300x120 — 2.5x wider than tall,
  rendering every Bragg disk as a horizontal ellipse** — in the app that has an
  ellipse-calibration feature for measuring exactly that distortion. The 200x50
  real-space preview was squashed the other way. Fixed with
  `.aspectRatio(width/height, contentMode: .fit)` ahead of a `maxHeight` frame;
  re-driven afterwards, the square patterns now render square with round disks
  and real space as a correct 4:1 strip. `unit` 384/4/0 exit 0.
  **The sweep was then actually run, and it found a fourth.** All six
  `MetalImageView` call sites, audited 2026-08-27:

  | call site | aspect handling |
  |---|---|
  | `DiffractionView.swift:98` | correct — `fitted(in:aspect:)` |
  | `StemImageView.swift:292` | correct — `fitted(in:aspect:)` |
  | `StemImageView.swift:481` (scan navigator) | correct by construction — `height = 118 * h/w` |
  | `LoadConfiguratorView.swift:243` | **was stretched**, letterboxed same day |
  | `DatasetInspector.swift:358` | **was stretched**, letterboxed same day |
  | `ProductWorkspaceViews.swift:803` | **was stretched — found by this sweep**, fixed |

  The fourth is the **comparison panel**: it framed each product to the full
  pane, so two products being COMPARED were both distorted, in the view whose
  only purpose is comparing them and which offers a difference map beside them.
  It survived a rewrite of that very function earlier the same day, because the
  rewrite was looking at `contentVersion` and not at aspect — a good argument
  for auditing the class rather than the instance. Fixed with
  `.aspectRatio(...)` ahead of the zoom `scaleEffect`, so the letterbox applies
  before the shared zoom and the outer frame still bounds and clips the pane.
  `unit` 384/4/0 exit 0. **The class is now closed: no `MetalImageView` in the
  tree is left without an aspect constraint.** Unverified on screen for the
  comparison panel — it needs two saved products loaded into slots A and B
  (Track B row F1.35 covers that state).

- ~~**#38 — the image panes' scroll monitor consumes every scroll in the
  window.**~~ — **Fixed by S18, 2026-08-27.** `addLocalMonitorForEvents` is
  application-wide: while installed it sees every scroll in every window and,
  by returning nil, swallows it. Hover was the only thing deciding whether it
  was installed, and hover is not a reliable exit signal — another window
  coming forward, a sheet opening over the pane, Mission Control, or a fast
  exit can all leave `.onContinuousHover` never reporting `.ended`, and the
  pane then ate the wheel for the whole app until it was hovered and left
  again. The authority is now geometry asked at **event** time rather than
  remembered from a callback: `ZoomPanModifier` keeps a passthrough backing
  view and consumes a scroll only when it landed inside that view's
  `visibleRect` in that view's own window, passing everything else through
  (`UI/SwiftUI+MTKView.swift`). `visibleRect` rather than `bounds` so a pane
  clipped by an enclosing scroll view does not fight the scroll view hiding
  it; the window comparison covers sheets and popovers without a special case.
  Hover still gates installation — a monitor that outlives its hover is now
  inert instead of destructive. **Unverified on screen: Track B row F1.33**,
  which says how to provoke a stale monitor, because the old behaviour is
  intermittent and one clean attempt is not evidence.


---

## The configurator's two preview panes draw nothing (2026-08-18 entry) — superseded 2026-08-28

Moved **verbatim** from [`docs/open-items.md`](../open-items.md). Every thread in it
closed; the live file keeps a tombstone naming the one residual (F1.19).

- **The configurator's two preview panes draw nothing.** Found 2026-08-18 on
  `calibrationData_circularProbe.h5` (1.96 GB) and again on
  `downsample_Si_SiGe_exp.h5`. Everything *around* the images is correct — the
  stride line (*"Sampled preview · every 6th position · 238 of 8,400"*), both
  titles and subtitles, the caption, the bin picker, the size table — and the
  drag rectangle draws and produces a correct crop. **The images themselves are
  blank** across the full 220pt pane. **This makes the whole feature miss its
  point**: the release owner's words were "would be cool to see a preview to
  choose the ROI from" — choosing a region against an empty rectangle is not
  choosing. It also silently weakens F1.3c, which was scored on a drag into
  blank space.

  **Diagnosed 2026-08-18 by a review agent, and the first hypothesis written
  here — "`MetalImageView` does not draw inside a sheet" — is WRONG.** It is not
  a hosting problem. The configurator is the **only call site in the app that
  violates `MetalImageView`'s documented input contract**
  (`UI/MetalImageView.swift:9-11`: pixels must already be normalized to [0,1]).
  `LoadConfiguratorView.swift:74` passes `preview.realSpace.pixels` and `:92`
  passes `preview.maxDP.pixels` — **raw**, where `DatasetInspector.swift:35,40,45`,
  `StemImageView.swift:469`, `ProductWorkspaceViews.swift:698` (moved into
  `ComparisonPanel.init` by S18) and
  `DiffractionView.swift:98` all pass `.normalized()`. Raw here is not merely
  "unscaled": `realSpace` holds `total`, the sum of every detector pixel at that
  scan position (`Core/Analysis/DatasetPreview.swift:136-144`), so 10⁴–10⁸ on any
  real cube. The shader clamps with `clamp(raw, 0.0, 1.0)`
  (`Shaders/Colormaps.metal:60`), so every value collapses to the top LUT entry
  and the pane renders one flat colour — which is what "blank" actually was.
  What refutes the sheet theory: the crop rectangle is a sibling in the same
  `ZStack` in the same sheet and draws fine (`LoadConfiguratorView.swift:151-161`),
  and F1.3c's correct crop proves `geometry.size` was non-zero.
  **FIXED 2026-08-18, NOT YET SEEN ON SCREEN.** `LoadConfiguratorView.swift:74`
  now passes `preview.realSpace.normalized()` and `:92`
  `preview.maxDP.normalized(useLog: true)` — the log form matters, because a
  linear-normalized max-DP is the central beam and nothing else: drawing, but
  useless for choosing a detector crop. The contract and the reason it was
  broken are now a comment on `previews`, so the next edit cannot reintroduce it
  silently. App builds. **No test covers this and none can** — the defect is
  "renders one flat colour", which every unit-level assertion about pixel counts
  and dimensions passes happily. It is Track B rows F1.3b/F1.3c and nothing
  else, so neither may be re-scored until someone looks.

  ~~Adjacent, same code, land together: the sheet clipping, the missing
  `progress:` argument, the single-DP picker + dims, and the `contentVersion`
  value-dependence.~~ **ALL FOUR LANDED 2026-08-24 (S4).**
  `MetalImageView.contentVersion(of:)` (FNV-1a over pixel values) replaced the
  dimensions-only hashes at both preview call sites *first*, pinned by
  `mac4DSTEMTests/ImageContentVersionTests` (observed failing under a
  dims-only mutation); the configurator gained a third **single position**
  pane fed by a click on the real-space preview (stride-multiplied to source
  coordinates; caption names the position; default is the brightest sampled
  position), with the new state held by `PendingLoad`, not `AppState`;
  `openFileForConfiguration` now passes the same determinate `progress:`
  handler the plain open uses; the dialog states Scan (Ry x Rx) and
  Detector (Qy x Qx) in the inspector's axis convention; and the sheet is
  900×760, sized so the standing content fits without scrolling. **Unverified
  on screen** — Track B rows **F1.16/F1.17/F1.19**, plus the standing F1.3b
  re-drive for the panes themselves.

  **The previews are also aspect-stretched** — `MetalImageView` maps the image to
  normalized view UVs (`Shaders/Colormaps.metal:44,49-51`), so a 106×153 scan is
  drawn into a ~332×220 box. The drag→crop math stays correct, but a user
  dragging a visually square box gets a non-square crop. Decide once the panes
  draw.


---

## #17a for the configurator panes — settled 2026-08-28

The narrative half of a still-live entry, moved **verbatim** from
[`docs/open-items.md`](../open-items.md) during the 2026-08-28 compaction. The wider
#17a question — pane arrangement in the main window — remains open in the live file.

- **#17a — aspect-aware pane arrangement.** Built, then reverted on sight
  2026-08-05. Needs a design decision, not an implementation. **Decided and
  implemented for the CONFIGURATOR PANES ONLY, 2026-08-27** (owner decision,
  taken on measured evidence rather than on sight this time): those panes
  handed `MetalImageView` the full pane, and it maps to normalized view UVs, so
  an 84x100 scan was drawn into a ~270x227 box. A visually square drag on
  sim_Au produced `63 x 45` — 54% of width by 63% of height — so the crop
  arithmetic was right while the picture misrepresented what was being
  selected, and a circular disk rendered elliptical in an app that has an
  ellipse-calibration feature. `LoadConfiguratorView` now letterboxes through
  the same `fitted(in:aspect:)` the result and diffraction panes use.

  **CORRECTION, 2026-08-27, same day: that change did not letterbox anything,
  and this entry's own claim — "with the ZStack sized to the box" — was false.**
  `size` was computed and then used ONLY for the crop-overlay scaling and the
  gesture math; nothing sized the `ZStack` to it, and the chain ended at
  `.frame(maxWidth: .infinity, maxHeight: .infinity)`. `MetalImageView` is
  flexible, so the `MTKView` still filled the whole 276x220pt pane. The picture
  stayed stretched **and** the gestures had already moved into a box the image
  did not occupy, so the two now disagreed — arguably worse than before.
  Measured on screen once F1.3b stopped hiding it: a 128x128 pattern drew
  **277x213**. Fixed by adding the `.frame(width:height:)` the comment always
  described — whose placement relative to `contentShape`/the gestures was then
  tested BOTH ways and makes no difference (same tap result, same drawn box; an
  interim claim that taps died in one ordering was an artefact of the
  element-based test harness, not a property of the code, and was removed from
  the shipped comment before landing) — and verified on screen 3/3: the 50x13
  scan preview now draws **276x72pt** (aspect 3.83 against the sampled grid's
  50/13 = 3.85; note this is the SAMPLED aspect, which differs from the source
  scan's by the stride's ceiling rounding) and the two 128x128 diffraction panes
  draw square, with round disks.

  **The crop half is verified too, and it was the last place a silently wrong
  crop could hide** — the Gate B reader flagged it as the one open
  data-correctness question. Driven with real `CGEvent` drags on
  `downsample_Si_SiGe_exp.h5`: a visually square 60 x 60pt drag on the scan
  strip returns *Loaded shape* **44 x 48** x 128 x 128 — ratio 1.09, against
  1.40 for the same gesture before the fix — and the drawn crop rectangle
  measures 69 x 65pt, so the overlay, the picture and the loaded extent all
  agree. The residual 9% is the preview's stride (4), not a defect: a crop can
  only quantise to sampled positions, so ±4 source rows on a ~44 extent is the
  floor. Track B row F1.3c.
  `unit` 387/4/0 exit 0 after the change.

  The lesson, and it is the reusable part: the commit message, the code comment
  and this entry all asserted a `.frame` that was never written, and none of the
  three could be checked because the defect that hid it was still open. A claim
  whose only witness is a blocked Track B row is not a verified claim.
  The wider #17a question — pane ARRANGEMENT in the main
  window — is untouched and still open.


---

## TB1 sitting 2's freeze — the Gate D narrative, archived 2026-08-28

Moved **verbatim** from [`docs/open-items.md`](../open-items.md) during the
2026-08-28 compaction. **The item is still LIVE** — the freeze is unreproduced and a
competing account is open — so the live file keeps the finding, the open account and
all five recorded residuals; what moved here is the refuted-hypothesis narrative.

- **TB1 sitting 2: an open froze for minutes at "Checking for a saved
  session…" until cancelled (2026-08-25, ~18:54).** The owner attributed
  it to a leftover sidecar; Gate D the same evening refuted that and one
  more account, measured the real block, and landed a fix for the measured
  half — **the on-screen freeze itself remains unreproduced end to end**:
  - ~~The staged WS₂ sidecar blocks reads~~ — a fresh process reads it in
    0.47 s, and the full WS₂-beside-sidecar open completes in ~1 s in the
    unit host with the S7 rewrite gate correctly armed.
  - ~~A stale sidecar-bookmark for the opened path~~ — the app's real
    domain (`com.mac4dstem.mac4DSTEM`, dumped through the shared test
    host) holds sidecar bookmarks only for sim_Au, Si_SiGe (both local)
    and one NAS source nobody opened.
  - **Measured: resolving a stored bookmark whose volume is an unmounted
    network share blocked 30.03 s** — this machine's own recents entry for
    `/Volumes/eXtendedGROUPS/…` — and both production resolution sites run
    synchronously on the main actor. **Fixed the same evening:**
    `.withoutMounting` added to `WorkspaceRecoveryStore.resolve` and
    `SessionSidecarLocator.grant` — an unmounted volume now refuses fast
    instead of freezing the UI per attempt; all six stored bookmarks
    resolve-or-refuse in 27 ms total, pinned by
    `BookmarkResolutionLatencyTests` (the pre-fix 30.03 s measurement of
    the same operation is the observed-failing half of that pair).
  - **Leading account for the minutes, upgraded by the Gate D second
    reader and then bounded by a probe.** The label is mechanically exact,
    not incidental: `beginDatasetLoadingStage("Checking for a saved
    session…")` is followed with NO suspension by
    `sessionSidecar.location(for:)` → `grant()` → bookmark resolution on
    the main actor, and every open starts cold (`release()` runs first) —
    so a sidecar-grant bookmark pointing at an absent volume blocks under
    exactly that label. BUT the follow-up probe read every stored sidecar
    bookmark's EMBEDDED path without resolving: none targets `/Volumes`
    (sim_Au → its local sibling; Si_SiGe → a since-emptied `~/.Trash`
    entry; the one NAS-source key → a Desktop file). So on this machine
    that path could not have produced the freeze, and a competing account
    the fix does not address remains open: a mount that succeeded SLOWLY
    followed by a slow SMB read. Which cube sitting 2 opened is not
    recorded. Confirmation if it recurs: `sample mac4DSTEM 3` in Terminal
    while it hangs.
  - **The second reader refuted the fix's first catch blocks, corrected
    the same evening:** `openRecent` deleted the recents entry — and the
    only rendering of the NAS path — for a merely-unmounted volume, with a
    "renew permission" remedy that cannot work; `grant()` likewise deleted
    a sidecar grant, silently re-arming the silent-full-extent reopen for
    a sidecar legitimately saved to a NAS. Both now branch on
    `WorkspaceRecoveryStore.unmountedVolumeName(forBookmark:)` (embedded
    path, no resolution): unmounted keeps the state and names the volume;
    only a genuinely dead bookmark is forgotten. Pinned machine-locally by
    `BookmarkResolutionLatencyTests.testClickingARecentOnAnUnmountedVolume…`
    (observed failing under the old catch, teardown-protected).
  - **Recorded residuals:** (1) with the share unplugged, an open whose
    sidecar lives on the NAS is still SILENT for that one open (grant nil
    → derived-sibling fallback → "no session recorded") — the loud refusal
    belongs to the S7 gates seam when someone owns it; (2)
    `.withoutMounting` does nothing for a MOUNTED-but-hung server — the
    block then moves into plain file I/O (`fileExists` on the main actor
    at two open-path sites), S9's territory; (3)
    `UI/InspectorPanels.swift:108` calls `sessionSidecar.location(for:)`
    inside a view body — a defaults read + bookmark resolution per body
    evaluation on a cache miss; (4) a sidecar bookmark FOLLOWS the file
    into `~/.Trash` (identity-tracking; the Si_SiGe key demonstrated it) —
    a trashed-but-not-emptied sidecar would keep being read as the live
    session; policy needed (probably: a grant resolving into the Trash is
    no grant); (5) `openFileForConfiguration` sets no terminal status
    line, so the last sampling tick — which can drop its final update in a
    benign race with `finishDatasetLoading` — stays on screen indefinitely
    (the frozen "row 33 of 34").

---

## The external review's own errors — do not import

Moved verbatim from [`docs/open-items.md`](../open-items.md) by S11 on
2026-08-28, once the four live leads that review raised were triaged. The live
file keeps a one-line pointer here. **History, and a standing guard**: if that
document is ever re-read, these are the parts that were checked against this
tree and found wrong.

**Errors in that review — do not import.** It states the app uses **MLX**
(it does not; `grep -rl "import MLX" mac4DSTEM/` is empty — MLX is prior art in
`References/MigrationSource` only). It assumes an **App Store** release goal and
raises a "distribution mismatch" on that basis; the plan is Developer ID +
notarization, and GPL-3.0 is incompatible with the App Store anyway. Its
resident-cube findings ("untracked", "no AppState preload/release/progress
wiring") described a mid-L2 working tree and are stale as of `73105fc`. Many of
its file paths do not exist here (`mac4DSTEM/App/ContentView.swift`,
`mac4DSTEM/Platform/HDF5/H5Reader.swift`, `mac4DSTEM/Core/Export/ResultExport.swift`),
so **its line citations cannot be trusted without checking** — which is why the
list in the live file is only what was re-derived from this tree.

**Framing caveat.** The review repeatedly reasons about "the shortest credible
path to v1" and recommends narrowing scope before release. **v1.0.0 shipped on
2026-08-06 and is public.** Read those sections as *what v1.1 should fix before
the claims are widened*, not as release advice.
