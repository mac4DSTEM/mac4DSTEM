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
