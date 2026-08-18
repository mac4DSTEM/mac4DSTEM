# Open items

Everything still live after **v1.0.0** (tagged 2026-08-06).

> **Active feature work is planned separately** in
> [`docs/load-pipeline-plan.md`](load-pipeline-plan.md) — load progress, a
> resident in-memory cube, crop/bin on open. It is kept out of this file on
> purpose: every item here is UI/workflow-only and touches no `Core/`, which is
> what makes this list safe to hand out as implementation prompts. Two items
> below are claimed by that plan and are noted where they appear (**#36** —
> now fixed by stage L1 — and **#37**).

Closed items are not here — the full v1.0 record is
[`docs/archive/v1.0/ui-workflow-backlog.md`](archive/v1.0/ui-workflow-backlog.md),
kept as history. Cited numbers are prefixed `#` and refer to that file.

## Phase 2 was planned — 2026-08-17

**No decisions are owed.** The contract is [`docs/v2-scope.md`](v2-scope.md):
priority order, refusal rule, version policy, and the eight decisions with their
reasons. `docs/v2-planning-draft.md` is deleted; every proposal in it was
accepted, changed, or rejected.

Settled here and previously blocking: **a cropped/binned cube is a *view* of the
source file** (`load-pipeline-plan.md` §7.1). **L3 is unblocked.**

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

New work that came out of the session:

- **A free-space preflight in `tools/run-tests.sh`** — fail immediately with
  "need N GB free, have M" rather than letting a full disk produce three
  different failure sets that look like code regressions. ~15 lines; not yet
  written.
- **Delete or keep `mac4DSTEMUITests/` + `tools/ui-qc-playthrough/`?** Retired
  as the acceptance test and unmaintained, but still in the tree and still
  building. Deleting it also removes the only consumer of the accessibility
  identifiers that `docs/v1-scope.md` deliberately kept — check
  `mac4DSTEMUITests/Support/AXDriver.swift` before pulling the thread.

## Release-owner actions — **done 2026-08-14/15**

Developer ID signing, notarization and a clean-account launch all completed.
The repository is public at `github.com/mac4DSTEM/mac4DSTEM` under GPL-3.0, and
`v1.0.0` carries a signed, notarized, stapled `mac4DSTEM.dmg` linked from
mac4dstem.com.

The pipeline is now in the repo rather than in someone's shell history:
`tools/release/build-developer-id.sh` → `notarize.sh` (takes an `.app` *or* a
`.dmg`) → `make-dmg.sh` → `notarize.sh` again. Both the app and the image are
stapled, because Gatekeeper assesses the file the user actually opened.
`docs/releasing.md` predates `make-dmg.sh` and does not describe it yet.

Two things learned that are not obvious and cost time:

- **Stapling rewrites the DMG, so it changes the checksum.** `make-dmg.sh`
  prints a SHA-256 *before* the ticket is attached; publishing that one gives
  users a hash that does not match the download. Take the hash from the
  notarize step, or after.
- **The notary credential is not always readable from a non-interactive
  process.** `notarytool` failed with *No Keychain password item found* from an
  automated shell while working fine from Terminal; re-running
  `store-credentials` interactively fixed it permanently.

## Verification debt

- **No automated visual baseline, and there will not be one soon.** Every
  playthrough run used `--no-screenshots`, so the acceptance evidence for the
  tag is numeric only: the numbers the app reports through its own controls,
  never what it draws. **As of 2026-08-17 the answer is Track B, not a
  screenshot harness** — the XCUITest playthrough is retired and
  [`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md) is the
  procedure. So any claim that a UI change "looks right" rests on someone having
  looked; say who, and when. It has earned that standing: two defects on tag day
  with all 30 harnesses green (the unreachable Result colormap, the readiness
  row calling a measured origin "Missing") and three more in the clean-account
  run.
- **`tools/bragg-spacing-probe/` gates nothing** and cannot: it needs a
  gitignored multi-gigabyte datacube. It stays a diagnostic. **`tools/residency-sweep/`
  (added 2026-08-17) has the same standing** for the same reason.
- **The residency threshold is unmeasured, so residency is dormant.** L2's
  mechanism ships behind `.automatic`, which streams until
  `ResidencyAdmission.measuredWorkingSetFraction` is set — and it can only be set
  from a sweep that reaches past ratio ~0.5. The three checked-in training cubes
  top out at 0.19 on this machine (1.00 GB against a 5.33 GB working set), where
  residency still pays 106x, so no knee exists in the data. **Needs a run of
  `tools/residency-sweep/run.sh` on one of the release owner's large cubes
  (≈7.46 GB / ≈4.25 GB), copied to local storage first.**
- **The app has never run on the macOS version it claims to support.**
  `LSMinimumSystemVersion` is 14.0; every build, test run and manual session to
  date has been on macOS 27. Nothing between 14 and 26 has been exercised, and
  `SidebarLayoutTests` below is direct evidence that this app's layout does
  shift with the OS. Only a real older machine answers this.
- **`README.md` and `CHANGELOG.md` claim `tools/run-tests.sh all` — exit 0, 30
  harnesses.** Measured at the tag; **nobody has reproduced the aggregate
  since**, and the count has moved twice — `virtual-detector-residency` landed
  2026-08-17 and `load-spec-test` and `load-spec-calibration` on 2026-08-18, so `scientific` is
  now 32 and `all` is 34. A verification claim that a reader cannot reproduce is the kind
  that costs credibility with exactly the people who check — so either re-run
  `all` and restate it, or say what was actually run.

  **Measured 2026-08-18, and it is worse than "not re-run":** `run-tests.sh all`
  cannot reach a single harness. It runs `unit` first and `set -e` aborts there
  on the intermittent `SidebarLayoutTests.testEveryWorkspaceSidebarFitsItsColumn`
  — exit 65, zero `==>` lines. So the standing note that **#43** is "what
  currently stops `run-tests.sh all` from passing at all" (repeated in
  `CLAUDE.md` and `docs/load-pipeline-plan.md` §5) was wrong on this machine: the
  sidebar test stops it first and #43 was never reached. Confirmed pre-existing —
  the same test fails the same way on a stashed clean tree.

  **Re-measured after #43 was fixed, later the same day: `all` still aborts in
  the unit stage.** Fixing #43 did not change that and was never going to. But
  every *other* component of the aggregate has now been run individually and is
  green on this machine:

  | component of `all` | result, 2026-08-18 |
  |---|---|
  | `unit` | **1 failure** — `testEveryWorkspaceSidebarFitsItsColumn`, intermittent, pre-existing |
  | `scientific` | exit 0, **32 harnesses** |
  | `real-data-acceptance` | exit 0, 4 cubes golden, 2 sidecars skipped |
  | `package-test` | exit 0 |

  So the honest claim a reader can reproduce is **"every part of `all` except one
  intermittent layout test"** — not "exit 0, N harnesses". The single thing
  between here and an aggregate number is that test, and a layout threshold that
  drifts with the machine is its own problem, not a gate to widen.

### First clean-account acceptance run — 2026-08-14

The v1.0 DMG was downloaded from mac4dstem.com in a fresh macOS account that had
never run the app, installed by drag, and driven through Prepare → Bragg disks →
Strain on `downsample_Si_SiGe_exp`. It worked: 248,384 peaks, 100% basis
consensus, 100% indexed, a quantitative ε_xx map with the expected SiGe layer
periodicity, and **no Gatekeeper warning at any point**.

That single run — perhaps fifteen minutes of human time — produced three defects
that no harness in the repo can reach. They are listed under *Known, scoped, not
blocking* below. This is the second time the Track B pattern in
Track B ([`docs/visual-acceptance-checklist.md`](visual-acceptance-checklist.md))
has outperformed the automated suite on its own terms.

## From an external read-only review — VERIFIED here, 2026-08-18

A second agent reviewed the repo at `839bf49` and produced a findings document.
**Only what was independently checked against this tree is recorded below**; the
review also contained several factual errors, listed at the end so nobody
re-imports them.

These are scientific-presentation defects, not crashes, and they are the exact
class `docs/v2-scope.md` §4 exists to refuse: **a plausible result that a
careful user would reasonably misread as a quantitative claim.**

- **Strain is computed and exported in the DIFFRACTION frame, labelled only
  εxx/εyy/εxy, and displayed over scan coordinates.** Verified:
  `Core/Analysis/StrainMapping.swift`'s own header says *"Strain is expressed in
  diffraction-space x/y"*; no rotation is applied anywhere in that file; and
  the vendored py4DSTEM docstring for `get_strain_from_reference_g1g2`
  (`References/py4DSTEM-dev/py4DSTEM/process/strain/latticevectors.py:324`)
  explicitly says the result is *"oriented with respect to the x/y axes of
  diffraction space — to rotate the coordinate system, use
  get_rotated_strain_map()"*, which exists at `:409` and which this app does not
  call. The tensor is not wrong *as an unrotated diffraction-frame tensor*. The
  defect is that nothing on screen or in the export says so, while the map is
  drawn over scan axes — and a 90° R–Q rotation swaps the normal components and
  changes the sign convention of the shear. **Fix: either rotate into the scan
  frame, or label and export it as diffraction-frame strain together with the
  R–Q transform.** Until then, no export of this should be described as
  sample-frame strain.
- **Physical iDPC does not require the origin fit to be quantitative.**
  `AppState.idpcPhysicalCalibration` gates on `calibration.hasFittedOrigin &&
  calibration.hasRotation` only, while `Calibration.swift:254` *does* consult
  `originFitIsQuantitative` for the readiness report. So Prepare can label a fit
  "Not quantitative" and physical iDPC still exports in radians. A gate that one
  workflow honours and another ignores is worse than no gate.
- **`DPC.integrateIDPC` returns a zero-filled image on invalid input** — bad
  dimensions, a malformed CoM array, a non-finite parameter — and the caller
  publishes it like any other result. **A numerical failure becomes a plausible
  zero-phase specimen.** It must return a typed error.
- **Disk-detection tile read errors are reported as an FFT failure.**
  `TiledDiskDetection.swift:42` swallows any tile error with `try?`; the caller
  presents *"Disk detection failed to initialize its FFT plan."* On a long
  experimental scan that sends the user hunting in entirely the wrong place.

Credible but **not yet verified here**, so treat as leads rather than findings:
the Q-calibration estimator differing materially from py4DSTEM's radial-profile
fit and the file/session mean origin not reaching it; ACOM omitting py4DSTEM's
default `power_radial=1.0` radial weighting; HDF5 discovery assuming
`[Ry,Rx,Qy,Qx]` and auto-selecting a `/data` object without checking axis
metadata; and the strain estimator's weighting deviation being absent from
exported provenance.

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
list above is only what was re-derived from this tree.

**Framing caveat.** The review repeatedly reasons about "the shortest credible
path to v1" and recommends narrowing scope before release. **v1.0.0 shipped on
2026-08-06 and is public.** Read those sections as *what v1.1 should fix before
the claims are widened*, not as release advice.

## Known, scoped, not blocking

- **`SidebarLayoutTests.testEveryWorkspaceSidebarFitsItsColumn` is
  intermittent.** It failed on macOS 27 — uncalibrated Prepare measuring 933pt
  against 871pt of column, 62pt of overflow against a 60pt allowance — and
  **passed on 2026-08-17**, in a `tools/run-tests.sh unit` run that exited 0 on
  the same OS. **Not a regression either way:** `git diff v1.0.0..HEAD` over
  `mac4DSTEM/`, both test targets and `tools/` was empty when the failure first
  appeared, so no app code had changed. The test's own comment records the
  overflow as 49pt when written, giving 11pt of headroom.
  **An intermittent layout threshold is worse than a stable red one**, because a
  green run stops being evidence — and this test has form: it is a sibling of
  `testSidebarContentNeverDrawsOverTheTitlebar`, which stayed green for months
  with #16 visibly on screen. The question is not what broke but **whether 60 was
  ever a threshold or just one machine's measurement rounded up**, and what the
  run-to-run variable is (display scale? font? window server state?). Until that
  is known, do not treat either outcome as information.
- **The burned-in caption on exported figures truncates.** Observed on a strain
  export: `…basis_mode=consensus · reference_mode=whole-scan · displa…`. That
  caption *is* the provenance record and it is the part that travels into a
  paper, so cutting it mid-word defeats the reason it is burned in at all.
- **Colorbar and scale bar collide on tall, narrow maps.** Seen on a 200×50 scan
  with a display rotation applied: the `-0.04145 0 0.04145` colorbar and the
  `20 [pix]` scale bar stack into each other at the foot of the pane. Both are
  bottom-anchored with no awareness of one another.
- **"Recent-file access could not be remembered."** Logged after a successful
  open in the clean-account run: the app loaded the file but could not persist a
  security-scoped bookmark, so Open Recent will not reopen it. **Caveat before
  anyone chases this:** the test file was a *hard link* staged into
  `/Users/Shared`, which is unusual enough that it may be the cause. Re-test with
  a plain copy before treating it as an app defect.
- **The legacy `.icns` tops out at 256px.** After the move to an Icon Composer
  `.icon`, the compiled fallback carries only 16, 16@2x, 128 and 128@2x. macOS 26
  and later render from the `.icon` source and are correct at every size; on the
  macOS 14 floor this app declares, anything larger than 256px is upscaled — Get
  Info, Quick Look, large Finder icon view. The Dock is unaffected. Undecided
  whether to ship a legacy PNG set alongside.
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

Fix is in the row, not the identity: show enough of the path to disambiguate
(volume or parent directory), or mark entries that live on a network volume.
Not done — it is UI work and belongs in a pass that can be looked at.

**PASSED — §F1.2 and §F1.3, both first-time.** The dataset inspector's *Preview*
section reads *"Sampled preview · every 8th position · 280 of 16,218"* — the
stride stated, as invariant I4 requires — above real-space, mean-pattern and
max-pattern thumbnails, and closes with *"Not a result — cannot be exported or
saved."* No control offers to export or promote it. L5's preview half is now
confirmed on a real 3.96 GB cube rather than only in `DatasetPreviewTests`.

Incidental corroboration: the inspector reports **Chunks: contiguous** for this
file, which is the case where `H5Reader.loadPushdown` correctly claims `.full` —
the chunked case that made it conditional is a different file class.

**WORTH CONFIRMING — the scan extent is printed in two orders in one window.**
The sidebar header reads `106 x 153 scan` while *Dimensions* reads
`Scan (Ry x Rx) 153 x 106` and *Shape* reads `153 x 106 x 256 x 256`. Each is
defensible alone — an image convention of width x height against array order —
but the sidebar carries no axis labels, so the two disagree on screen with
nothing to reconcile them. This is the shape of the defect Track B found on tag
day (a readiness row contradicting its own detail line). Needs a second look
before it is called a defect; recorded so it is not lost.

**WITHDRAWN — §F1.1 could not pass on any dataset.** It asked the release owner
to watch the L2 preload phase; `makeResident` refuses immediately because
`ResidencyAdmission.measuredWorkingSetFraction` is `nil` by decision, so no such
phase runs. The 4.25 GB cube was more than large enough — the row was wrong. It
is struck from the checklist with the reason, and reinstated only when the
threshold is measured. **The lesson is about writing checklists, not about
residency:** a Track B row must be checked against what the build actually does,
or it spends the one resource Track B is expensive in — a person's attention.

- **L4 stays `[~]`: its review ran, but on the default model rather than the
  Fable 5 / `/code-review ultra` the plan names**, and two of its findings are
  still open. The review could not refute the array math on any composition it
  built (all bit-exact against py4DSTEM) and found one CRITICAL latent defect —
  four detector-frame values derived from the source rather than the view, plus
  a fifth instance in a claim the plan had already made about `minPeakSpacing`.
  Both fixed. **What is still owed** is in `load-pipeline-plan.md` §5 under
  "STILL OWED": no view reads `LoadedView`'s display surface, so L4's "state it
  in the UI" and "label the result" items are not done; and the fixture has no
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
- **`measureOrigin` performs a single centre-of-mass refinement, not an
  iteration to convergence**, so its output sits ~0.6 px from the converged
  windowed centre on the same fixture. Also pre-existing, also a deviation from
  what "centre of mass origin" implies to a reader. Recorded because a harness
  that assumes the returned origin is a fixed point of its own CoM will fail for
  this reason and look like a crop bug — it did, on 2026-08-18, before the
  arbiter was re-anchored on the fixture's analytic truth.
- **Two L3 residuals from the 2026-08-18 adversarial review, both unreachable
  today and both reachable the moment L5's configurator lands.**
  **(a)** `BraggVectorEMDWriter.transformedCalibration` rescales the origin,
  `qSize` and the probe radius by the *export* bin only; it knows nothing about
  `view.specification.detectorCrop`, and its origin-map shape check now compares
  against the *view* extent, so a source-extent map would fall silently through
  to an empty array. The export currently **refuses** a cropped view rather than
  carrying that defect; the refusal is lifted by L3's calibration re-reference,
  not before. **(b)** `FourDArray.tile(yRange:from:)` — the read offset out of a
  resident buffer — is only ever exercised at `lowerBound == 0` by
  `tools/load-spec-test`, so a bug in that offset would not be caught there.
- **`tools/load-spec-test` compiles `LoadSpecification.swift` with bare
  `swiftc`, which defaults to *nonisolated*, while the app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** So the harness validates
  different isolation semantics from the app, and cannot see an actor-isolation
  defect at all — that class showed up only in the app build (35 warnings, three
  classes of them "an error in the Swift 6 language mode"). Every `tools/`
  harness that compiles app sources has the same blind spot. Not a bug to fix so
  much as a limit to know: **the app build is the only gate for isolation**, and
  a stage that adds Core value types crossing into the reader actors should be
  built, not just harnessed.
- **No way to stop a dataset load in progress.** Requested by the release owner
  2026-08-18, during the Track B pass, on a 4.25 GB cube opened over SMB: pick
  the wrong file and the only exit is quitting the app. Analysis operations
  already have a Cancel (the *Origin calibration · Cancel* control is visible in
  the same screenshot); **the open itself does not**, and it is the longest
  uninterruptible wait in the product — worst on exactly the slow network source
  the welcome screen warns about.

  What it needs, and none of it is decided yet:
  - A cancel affordance on the loading card, next to the progress it is
    cancelling.
  - **A definition of what is released.** `AnalysisCancellationToken` already
    threads through `makeResident` and the tiled readers, and `FourDArray`'s
    generation counter already refuses to publish a superseded preload — so the
    machinery exists. What is undefined is the *destination state*: back to the
    welcome screen with no dataset, and every partial artefact dropped (the
    array, any staging buffer, the preview task, the half-built calibration).
  - **The failure mode to design against is a half-loaded dataset that looks
    loaded.** Cancelling into a state where the inspector shows dimensions for a
    cube whose pixels were never read would be worse than no cancel at all.

  Sits naturally with L5's configurator — same screen, same moment — but does
  not depend on it, and is worth doing on its own.
- **#17a — aspect-aware pane arrangement.** Built, then reverted on sight
  2026-08-05. Needs a design decision, not an implementation.
- ~~**#36 — no progress indication while a datacube loads.**~~ **Fixed
  2026-08-06** by `load-pipeline-plan.md` stage L1, and **confirmed on the real
  app** on a 3.96 GB cube (patterns and MB both counting, bar advancing).
- **#37 — cancelling the virtual detector takes a long time.** *Re-measure now
  that L2's mechanism is in.* The sweep gives a first indication that it may
  simply disappear on a resident cube: a whole-cube virtual image that takes
  996 ms streaming takes **9.4 ms** resident, and cancellation latency was
  bounded by the tile in flight. Not yet measured, and residency is dormant
  until the threshold is set, so the item stands.
- **A resident cube still pays ~0.375 × working set in staging copies.** When
  resident, `FourDArray.scanTile` copies out of the buffer into a Swift
  `[Float]`; `TilePrefetcher` holds two of those, and `tiledDPStatistics` /
  `tiledDiffraction` / `tiledMeasuredOrigins` / `tiledCenterOfMass` then build a
  third copy as an `MTLBuffer`. Peak ≈ cube + 3 × (working set / 8), reached
  during `activate` itself. **Any `f` the sweep recommends is measured without
  this overhead**, because the sweep only times `tiledImage`, which takes the
  single-dispatch fast path and allocates nothing — so a measured threshold must
  be discounted for it, or this must be fixed first. The copies are avoidable:
  `MetalEngine` already takes an `MTLBuffer` for all four, and
  `setBuffer(_:offset:index:)` could bind the resident buffer at the tile's byte
  offset with no copy at all. Found by adversarial review 2026-08-17.
- **`FourDArray.pattern(ry:rx:)` ignores the resident cube** and always reads
  through the reader, so browsing diffraction patterns stays disk-bound while the
  panel reads "Resident". The indicator over-promises.
- **Cancellation is *coarser* when resident, not better.** The resident branch
  checks cancellation either side of one indivisible `waitUntilCompleted`; the
  streaming path checks once per tile. Academic at the ~10 ms dispatch measured
  so far, possibly not on a cube near the residency threshold. Bears on **#37**.
- **#38 — the image panes' scroll monitor consumes every scroll in the window.**
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
- **#31 — `validationIssues` is O(n²) and runs in a SwiftUI view body.**
- **#32 — `isSymmetry`'s bijection check has no fixture coverage**, and its
  stated counterexample does not exercise it.
- **#30 — origin calibration over a NAS runs at ~3 MB/s.** Investigation.
- **#11 — no WS₂ crystal model.** Scope question; `polycrystal_2D_WS2` cannot
  reach ACOM without one.
- **#18 — the campaign cannot reproduce the app's strain result on Si_SiGe.**
  Test-harness gap.
- **#15, #19, #20** — open measurement questions, low priority.

## Code hygiene

- **22 `.fixedSize(horizontal: false, vertical: true)` sites remain in `UI/`**,
  including 4 in `TaskPrerequisiteChecklist` — the construct that caused #16.
  Safe today and covered by `SplitViewHeightTests`, but unaudited.
- **A saved sidebar divider can restore below the declared minimum.** Observed
  144pt against `ContentView`'s declared `min: 250`. Every string wraps harder
  there than the layout was designed for. Test harnesses pin the width
  explicitly (`pinSidebarWidth`); the app does not.

## Working methods that earned their keep

Kept because they changed outcomes, not because they are tidy:

1. **Cost a UI change before designing it.** `SidebarDensityMeasurementTests`
   turned "it feels crowded" into 63pt of workspace rows and a 332pt shape
   change, and made the choice between options a measurement rather than taste.
2. **Adversarially review anything touching the science, and review the
   *diagnosis*, not just the code.** Twice now — 2026-08-05 and 2026-08-06 — a
   fix passed every test written for it, including one verified to fail without
   it, and was still wrong. Both times the refuting evidence was already in a
   log nobody had re-read.
3. **Never widen a gate that fails silently.** The QC harness's miss paths call
   `recordError` and continue; a control hidden behind a disclosure turns a
   failure into a finding nobody reads. Both are documented at the call sites.
4. **Open the app.** On the day of the tag, with all 30 harnesses green, ten
   minutes of driving the real app produced two defects the suite could not see:
   a colormap control missing from the only workspace that needed it, and a
   readiness row contradicting its own detail line. Neither is exotic; both are
   invisible to a test that never looks at the screen.
5. **A green suite can be green about the wrong thing.** On 2026-08-14 a change
   to how harnesses resolve their toolchain left 22 of them sourcing a helper by
   a `$0`-relative path *after* `cd`-ing to their own directory. They were
   broken. The suite stayed green at 28/28, because `tools/run-tests.sh` invokes
   each harness with an **absolute** path, so `$0` was absolute and the `cd` was
   harmless. The failure existed only for the direct invocation — the one
   `README.md` and `docs/technical-overview.md` tell a reader to use. It
   surfaced by accident, while running `package-test` by hand for an unrelated
   reason. Before trusting a suite, ask what calling convention it exercises,
   and whether that is the one anyone actually uses.

   **Second instance, 2026-08-17 — and this one was self-inflicted by a grep.**
   Adding `Core/Data/ResidentCube.swift` broke every standalone harness that
   compiles `FourDArray.swift`. Finding them with
   `grep -l "Core/Data/FourDArray.swift" tools/*/run.sh` returned **3 of 8**,
   because five runners spell it `"$SRC/Data/FourDArray.swift"` with
   `SRC="$ROOT/mac4DSTEM/Core"`. `unit` and `scientific` both passed; the four
   missing runners live in `all` (`real-data-acceptance`) and outside the gate
   entirely (`bragg-spacing-probe`, `real-acom-benchmark`,
   `training-dataset-campaign`), so nothing failed until the aggregate ran.
   **Search these runners by basename, never by path prefix** — the prefix is
   written three different ways. The check that actually works:

   ```sh
   for f in tools/*/run.sh; do
     grep -q "FourDArray\.swift" "$f" && ! grep -q "ResidentCube\.swift" "$f" && echo "$f"
   done
   ```

   Related trap from the same afternoon: a backgrounded
   `tools/run-tests.sh all 2>&1 | tail -12; echo "exit=${pipestatus[1]}"`
   reports the **echo's** status to the task runner, so a failing gate is
   announced as "completed (exit code 0)". The real status was in the printed
   line. Put the exit code where you will read it, not where the harness will.
6. **A test written for your own fix proves nothing until it fails without it.**
   Standard practice here for science changes, and it paid off in the UI layer
   too: the first colormap test failed against the fix *and* against the old
   code, and only became useful once it was made to report what it could
   actually see. Which was nothing — SwiftUI builds a `Picker`'s menu lazily for
   a real assistive client, so in-process every pop-up is blank. The test now
   asserts the *decision* instead of the rendering, and says why at the call
   site so the dead end is not rediscovered.
