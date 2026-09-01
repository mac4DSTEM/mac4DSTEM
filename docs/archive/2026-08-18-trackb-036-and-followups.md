# Archived 2026-09-01 — the 2026-08-18 Track B pass (036 cube) and its follow-up thread

Moved verbatim from `docs/open-items.md` (the 661-line section of the
2026-09-01 revision) by the pre-S20 docs tidy. It held the 2026-08-18 drive of
the 4.25 GB 036 cube, the L4 review notes, S18's findings and closures, and
every follow-up appended under the one heading through 2026-08-29. The
still-live residuals were extracted back into `docs/open-items.md`
("2026-08-18 Track B pass and its follow-up thread — untangled 2026-09-01");
everything here is history and evidence. Do not tick or amend anything here —
amend the live entry instead.

---

### Track B pass — 2026-08-18, `036_STEM_SI_preprocessed_filtered_bin_2_20240723.h5` (4.25 GB on disk, 3.96 GB as f32)

Driven by the release owner on the open/load rows of §F1. Two things confirmed,
one defect found, one checklist row withdrawn as unrunnable.

**Confirmed on screen, first time for both:**
- The **preview sampling phase** reports determinately during the open —
  *"Sampling a preview · row 9 of 20"*, welcome card still up. L5's preview half
  works on a real multi-gigabyte cube, not just in a unit test.
- L1's whole-cube pass again — *"Scanning patterns 318 / 16,218 patterns ·
  80 MB of 3.96 GB"*, bar advancing, welcome card still up. Previously confirmed
  2026-08-06; this is a second dataset.

**FINDING — two recents rows are indistinguishable on screen. The de-duplication
is not at fault.** Read out of the stored defaults rather than guessed:

    /Volumes/eXtendedGROUPS/.../Lobpreis$/00_inbox/4DSTEM_Binned_Cubes/036_STEM_SI_...h5   (NAS)
    /Volumes/PL_SSD_2TB/NAS_Backup/00_inbox/4DSTEM_Binned_Cubes/036_STEM_SI_...h5          (local backup)

Two genuinely different paths, so `rememberOpenedDataset`'s
`removeAll { $0.id == id }` on `standardizedFileURL.path` correctly kept both.
**The defect is the display:** each row shows only `url.lastPathComponent`, so a
NAS copy and a local backup of the same file render identically and the user
cannot tell which one they are about to open — on a list whose entire purpose is
choosing between them. It also means the 4.25 GB cube was opened over SMB while
an identical copy sat on a local SSD, which is exactly the case the
local-storage notice exists for (#30, ~3.3 MB/s).

**FIXED 2026-08-18** in the row, not the identity. Each recent now carries a
location line, shown as *"eXtendedGROUPS"* against *"PL_SSD_2TB"* for the pair
above. `RecentDatasetLocation.labels(for:)` gives each entry the **shortest**
label that separates it from the other entries sharing its file name: the volume
alone where that is enough, extended one directory at a time where it is not,
and the full path if even that collides — long and correct beats short and
wrong. Pinned by `mac4DSTEMTests/RecentDatasetLocationTests` (9 tests, built on
the two real paths); four controls fail it, including one that labels on the
parent folder instead of the volume, which fails 6 tests **because both copies
here live in `00_inbox/4DSTEM_Binned_Cubes`** — the obvious fix would have
looked right and changed nothing.

Two things deliberately not done. It does **not** say "network": that needs a
real volume query, the volumes are routinely unmounted, and asking the disk about
an absent NAS while drawing the app's first screen would stall it — the volume
*name* is shown and the reader draws their own conclusion. And the labels are
computed in `AppState`, once per change rather than per redraw, because the
disambiguation is O(n²) in the number of recents and #31 is the standing item
about exactly that pattern in a view body.

**Unverified on screen** — no one has looked at the new row yet. It is
`docs/visual-acceptance-checklist.md` §F1.1c.

**PASSED — §F1.2 and §F1.3, both first-time.** The dataset inspector's *Preview*
section reads *"Sampled preview · every 8th position · 280 of 16,218"* — the
stride stated, as invariant I4 requires — above real-space, mean-pattern and
max-pattern thumbnails, and closes with *"Not a result — cannot be exported or
saved."* No control offers to export or promote it. L5's preview half is now
confirmed on a real 3.96 GB cube rather than only in `DatasetPreviewTests`.

Incidental corroboration: the inspector reports **Chunks: contiguous** for this
file, which is the case where `H5Reader.loadPushdown` correctly claims `.full` —
the chunked case that made it conditional is a different file class.

~~**WORTH CONFIRMING — the scan extent is printed in two orders in one
window.**~~ — **Confirmed a defect and fixed by S18, 2026-08-27.** The sidebar
header read `106 x 153 scan` while *Dimensions* read `Scan (Ry x Rx) 153 x 106`
and *Shape* read `153 x 106 x 256 x 256`. **The second look: both orders are
correct and neither should change.** A number printed beside an image should
read the way the image draws (across, then down); a row labelled with its own
axes should read the way the array is indexed. Forcing one order on all three
would make the card disagree with the picture next to it — the same defect
pointing the other way. What made it a real defect is narrower than "two
orders": the sidebar card carried **no axis labels**, so a reader had two
numbers, no way to tell which convention either used, and nothing to reconcile
them with — the tag-day shape of a summary contradicting its own detail line.
The card now says which axes it names
(`106 × 153 scan (Rx × Ry)  ·  256 × 256 detector (Qx × Qy)`,
`UI/ContentView.swift`), and the inspector is untouched. The longer string did
not tip the sidebar column-fit gates (`unit` exit 0 after the change, measured
not assumed). **Unverified on screen: Track B row F1.34**, which also checks a
narrow sidebar for clipping.

**WITHDRAWN — §F1.1 could not pass on any dataset.** It asked the release owner
to watch the L2 preload phase; `makeResident` refuses immediately because
`shouldAdmit` returns false for `.streamed` outright, so no such
phase runs. The 4.25 GB cube was more than large enough — the row was wrong. It
is struck from the checklist with the reason, and reinstated only if
`.automatic` returns post-v2 — the case itself was dropped in S3 (2026-08-19),
so a measured threshold alone no longer re-arms the phase this row watched.
**The lesson is about writing checklists, not about
residency:** a Track B row must be checked against what the build actually does,
or it spends the one resource Track B is expensive in — a person's attention.

- **L4 stays `[~]`: its review ran, but on the default model rather than the
  Fable 5 / `/code-review ultra` the plan names**, and two of its findings are
  still open. The review could not refute the array math on any composition it
  built (all bit-exact against py4DSTEM) and found one CRITICAL latent defect —
  four detector-frame values derived from the source rather than the view, plus
  a fifth instance in a claim the plan had already made about `minPeakSpacing`.
  Both fixed. **Carried into L5** (`load-pipeline-plan.md` §5): no view reads
  `LoadedView`'s display surface, so L4's "state it in the UI" and "label the
  result" items land with the configurator; and the fixture has no
  rank-3-with-bin case.
- **A negative control was reported as passing when it cannot fail.** "Bounds-
  checking before the bin instead of after" was listed among L4's controls; the
  review implemented it faithfully and everything stayed green, because
  `binnedCoordinate` is affine and the pre-bin and post-bin bounds tests are the
  same predicate. The mutation actually run had changed the *extent* instead —
  a different, meaningless edit that failed for an unexamined reason. Nothing in
  the code is wrong; the claim was. **Recorded because the class matters more
  than the instance:** a control is only evidence if you know which line it
  breaks and why the failure follows, and "it went red" is not that. Both the
  plan and the call-site comment are corrected.
- **The plan's named L4 fixture does not exist, and the premise was never
  checked.** §6 said the training set carries `bin2` and `bin8` files of the same
  data, offering "real external ground truth". `References/training_dataset/`
  holds one Particle_1 file whose name carries both tokens for unrelated
  reasons. Corrected in the plan; recorded here because the same class of error
  — a fixture asserted in a doc and never checked against the directory — is
  cheap to repeat. The replacement (py4DSTEM as the arbiter) is better, so
  nothing is owed except the habit.
- **A bounds convention was wrong before the load pipeline and binning exposed
  it.** `CalibrationReReference` tested an origin against `[0, width)`, the
  convention for *indices*, but an origin is a continuous position and the
  detector covers `[-0.5, width - 0.5)` in pixel-centre coordinates. Harmless
  while every operation was a translation; `binnedCoordinate` maps source 0 to a
  negative value for every factor, so ordinary origins fell in the gap and the
  whole calibration would have been invalidated — an off-by-half that presents
  as a principled refusal. Fixed 2026-08-18 with the case pinned. **Worth a
  sweep:** other detector-bounds tests in the app may use the index convention
  for continuous positions too; nobody has looked.
- **`measureOrigin` is frame-dependent: cropping the detector moves the
  measured origin by up to ~1 px, and this predates the load pipeline.** Its
  coarse step takes an argmax over blocks of side `round(probeRadius)` tiled
  from pixel (0, 0) (`Shaders/OriginMeasure.metal`), so a crop offset that is
  not a multiple of that block slides the grid under the disk. Measured
  2026-08-18 on the `tools/load-spec-calibration` fixture (block 4): offset
  (8, 4) reproduces the full-frame origin **exactly**, (6, 4) differs by
  **0.68 px**, (8, 5) by **1.13 px**. py4DSTEM's own coarse step,
  `argmax(gaussian_filter(dp, sigma=r))`, is translation-equivariant and does
  not have this property — the binned-block substitution is the deliberate
  deviation recorded in that shader's header, taken for cost.
  **Consequence to weigh, not a bug to rush:** "re-fit the origin on this view"
  can legitimately return a slightly different answer from the re-referenced
  one, so the two are not interchangeable at sub-pixel precision. It also means
  the same dataset cropped two ways can fit two origins ~1 px apart. Bears on
  the Q-calibration lead, where `KnownCrystalQCalibration.estimate` already
  discards peaks inside 2 px. A translation-equivariant coarse step (a real
  Gaussian, or an argmax refined against a fixed grid) would remove it.

  **S2, 2026-08-19 — the discriminating experiment was run, twice
  independently, and it settles the cause for S12.** Striding the block scan by
  1 instead of by `bin` (`OriginMeasure.metal:47,49` — a two-token change) takes
  the measured translation-equivariance error from **0.6094227 px to
  9.536743e-07 px**, i.e. float noise. So the coarse grid *is* the cause of the
  equivariance error, and the un-iterated CoM below is **not** an independent
  contributor to it: the CoM is exactly equivariant once seeded equivariantly.
  The same experiment leaves the **absolute** error unchanged at 0.337 px, which
  is how the two items are told apart — they are separate defects that happen to
  be the same order of magnitude, and S2's first draft wrongly asserted they were
  the same number. Both are now pinned by `tools/two-spec-analysis-test`
  (`P4_KNOWN_BOUND` 0.65 px, `ORIGIN_ABSOLUTE_BOUND` 0.40 px), so S13 gets a
  before/after gate rather than an argument.

  **Cost, MEASURED by S12 on 2026-08-28** (`tools/origin-fit-diagnostics/run.sh
  coarse-cost`; both kernels derived from the shipped shader at run time so
  neither can drift; median of 15 dispatches **at the app's real tile grid** —
  `measureOrigin` is dispatched per tile, and an earlier draft of this
  paragraph timed invented scan shapes and had every ratio wrong): the naive
  stride-1 window costs **2.5× at bin 2, 14.8× at bin 5, 21.6× at bin 6 and
  86.3× at bin 11** — 1.3–3.3 µs/pattern shipped against 3.3–224.3 µs. Against
  a whole `origin_calibration` stage of 60–174 µs/position (the shipped kernel
  being 1.3–5.5% of it), that is **+17% at *r* = 5 and +261%, i.e. 3.6× the
  whole stage, at *r* = 10.6**. So this entry's own guess that "the equivariant
  step is therefore probably cheap" was **wrong**, and the shader header's
  "prohibitively expensive" is closer to right than this entry assumed —
  negligible for small probes, more than triple the stage for large ones.
  **Per-machine caveat:** tile height comes from `scanTileRows`, bounded by
  physical RAM, so these are an 8 GB machine's ratios. **S12 recommends it OUT of S13**: it buys 0.61 px
  that is a stated bound rather than a product claim (already pinned by
  `P4_KNOWN_BOUND` 0.65 px), it leaves the 0.337 px absolute error untouched,
  and the same datasets are 11.7 px and 18.3 px wrong for an unrelated reason
  (below). If it is ever wanted, stride-1 is the wrong implementation — a
  separable box filter restores O(qy·qx) and must itself be measured before it
  is believed. Re-entry condition and reasoning:
  [`docs/q-calibration-design.md`](q-calibration-design.md) §4.
- **`measureOrigin` performs a single centre-of-mass refinement, not an
  iteration to convergence**, so its output sits ~0.6 px from the converged
  windowed centre on the same fixture. Also pre-existing, also a deviation from
  what "centre of mass origin" implies to a reader. Recorded because a harness
  that assumes the returned origin is a fixed point of its own CoM will fail for
  this reason and look like a crop bug — it did, on 2026-08-18, before the
  arbiter was re-anchored on the fixture's analytic truth.
- ~~Two L3 residuals from the 2026-08-18 adversarial review~~ — **(a)
  CLOSED by S10, 2026-08-26**: the cropped-view export refusal is lifted,
  `transformedCalibration` gained the frame refusals + the ellipse rescale,
  pinned by `tools/reduced-export-test`; (b) was closed by S2, 2026-08-19;
  record in [the closed-items archive](archive/closed-items-2026-08.md).
- ~~"Save Calibration to Session Sidecar" wrote the file but never persisted
  the access grant~~ — **found by Track B F1.3h and FIXED 2026-08-19** (one
  shared `rememberSidecarGrant`); record in [the closed-items archive](archive/closed-items-2026-08.md).

- ~~Once a sidecar grant exists there is no way to rename or relocate it~~ —
  **FIXED 2026-08-24 (S4)**: File ▸ Save Session Sidecar As… + inspector
  Change…, copy-never-move, identity-compared; record in [the closed-items archive](archive/closed-items-2026-08.md).
  Still live: the stranded `calibrationData_bullseyeProbe.mac4dstem.h5` on
  the Desktop can now be brought home by the owner; rows F1.20 + F1.3i are
  queued; and a known residual of the shipped code stands — a retarget made
  before any save exists has no file to bookmark, so it survives only until
  the next dataset change (the first real save persists it; stated in the
  status message).
- **Repeating Save Session Sidecar As… can prefill and create a doubled
  `.h5.h5` suffix — Track B finding, owner drive 2026-08-29 on
  `downsample_Si_SiGe_exp.h5`.** The first drive of F1.20 passed exactly:
  `crop-test.mac4dstem.h5` was copied, the original remained, and the inspector
  followed the renamed file. Opening Save As again then showed
  `crop-test.mac4dstem.h5.h5` in the name field — `crop-test.mac4dstem.h5`
  selected with a final `.h5` outside the selection — and accepting it created
  and retargeted the session to that doubled name. The screenshot and the
  resulting 494,336-byte file independently establish the observation. This
  is a naming/Save-panel finding only; no cause is claimed and no app fix was
  attempted during the evaluation pass.
- ~~Opening a `.mac4dstem.h5` sidecar directly dumps a 60-line wall of tried
  paths~~ — **FIXED 2026-08-24 (S4)** (`H5Error.sessionSidecarOpened`, capped
  path list); record in [the closed-items archive](archive/closed-items-2026-08.md). Still live: pre-S4 calibration-only sidecars
  remain unrecognisable, and the extension/open-panel-filter half is an
  owner decision queued for TB1. Track B row F1.21.
- ~~The configurator never says what a detector crop costs, and lets a crop
  exclude the direct beam without a word~~ — **FIXED 2026-08-24 (S4)** (the
  crop-vs-bin cost caption + the configure-time refusal, checked against the
  rectangle actually read); record, including the crop-vs-bin analysis
  table, in [the closed-items archive](archive/closed-items-2026-08.md). Still live: the beam proxy is the mean pattern's brightest
  pixel with no override — the "load anyway" question is queued for TB1,
  and unifying this gate with `CalibrationReReference`'s into one policy
  owner is queued on that TB1 decision: S7 built the seam
  (`App/SessionGates.swift`, its stated home) but deliberately did not do
  the unification (s7.md deviation 2). Track B rows F1.17/F1.18.
- **Nothing pins the virtual-detector mask boundary convention against
  py4DSTEM, and no harness can currently see a change to it.** Found by Gate B
  during S2 (2026-08-19). The app's circle mask uses `r2 < rOut2`
  (`Core/Analysis/VirtualDetector.swift:534`) and py4DSTEM uses strict `<`
  (`References/py4DSTEM-dev/py4DSTEM/datacube/virtualimage.py:636`), so **the app
  is correct today** — this is not a live defect. The gap is that flipping it to
  `<=` leaves both `tools/two-spec-analysis-test` and `tools/virtual-detector-test`
  at exit 0, because every comparison in both runs the same `makeMask` on each
  side, and a boundary-pixel change cancels. It is the shared-code limit of any
  self-comparison, and the fix is one assertion pinning `makeMask`'s output
  against an analytic mask, not a new harness. Cheap; nobody has done it.
- **The 2026-08-17 runner breakage recurred on 2026-08-25, exactly as
  predicted: SEVEN runners hand-listing `BraggVectorEMDWriter.swift` had
  never gained `Core/Data/SessionReplayRecord.swift`, which S5 made a
  dependency of the writer on 2026-08-24 — and `scientific` had not run end
  to end between S5 landing and S7's gate run, so the break sat invisible
  for a day.** S7 patched the missing file into all seven
  (`bragg-export-test`, `bragg-spacing-probe`, `scientific-bundle-test`,
  `preprocessing-export-test`, `sidecar-error-detail-test`,
  `training-dataset-campaign`, `sidecar-result-test`) — a minimal fix,
  **deliberately NOT the manifest migration the 2026-08-18 policy calls
  for**: migrating seven runners' full source lists mid-session is its own
  verification job. The policy stands; the count of manifest-sourced
  runners is still one. Each of the seven is now one file further from its
  hand list being right by accident.
- **`Aperture` is declared in `App/AppState.swift`, so every scientific harness
  that compiles `VirtualDetector.swift` redeclares its own copy.**
  `tools/virtual-detector-test` and `tools/two-spec-analysis-test` each carry
  one. If the app's `Aperture` gained a field, every copy would still compile and
  still pass, testing a shape the app no longer has — the `sources.manifest`
  problem in a different costume. The honest fix is to move `Aperture` into
  `Core/`, which is an app-layout change and so belongs to a session that is
  already touching that area, not to a harness session. Raised by S2, 2026-08-19.
- **`tools/load-spec-test` compiles `LoadSpecification.swift` with bare
  `swiftc`, which defaults to *nonisolated*, while the app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** So the harness validates
  different isolation semantics from the app, and cannot see an actor-isolation
  defect at all — that class showed up only in the app build (35 warnings, three
  classes of them "an error in the Swift 6 language mode"). Not a bug to fix so
  much as a limit to know: **the app build is the only gate for isolation**, and
  a stage that adds Core value types crossing into the reader actors should be
  built, not just harnessed.

  **Amended 2026-08-19 (S2): "every `tools/` harness has this blind spot" is no
  longer true, and the narrowing is smaller than it sounds.**
  `tools/lib/sources.manifest` now carries `MAC4DSTEM_ISOLATION_FLAGS` and
  `tools/two-spec-analysis-test` builds with them, which surfaces one Swift 6
  diagnostic (`FourDArray.swift:244`, `ResidencyAdmission.shouldAdmit`) that the
  same sources compiled bare do not produce at all — measured three ways.
  **But the warning does not gate:** `swiftc` exits 0 on it, so `set -e` never
  fires and `scientific` stays green. Making it bite needs `-warnings-as-errors`,
  which today would fail the build on that very warning. The app build therefore
  remains the only real gate; the flags buy visibility, not enforcement. Gate B
  also caught the first version of the flag list carrying three of the five
  features `SWIFT_APPROACHABLE_CONCURRENCY` enables while claiming to "match the
  app target"; all five plus `MemberImportVisibility` are there now.
- ~~No way to stop a dataset load in progress~~ — **BUILT 2026-08-18**
  (Cancel on the loading card; a cancelled load is deliberately not
  remembered); record in [the closed-items archive](archive/closed-items-2026-08.md). Still live: nobody has cancelled a real load
  on screen (F1.1d), and the teardown of a resident buffer / cropped view
  is unpinned — the demo path cannot reach those states, the honest gap in
  `DatasetLoadCancellationTests`.
- **#17a — aspect-aware pane arrangement. The WIDER question is still open:**
  pane ARRANGEMENT in the main window. Built, then reverted on sight 2026-08-05;
  it needs a design decision, not an implementation.
  **Settled for the CONFIGURATOR PANES ONLY, 2026-08-27/28** — owner decision
  taken on measured evidence rather than on sight this time, then implemented,
  corrected once (the first letterbox was computed and never applied), and
  verified on screen: a 50x13 scan draws 276x72pt, the 128x128 patterns draw
  square, and a visually square drag returns a 44x48 crop against 63x45 before.
  Full record in [the closed-items archive](archive/closed-items-2026-08.md).

  **The lesson is the part worth keeping here.** The commit message, the code
  comment and this entry all asserted a `.frame` that was never written, and
  none of the three could be checked because the defect hiding it (F1.3b) was
  still open. **A claim whose only witness is a blocked Track B row is not a
  verified claim** — write it in the unverified voice until the row scores.
- ~~**#36 — no progress indication while a datacube loads**~~ — **fixed
  2026-08-06 (L1)**, confirmed on a real 3.96 GB cube; record in
  [the closed-items archive](archive/closed-items-2026-08.md).
- **S18's axis labels are TRUNCATED in the sidebar dataset card — half the fix
  is invisible.** Found on screen 2026-08-27, driving the demo dataset in the
  build under test at the default sidebar width. The card renders
  `12 × 12 scan (Rx × Ry)  ·  64 × 64 detector (…` — the line truncates with an
  ellipsis instead of wrapping, so **`(Qx × Qy)` never appears**. The scan axes
  are labelled; the detector axes are not, which is precisely the ambiguity the
  change existed to remove, still present on the second half of the line.
  Worse on a non-square detector, where the unlabelled pair actually matters.

  **Every automated gate passed while this was on screen** — `unit` 384/4/0
  exit 0, including `SidebarLayoutTests`. They measure document height and
  column fit, and truncation changes neither, so this defect is structurally
  invisible to them. It is the F1.34 row scoring FAILED on its own session's
  work, and a clean demonstration of why Track B is not redundant with Track A.
  **FIXED AND RE-VERIFIED ON SCREEN the same session, 2026-08-27.** The card
  now renders three lines — `mac4DSTEM Demo.h5` / `12 × 12 scan (Rx × Ry)` /
  `64 × 64 detector (Qx × Qy)` — with both axis pairs complete and no ellipsis.
  **The first fix did not work and that is worth recording:**
  `.fixedSize(horizontal: false, vertical: true)` was applied, built and driven,
  and the line still truncated — confirmed against the rebuilt binary, not
  assumed. Splitting the string into two `Text` views is structural: neither
  line is long enough to truncate at any sidebar width the app permits (min
  250pt). `unit` re-run after the card grew a line: **384 passed / 4 skipped /
  0 failed, exit 0**, with `testEveryNonQuarantinedWorkspaceSidebarFitsItsColumn`
  and `testSidebarDocumentRoughlyFitsItsColumn` both still passing — the extra
  line does not tip the column-fit gates.

- **A DPC result run on an uncalibrated dataset is badged "Quantitative"
  while the task banner directly above says it ran in qualitative units.**
  Found 2026-08-27 driving TB1 on `downsample_Si_SiGe_exp.h5` (origin measured
  in app and reading **"Not quantitative"**; ellipse, R-Q rotation, Q scale and
  R scale all Missing). **Both statements are on screen in one frame, about
  30pt apart:**

  > ⊘ Ready · limited interpretation — *"Runs in **qualitative** units; add
  > origin, R-Q rotation, Q scale, R scale, voltage for quantitative
  > DPC/iDPC."*
  >
  > **DPC magnitude** `Quantitative`  ← green badge

  **Mechanism, read from the code and not inferred from the symptom:**
  `AppState.quantitativeStatus(for:units:)` (`App/AppState.swift:735-746`)
  pattern-matches on the kind and units strings — ACOM prefixes, `dpc_color`,
  `ipf`, `idpc_qualitative`, and units containing `intensity` / `arbitrary` /
  `log_` — and **falls through to `.quantitative` for everything else**. DPC
  magnitude in detector pixels matches none of them, so it is badged
  Quantitative **by default**. The function never consults the calibration
  state at all, so it cannot know what the banner two lines above it knows.

  **Why this is a defect and not a wording clash.** The green badge is the
  app's strongest trust signal, and here it defaults to the reassuring value
  for any case the function does not recognise — the opposite of a safe
  default, and the shape the refusal rule names: *a gate whose miss path
  records an error and continues is not a gate*. It is also the tag-day defect
  class exactly — a readiness line contradicting its own detail line. S7 wired
  `originFitIsQuantitative` into the iDPC gate; **this badge does not consult
  it**, which is why the same session both refuses iDPC and calls the DPC
  output quantitative.

  **AND IT ESCAPES THE APP — verified by exporting, 2026-08-27.** The result
  was exported through *File ▸ Export Result Image…* and the PNG read back
  programmatically. Its XMP `dc:description` carries
  `"quantitative_status":"quantitative"` alongside `"value_units":"detector_px"`
  and `"pixel_units":"[pix]"`, and the **burned-in caption on the figure reads
  `scan space · quantitative · 1 [pix]/px`**. So a colleague who receives only
  the PNG — which is the entire point of burning the caption in — reads
  "quantitative" next to uncalibrated pixel units, with no trace of the
  "limited interpretation" banner that was on screen when it was made. That
  moves this from a display inconsistency to a **provenance defect in a
  shareable artifact**, and it is squarely W2 territory.

  **The strain export makes the contradiction internal to one dictionary.**
  Exporting the ε_xx map (2026-08-27) produced XMP provenance containing, as
  adjacent keys, `"quantitative_status":"quantitative"` and
  `"strain_frame_reason":"qr_rotation_not_calibrated"` — the same record both
  asserts the result is quantitative and states that the rotation calibration
  it would need is absent. The burned caption likewise reads
  `scan space · quantitative · 1 [pix]/px · … · strain_frame=detector`. This is
  no longer two views disagreeing; it is **one artifact disagreeing with
  itself**, and it is the artifact meant to travel to a colleague.

  A defensible reading exists — `.quantitative` may be intended as "these are
  real measurements, not exploratory", distinct from "carries physical units" —
  but a user cannot be asked to hold two meanings of one green word, and the
  two readings are never distinguished on screen. **Fix is a judgement call and
  is not attempted here** (acceptance is evaluation only): either the status
  consults readiness, or the badge says what it means (e.g. "measured, detector
  px"). Owner: a trust-fixes session; it belongs with W2's error-honesty work
  rather than with polish.

- **TB1's staged fixtures are GONE, and F1.26 cannot be driven.** Found
  2026-08-27 while attempting the row: `References/training_dataset/` contains
  the four `.h5` cubes and **no `.mac4dstem.h5` sidecar at all**. Two files the
  drive kit asserts are present are missing:
  (1) `polycrystal_2D_WS2.mac4dstem.h5` — the deliberately foreign sidecar
  recording a 200x200 scan crop against a 128x128 file, which the kit says was
  *"already staged"* and *"verified by readback"*; it is the entire fixture for
  **F1.26**, and without it the row has nothing to observe; and
  (2) `sim_Au_data_all_binned.mac4dstem.h5`, which the kit describes as a real
  prior session's sidecar and offers as an option for **F1.3f**.
  Neither was deleted by this session — the kit's own cleanup block was never
  run. **F1.26 is BLOCKED on re-staging**, and F1.3f loses one of its two
  routes. Re-staging is a `tools/` job (the kit says the original was written
  through `BraggVectorEMDWriter.mergeCalibration`), not something a Track B
  drive should improvise, because a hand-made fixture that differs from what
  the app writes would test the wrong thing. Owner: whoever next picks up
  sitting 2.

- ~~**The dataset inspector's preview thumbnails are aspect-stretched.**~~ — **Fixed 2026-08-27**, reported by the release owner and re-driven on screen after the fix; record in [the closed-items archive](archive/closed-items-2026-08.md). The sweep it triggered found a fourth stretched call site and is the reason no `MetalImageView` is left without an aspect constraint.

- **The launch screen's Prepare / Analyze / Preserve cards are too large.**
  Release owner, 2026-08-27, while driving TB1: three full-width cards stacked
  top-to-bottom spend a lot of vertical space on what is a three-way choice,
  and they push the actual entry points (Open Dataset… / Open with Options… /
  Reopen / Try Demo) and the recents list far down the window. **Owner's
  suggestion: lay them out side by side.** A design preference, not a defect —
  recorded rather than fixed inline because acceptance is evaluation only, and
  because it changes what the app draws and therefore wants its own Track B
  row. Cheap and self-contained; a good candidate for the polish successor to
  S18, or any session with slack.

- **At minimum pane width the pane header degrades badly.** Seen while driving
  F1.32's narrow case (2026-08-27, demo dataset, right pane at its 171pt
  floor): the title truncates to `Vi...` and the blue **"Relative" badge wraps
  one letter per line**, rendering as a vertical `R-e-l-a-t-i-v-e` ribbon
  taller than the header itself. It reads as broken rather than as compressed.
  **Pre-existing, not S18** — the header is untouched by it; S18's overlay work
  is what put a pane at that width for the first time. The bottom overlays
  themselves behave correctly there (that is F1.32 passing). Fix is probably a
  `lineLimit(1)` plus `fixedSize` on the badge, or hiding the badge below some
  width. Owner: S18's polish successor, or whichever session next touches
  `ProductWorkspaceViews`.

- **Selected-area diffraction's scan-mask-to-tile correspondence is unpinned.**
  Demonstrated by experiment, not argued (Gate B on S18, 2026-08-27): replacing
  the per-tile mask slice at `Core/Analysis/VirtualDetector.swift:354` with
  `Array(fullMask[0..<range.count * d.rx])` is **green on every harness in the
  repo, including all 37 in `scientific`**. With a region covering only some
  scan rows, the later tiles reuse row 0's mask, so **scan rows the user
  deliberately excluded are summed into the pattern** — wrong science, plausible
  numbers. It survives because `tools/virtual-detector-residency` compares
  resident against streaming and both take the same wrong slice. **Pre-existing,
  not an S18 defect** (the line is untouched by it); S18's review is simply what
  found it. Fix: a ground-truth case in `tools/virtual-detector-test` with
  ry ≥ 4 and a region whose y-extent covers only some rows, comparing
  `tiledDiffraction(maximumTileRows: 1)` against the whole-cube path. Owner:
  whichever session next touches virtual diffraction.

- **`releaseResident()` is asserted by a derived number, so a leak is
  invisible.** Gate B (2026-08-27) made `releaseResident()` stash the cube in a
  private property before nilling `residentCube` — the `MTLBuffer` is then never
  deallocated — and the residency harness's I6 section,
  `DatasetResidencyTests.testReleaseReturnsToStreamingAndGivesTheBytesBack`, the
  whole unit suite and all 37 scientific harnesses stayed **green**.
  `ResidentCube.byteCount` is `descriptor.byteCountAsFloat32`
  (`Core/Data/ResidentCube.swift:70`) — computed from the descriptor, never
  measured — and every assertion reads `isResident` or `residentByteCount`, so
  "the bytes came back" is currently unfalsifiable. Fix: observe the buffer
  weakly (or probe allocation) across the release rather than asserting a
  derived count. Pre-existing; matters more the day a control makes residency
  reachable.

- **No fixture exercises the resident read paths under any `LoadSpecification`.**
  Gate B ran five mutations against the view-vs-source stride arithmetic in
  `FourDArray.pattern(ry:rx:from:)` and `TileGPUSource` — source scan width for
  view width, double-applied scan-crop offset, source detector stride, a bin
  divisor — and **all five are semantic no-ops on every fixture in the tree**,
  because every resident array in the repo is full-extent (scanOffset 0,
  source == descriptor, detectorBin 1, scanCrop nil). The two cropped+resident
  cases that exist (`tools/load-spec-test:521-526`,
  `tools/two-spec-analysis-test:744-757`) exercise `scanTile` only, never
  `pattern(ry:rx:)`. So both S18 changes are correct by reasoning and unasserted
  by machine outside the full-extent point. Fix: add a `pattern(ry:rx:)`
  comparison inside `two-spec-analysis-test`'s existing `residentTileOffset`
  loop, which already walks a full-extent and a scan-crop specification. Owner:
  the session that ships a residency control, or S11.

- **#37 — cancelling the virtual detector takes a long time.** **Measured by
  S18, 2026-08-27** — `tools/performance-baseline`, three new benchmarks, on a
  64x32x128x128 synthetic cube (134 MB) with 4-row tiles (16 tiles), M3,
  7 repeats after 1 warmup:

  | what | median | min | max |
  |---|---|---|---|
  | streaming, best case (cancel at a tile boundary) | **0.006 ms** | 0.004 | 0.011 |
  | streaming, **bound** (one whole tile) | **5.4 ms** | 4.0 | 6.7 |
  | resident, **bound** (the one indivisible dispatch) | **13.2 ms** | 11.1 | 16.0 |

  **Second run the same day, 5 repeats after 1 warmup, same machine:** streaming
  best case 0.008 ms, streaming bound **5.5 ms** (stable), resident bound
  **20.3 ms** — against 13.2 ms in the morning. The streaming bound reproduces
  tightly; **the resident bound does not**, varying by half again between runs
  on one machine. Anything quoting it — S20's release table especially — should
  give a range, not a point. The conclusion is unaffected: streaming's bound is
  single-digit ms and dispatch-only, so #37's cost is the per-tile read.

  **The check granularity is not the problem.** A user clicking Cancel waits
  at worst one tile and on average half of one — single-digit milliseconds
  here, which nobody would describe as "a long time". So the reported cost is
  in the part this measurement deliberately excludes: the harness reads from a
  synthetic in-memory source, so each tile is dispatch-only and the **read**
  half of the per-tile bound is missing. On a real file that read is the whole
  story, and over a NAS it dominates — **#37 is therefore an I/O item, and it
  belongs with S9**, not with the cancellation checks. Re-measure against a
  real reader when S9 has NAS access; the benchmark takes a descriptor and a
  cube, so pointing it at one is a small change.

  **The 2026-08-17 review's counter-argument is confirmed, not refuted.**
  Resident cancellation is **coarser**, by 2.5x here: the resident path is one
  `waitUntilCompleted` with checks either side, so a cancel is honoured only
  after the whole dispatch returns. The harness found this the hard way — its
  first version cancelled after the first progress tick, and on the resident
  path the *only* tick is `progress?(1)` after the dispatch has already
  finished (it arrived at 21.36 ms of a 21.36 ms pass). There is no mid-pass to
  cancel into, which is why the two paths are now measured differently and
  named for what each actually measures. It feels better only because the whole
  resident dispatch is short.
- ~~**A resident cube still pays ~0.375 × working set in staging copies.**~~ —
  **Landed by S18, 2026-08-27; the Gate B second read RAN 2026-08-28 and it
  SURVIVED** — see the Gate B outcome entry below. When resident, `FourDArray.scanTile` copied
  out of the buffer into a Swift `[Float]`; `TilePrefetcher` held two of those,
  and `tiledDPStatistics` / `tiledDiffraction` / `tiledMeasuredOrigins` /
  `tiledCenterOfMass` then built a third copy as an `MTLBuffer`. Peak ≈ cube +
  3 × (working set / 8), reached during `activate` itself. Found by adversarial
  review 2026-08-17.

  All four now go through `TileGPUSource` (`Core/Analysis/VirtualDetector.swift`),
  which binds the resident buffer at the tile's byte offset via a new
  `cubeOffset:` on the four `MetalEngine` entry points. **The tiling is
  deliberately unchanged** — same ranges, same partials, same combination order
  — so the results stay bit-identical rather than merely close, which is what
  lets `tools/virtual-detector-residency` keep asserting exact `==` on the two
  float-order-dependent reductions. Offsets are whole scan rows, so Metal's
  4-byte `device`-address-space alignment is automatic.

  **How the claim is checked, since equality alone cannot see a staging copy:**
  `FourDArray.residentTileCopies` counts tiles materialized out of the cube, and
  the harness asserts the four reducers add zero. Reintroducing the copy makes
  it fail (16 copies observed); zeroing the byte offset makes DP-max differ at
  index 0. Both controls were run.

  **Still staging, and out of S18's bounded list:** `TiledDiskDetection.detectAll`
  copies each tile into a fresh `MTLBuffer` the same way. It is not the same
  size of change — the offset has to thread through the whole multi-dispatch
  `detectAll(cube:descriptor:kernel:params:)` chain rather than one
  `setBuffer` call — so it is recorded here rather than smuggled in. Owner:
  whichever session next touches disk detection.
- ~~**`FourDArray.pattern(ry:rx:)` ignores the resident cube**~~ — **Landed by
  S18, 2026-08-27; the Gate B second read RAN 2026-08-28 and it SURVIVED.** It always read
  through the reader, so browsing diffraction patterns stayed disk-bound while
  the panel read "Resident" — the indicator over-promised. A pattern is now
  sliced straight out of the cube at `(ry * rx + rx) * qy * qx`, and
  deliberately **not** cached: the slice is a memcpy out of memory already held,
  so caching would duplicate up to 96 patterns of the resident cube for no saved
  I/O.

  The equality this rests on was not previously asserted anywhere: the cube is
  filled by `readScanTile` while the streaming path answers with `readPattern`,
  and nothing checked that a reader's two entry points agree pattern for
  pattern. `tools/virtual-detector-residency` now compares all 35 patterns and
  counts reader reads (must be zero). Controls run: a wrong offset differs at
  (ry 0, rx 1); disabling the branch reads the file 35 times. **Unverified on
  screen at all**: no shipping control requests `.resident`
  (`App/DatasetResidency.swift:34`, and `AppState.preloadResidentCube()`'s own
  comment at `App/AppState.swift:2701-2703`), so this path is Track-A-only
  until an admission control exists. Track B row F1.36 was queued for it and
  **withdrawn the same day** — it named a control that does not exist. The
  motivation originally written for this fix was wrong in the same way: the
  Performance panel never reads "Resident", so it was not "over-promising" to a
  user. The fix is still right — the harnesses and any future control need it —
  but it was justified by a scenario the app cannot produce.
- **Cancellation is *coarser* when resident, not better.** The resident branch
  checks cancellation either side of one indivisible `waitUntilCompleted`; the
  streaming path checks once per tile. **Now measured (S18, 2026-08-27): 13.2 ms
  resident against a 5.4 ms per-tile streaming bound on a 134 MB cube — 2.5x
  coarser**, and it scales with the cube while the streaming bound scales with
  the tile. Still academic at these sizes; the numbers and the method are under
  **#37** above. **Correction, 2026-08-27 (Gate A):** an earlier version of this
  line said residency is "a property of a button the user pressed". There is no
  such button — `DatasetResidency.request(_:on:)` has no caller under
  `mac4DSTEM/`, so this coarseness is a property of the harnesses and of any
  future admission control, not of anything a user can trigger today.
- ~~**#38 — the image panes' scroll monitor consumes every scroll in the window.**~~ — **Fixed by S18, 2026-08-27** (scoped by event-time geometry instead of a remembered hover). Record in [the closed-items archive](archive/closed-items-2026-08.md). **Live residual: Track B row F1.33 has never been driven**, so the fix is unverified on screen.
- ~~**#43 — the acceptance gate breaks if a session is saved for a training
  dataset**~~ — **FIXED 2026-08-18** (`noDatasetFound` treated as input, not
  error; the glob deliberately left alone so the skip path stays exercised;
  both guards verified by control); record in
  [the closed-items archive](archive/closed-items-2026-08.md).
- **#31 — `validationIssues` is O(n²) and runs in a SwiftUI view body.**
- **#32 — `isSymmetry`'s bijection check has no fixture coverage**, and its
  stated counterexample does not exercise it.
- **#30 — origin calibration over a NAS runs at ~3 MB/s.** Investigation.
- **#11 — no WS₂ crystal model.** Scope question; `polycrystal_2D_WS2` cannot
  reach ACOM without one.
- **#18 — the campaign cannot reproduce the app's strain result on Si_SiGe.**
  Test-harness gap. **Mechanism localized by S8's instrumented diff
  (2026-08-25, three campaign runs on the real cube, spacing=10):** the
  failure is in `estimateLatticeBasis`'s clustering SCALE, before any basis
  pair is ever tested. At ~every position a bright peak sits 2.85–8.92 px
  (q05–q95) from the reference origin — the **direct beam, scattered by
  origin-fit residuals** (this is the #46 dataset: plane-fit RMS ≈ 11.7 px
  exceeds the ≈ 5 px probe radius) — and survives `minRadius = 2`. The
  nearest-peak median is therefore 5.82 px while the true shells sit at
  17–42 px, so `clusterTolerance = 0.18·5.82 ≈ 1.05 px`; every true
  reflection fragments into ~300-member pieces (three fragments around one
  physical reflection at (−25, −15.5) in the dump), all under the 8% support
  floor (800 of 10,000), and `candidates=0` — the recorded "No sufficiently
  supported, well-conditioned lattice basis" with zero pairs examined.
  **Hypothesis refuted by pre-registered prediction:** `minRelative` (the one
  detector knob the 2026-08-04 overrides could not reproduce; override added
  as `MAC4DSTEM_DISK_MIN_RELATIVE`) — raising it to 0.02 removed 81,820
  peaks and left the nearestRadius quantiles **byte-identical**, candidates
  still 0: the near-beam population is intensity-strong, not weak noise.
  **RESOLVED at the mechanism level by the owner probe, 2026-08-25 evening
  (app driven on the real cube with `MAC4DSTEM_STRAIN_DEBUG=1`; strain
  succeeded — κ 4.84 vs the 2026-08-04 record's 4.80, 100% indexed,
  RMS 0.99 px).** The single differing input is the **reference origin**:
  - App dump: `origin=(64.000, 64.000)` — exactly the detector-centre
    FALLBACK (`calibration.meanOrigin ?? centre`), i.e. `meanOrigin` was nil
    at strain time even though the inspector said "Origin: Measured in app"
    (the not-quantitative fit — RMS ≈ 11.7 px, the #46 numbers — evidently
    does not populate `meanOrigin`). Under that origin the direct beam sits
    inside `minRadius = 2` at EVERY position and is excluded:
    observations = 248,384 detected − 10,000 exactly; nearestRadius
    q05–q95 = 13.97–15.44 (the true first shell); typicalRadius 14.43 →
    clusterTolerance 2.60; 98 clean clusters, 24 candidates, chosen basis
    g1=(4.675, −15.080), g2=(21.494, −20.804), κ 4.84, support 99.9%.
  - Campaign dump: it faithfully references ITS fitted mean origin
    (71.066, 64.062) — ~7 px off detector centre — so the beam survives at
    2.85–8.92 px at every position and poisons the clustering scale
    (typicalRadius 5.82 → tolerance 1.05, candidates=0).
  **The app succeeded BECAUSE the bad origin fit was gated out and the
  fallback happened to be the true beam centre; the campaign failed by
  trusting the measurement the app's own gate rejects.** Two candidate
  fixes, neither made in S8 (science changes, own Gate B): (1) the
  `typicalRadius` estimator should not admit a direct-beam residual cloud —
  floor `minRadius` at the probe radius or scale it with origin-fit quality
  (the `SessionGates` policy iDPC consults); (2) the campaign should adopt
  the app's origin gating instead of using a non-quantitative fitted mean —
  feeds the S12/S13 sane-origin/measure-Q split. Latent app-side risk to
  note: a genuinely off-centre beam with `meanOrigin` nil would fail in the
  app exactly as the campaign does. Si_SiGe strain parity records remain
  campaign-evidence-only until one of the fixes lands.
- **#15, #19, #20** — open measurement questions, low priority.
