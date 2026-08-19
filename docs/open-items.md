# Open items

Everything still live after **v1.0.0** (tagged 2026-08-06).

> **Active feature work is planned separately** in
> [`docs/v2-release.md`](v2-release.md) — the v2 release contract and session
> plan, which superseded `docs/load-pipeline-plan.md` on 2026-08-18. Most
> items below are claimed by a numbered session there; the mapping is in the
> next section. (The original rule that every item here is UI/workflow-only
> no longer holds — the 2026-08-18 verified findings touch `Core/` — so do
> **not** hand this file out as implementation prompts without checking the
> item's owning session and its gate.)

Closed items are not here — the full v1.0 record is
[`docs/archive/v1.0/ui-workflow-backlog.md`](archive/v1.0/ui-workflow-backlog.md),
kept as history. Cited numbers are prefixed `#` and refer to that file.

## The v2 release was planned — 2026-08-18

**No decisions are owed.** The contract, the gates and the numbered sessions
are [`docs/v2-release.md`](v2-release.md). Sessions claiming items in this
file:

- ~~Sidecar restore failure + `recordedLoadSpecification`/bookmark defect +
  `H5Eset_auto2` silencing → **S1**.~~ ~~The two-spec analysis fixture →
  **S2**.~~ **Both closed 2026-08-19** — see `docs/v2-release.md` §9 for what
  shipped, and
  [`docs/archive/s1-sidecar-under-the-sandbox.md`](archive/s1-sidecar-under-the-sandbox.md)
  for S1's investigation. Four items they turned up are still open and listed
  below; three of them are sidecar-identity questions headed for **S4**.
- The Track B §F1 queue → **TB1** (after S1, S3–S6).
- Strain frame → **S8**; iDPC gate, iDPC zero-fill, disk-detection error
  attribution and the burned-in caption truncation → **S7**; **#18** → **S8**.
- The 8 GB death / DM4 `.mappedIfSafe` suspect → **S9** (Gate D — the
  local-vs-NAS `footprint` experiment first).
- The four unverified review leads + the bounds-convention sweep → **S11**.
- `measureOrigin` frame-dependence and single-refinement → weighed in **S12**;
  **#29** → **S12** reads the campaign data that settles it.
- **#11** WS₂ → **S14–S16**.
- `SidebarLayoutTests` intermittent → **S17** (Gate D).
- Colorbar/scale-bar collision, **#38**, the scan-extent two-orders question,
  the comparison-panel `contentVersion`, `pattern(ry:rx:)` ignoring the
  resident cube, **#37** re-measure → **S18**.
- The stale `all` claim in README/CHANGELOG → **S19**; the legacy `.icns` →
  mooted by S19's floor raise to macOS 26; the `docs/releasing.md` gap →
  **S19**.
- The free-space preflight → **S0, done 2026-08-18**. CI for `unit` + the
  synthetic half of `scientific` on the public repo → **S21**.
- The resident-cube staging copies → **S18** (the `setBuffer(_:offset:)`
  elimination). The second-machine sweep → **post-v2** (`.automatic` is
  dropped in S3, so the threshold no longer blocks anything).

**Unclaimed and staying open:** #17a (design decision), #30 (NAS speed),
#31, #32, #15/#19/#20, the recents-bookmark hard-link retest, the
sidebar-divider minimum, and the `.fixedSize` audit. *(The
delete-`mac4DSTEMUITests` question was decided 2026-08-18 — see the entry
above; the deletion itself rides S18.)*

**One cheap experiment, unclaimed (2026-08-18) — give the agent eyes on the
Mac app.** Three candidate mechanisms, one time-box, keep whichever earns it:
**(a)** a debug-only tool rendering chosen SwiftUI views to PNG via
`ImageRenderer` — in-process and permission-free, but blind to
lazily-rendered chrome (the colormap test already proved in-process rendering
lies about `Picker` menus); **(b)** `screencapture -l <windowID>` of the real
running app — real pixels, needs a one-time Screen Recording grant to the
Claude Code host (expect the re-grant-after-update behaviour Accessibility
already shows); **(c)** headless
SwiftUI preview rendering through the real pipeline (no screen grant) — the
original candidate, Apple's `mcpbridge` `RenderPreview`, exposed **zero
tools even to the real client** on 2026-08-18 (see
`docs/development-process.md` §2), so probe **XcodeBuildMCP's `xcode-ide`
workflow** for the equivalent first and fall back to the raw bridge only if
Apple documents it. The configurator's flat-colour previews (F1.3b)
would have been visible to any of the three in one render. **Never
acceptance**: Track B stays human and the eval-only rule is unchanged; this
is development feedback only. If all three fight the framework, drop the
experiment and record why.

## Phase 2 was planned — 2026-08-17

**No decisions are owed.** The contract was [`docs/v2-scope.md`](v2-scope.md)
— **superseded 2026-08-18 by [`docs/v2-release.md`](v2-release.md)** — where
the priority order, refusal rule, version policy, and the eight decisions with
their reasons remain recorded. `docs/v2-planning-draft.md` is deleted; every
proposal in it was accepted, changed, or rejected.

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

- **A free-space preflight in `tools/run-tests.sh`** — **DONE 2026-08-18 (S0).**
  `require_free_space`, 8 GB for the `xcodebuild` modes and 4 GB for the
  harness-only ones, failing with "need N GB free for X, have M GB" before any
  build starts. The floors are margin, not measurement; the reasoning and the
  zsh `local path` trap that broke the first version are in the code comment.
- **DECIDED 2026-08-18: delete `mac4DSTEMUITests/` + `tools/ui-qc-playthrough/`.**
  The check this entry asked for is done, and it refuted the entry's own
  premise: `AXDriver` is **not** the only consumer of the accessibility
  identifiers — all four `tools/ui-smoke-test/*.applescript` drive the same
  identifiers (`dataset.card`, `workspace.primaryAction`, …), and the ~91
  `.accessibilityIdentifier(...)` sites live in *app* code that no deletion
  touches. So the identifiers stay (smoke tools today, VoiceOver/automation
  later), and nothing else holds the target: the repo carries **no** shared
  scheme, and `tools/run-tests.sh` deliberately never invokes it (its `:20`
  comment). What deletion involves: `git rm -r` both directories plus
  removing the target from `project.pbxproj` (**19 reference sites** — the
  one delicate part), verified by a build and `run-tests.sh unit` in the same
  sitting. **Ride v2 S18**, or any session with slack.

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
  now 33 and `all` is 35. A verification claim that a reader cannot reproduce is the kind
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
  | `scientific` | exit 0, **33 harnesses** (35 as of 2026-08-19, S2) |
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

  **Observation log, so S17 starts from a series rather than an anecdote**
  (same OS, macOS 27; app code identical across all of these — verified by
  `git diff` over `mac4DSTEM/` on each occasion):

  | date | `run-tests.sh unit` | this test |
  |---|---|---|
  | 2026-08-17 | exit 0 | passed |
  | 2026-08-18 | exit 65 | **failed** (933pt vs 871pt, 62pt overflow) |
  | 2026-08-19 ~09:00–10:00 | exit 0, twice | passed, twice |
  | 2026-08-19 ~11:00 | exit 65 | **failed, three times in a row** |
  | 2026-08-19, after freeing disk | exit 65, full `run-tests.sh unit` | **failed** (220 passed, 1 failed) |

  **It flipped WITHIN A SINGLE DAY on an unchanged tree**, which is the sharpest
  observation yet: green twice in the morning, red three times two hours later,
  same machine, same OS, same commit. That kills "it depends on the checkout" and
  narrows the run-to-run variable to machine state — display configuration, window
  server, or something that drifts with uptime and load. Between the two groups
  the machine had been building continuously and the release owner had been
  driving the app from Xcode.

  **Excluded by experiment, not assumption:** the red runs happened while S1's
  UI change (a new inspector section) was in the tree, so it was the obvious
  suspect. Reverting `DatasetInspector.swift` and `InspectorPanels.swift` to HEAD
  and re-running gave the **same failure**, and the test drives
  `openDemoFixture()` — no file path, so no sidecar, so the new section cannot
  render at all. Not S1's.

  **The disk was not the variable, and that is now measured.** The 11:00 runs
  happened at ~7 GB free, below the preflight's 8 GB floor, so `run-tests.sh unit`
  refused (exit 69) and the suite was run directly instead. After freeing space
  the full gate ran at 10 GB and produced **the identical result** — 220 passed,
  1 failed, same test. So the direct run was not distorted by the near-full disk,
  and the preflight's margin is genuinely margin rather than a live constraint on
  this suite. It also makes the morning-green/afternoon-red split harder to
  explain away: four consecutive reds now, across two disk states.

  **Two concrete inputs for S17, both learned the hard way here:**
  1. A passing run prints nothing, so three of the five observations above carry
     no measurement. Instrument the measured height on **every** run.
  2. **The failing run's number could not be retrieved either.** Running the test
     alone under `xcodebuild`, with and without `-quiet`, produced no assertion
     text at all — only "failed". So the 933pt/871pt figures from 2026-08-18 came
     from somewhere else (Xcode's UI), and a CI or terminal run yields nothing to
     diagnose from. **S17's first job is making the number reachable from the
     command line**, before any question about thresholds can be settled.
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
- **`recordedLoadSpecification` bypasses the security-scoped bookmark and
  swallows its own failure.** `App/AppState.swift:1416-1431` — the function L6
  depends on for "reopen with the same crop" — reads the sidecar through the
  *derived* path only (`:1419`), never through `resolvedSessionSidecarURL`, and
  `openFileAsync` drops the scoped URL immediately before calling it
  (`:1801-1804, 1808`). The failure is swallowed by `try?` at `:1421`. **If the
  sandbox/bookmark hypothesis above is right, F1.3f (crop survives session
  save/reopen) cannot pass today and will fail silently** — the app reopens at
  full extent and says nothing. Driving F1.3f is therefore both the L6 acceptance
  row and a second discriminator for the sidecar question.
- **Two more `contentVersion` staleness hazards, same class, both latent.**
  `UI/ProductWorkspaceViews.swift:719` passes a constant `0`, so the comparison
  panel uploads its texture once and never again — swapping products of the same
  shape would show stale pixels. And both preview call sites hash dimensions
  only (see the configurator entry below). Neither bites today; both bite the
  moment a view shows a *chosen* image rather than a fixed one.
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
  `StemImageView.swift:468`, `ProductWorkspaceViews.swift:760` and
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

  Adjacent, same code, land together: the 720×640 sheet **scrolls and clips its
  own headers** (`LoadConfiguratorView.swift:44`); and the sampling status line
  is determinate on one open (*"Sampling a preview · row 1 of 36"*) and
  indeterminate on another (*"Sampling a preview…"*) because
  `openFileForConfiguration` omits the `progress:` argument
  (`AppState.swift:1487-1490`) that the normal path passes
  (`AppState.swift:2172-2180`) — by L1's rule the configurator path is the wrong
  one. **Also requested, and not in any plan:** a single real diffraction pattern
  beside the mean/max, and the cube's real-space dimensions stated in the dialog.
  **If that single-DP picker lands, `contentVersion` must become value-dependent
  first** — it is a hash of dimensions only at `LoadConfiguratorView.swift:142`
  and `DatasetInspector.swift:230`, so swapping to a different DP of the same
  shape would not re-upload the texture (`MetalImageView.swift:87`) and the
  picker would appear to do nothing.

  **The previews are also aspect-stretched** — `MetalImageView` maps the image to
  normalized view UVs (`Shaders/Colormaps.metal:44,49-51`), so a 106×153 scan is
  drawn into a ~332×220 box. The drag→crop math stays correct, but a user
  dragging a visually square box gets a non-square crop. Decide once the panes
  draw.
- **The app died on an 8 GB machine, with no crash report.** 2026-08-18 ≈19:55,
  Apple M3 MacBook Air, 8 GB, during repeated opens of multi-GB cubes (a 17.19 GB
  `055_STEM SI.dm4` had been cancelled minutes earlier). **No `.ips` crash report
  for `mac4DSTEM` was written at all**, which is itself the signal — a jetsam
  (memory) kill often leaves none. Corroborating, from
  `/Library/Logs/DiagnosticReports/`: `openAndSavePanelService` spun at 19:53
  and **Finder spun at 19:55:05**, i.e. the whole system was stalling, not just
  this app; and a `JetsamEvent-2026-08-18-173817.ips` earlier the same day lists
  `mac4DSTEM` among the processes present (**listed, not proven to be the
  victim** — jetsam reports enumerate everything running). **Not diagnosed.**
  What makes it worth chasing rather than filing under "small machine": the app
  is deliberately out-of-core and streams, so a bare open should *not* be able
  to exhaust 8 GB — if it can, something is holding more than it declares.

  **Measure the right number.** `SystemMonitor.residentMemoryMB()`
  (`Support/SystemMonitor.swift:12-21`) reports `resident_size`, but **jetsam
  kills on `phys_footprint`**, which includes compressed pages and IOKit/Metal
  allocations that `resident_size` misses. So the app's own Performance panel
  structurally cannot predict the kill it suffered, and any measurement taken
  from it will look innocent. Use `footprint -p <pid>` and `vmmap --summary`.

  **Predicted streaming ceiling, to tell "small machine" from "holds too much":**
  `FourDArray.scanTileRows()` (`Core/Data/FourDArray.swift:301-307`) sizes a tile
  at `recommendedMaxWorkingSetSize / 8` ≈ **683 MB** here, and the tiled pass
  holds three at peak — current tile, prefetched next tile
  (`Core/Analysis/VirtualDetector.swift:165,170-172`) and a full
  `makeBuffer(bytes:)` copy (`:177-181`) — so ≈**2.0 GB transient on a path that
  legitimately claims to stream**. A peak near 2 GB means the tile budget is
  mis-scaled; a peak near cube size means something holds the cube. Note the
  budget derives from a **GPU** hint that is 65% of physical RAM on this machine,
  and nothing bounds the tile by *free* RAM — while the same number is shown to
  the user as "GPU budget" beside "This selection (f32)"
  (`UI/LoadConfiguratorView.swift:255`), which reads as an invitation to load up
  to a figure that will get them killed.

  **The concrete suspect is not the resident cube — it is `DM4Reader`.**
  `Core/Data/DM4Reader.swift:56` maps with `.mappedIfSafe`, which is a *request,
  not a guarantee*: Foundation declines to map on network or removable volumes
  and **silently falls back to reading the entire file into memory**. The run
  that preceded the death opened a **17.19 GB `055_STEM SI.dm4` from the NAS** —
  a 17 GB anonymous allocation on an 8 GB machine, which is exactly the profile
  of a jetsam kill with no `.ips` and a system-wide stall. It also explains why
  Cancel left the machine wounded: the allocation happens inside `DM4Reader.init`
  before any cancellation token is consulted. **Cheapest check, no build needed:**
  open the same DM4 from a local copy and from the NAS, watching `footprint`. If
  local stays flat and NAS climbs toward file size, that is the answer.
- ~~**A session sidecar that provably opens fine can still fail to restore.**~~
  **CLOSED 2026-08-19 in S1.** Cause: the 2026-08-14 bundle-identifier change
  (`1e5727d`) gave the app a new, empty sandbox container, so no session bookmark
  resolved and the fallback read of the derived sibling was refused by the sandbox
  — **observed at 09:34:27, `errno = 1`/EPERM**, not inferred. Fixed by the seam
  `App/SessionSidecarLocator.swift`. The full investigation — five hypotheses, the
  pre-registration written before its answer was known, and the two refutations
  that changed the outcome — is in
  [`docs/archive/s1-sidecar-under-the-sandbox.md`](archive/s1-sidecar-under-the-sandbox.md).

  **Three things it turned up are still open and unowned — the next three items.**

- **Concurrent HDF5 use crashes the process.** `EXC_BAD_ACCESS` in
  `libhdf5.dylib`\`H5SL_search`, reproduced under lldb within a few dozen
  iterations, in the library. The bundled build is `Threadsafety: OFF` with
  `_H5E_stack_g` a plain global. This independently kills the race hypothesis
  far more cleanly than the ordering argument — **a race here predicts a crash,
  not a tidy status line** — and it is a live latent crash: `loadSession` runs
  on `Task.detached` while an `H5Reader` actor may be working, plus the
  uncancelled `preloadResidentCube` noted elsewhere in this file.

- **Fabricated provenance on any pre-2026-08-18 sidecar.**
  `AppState.swift:2331` does `sessionLoadSpecification = snapshot.loadSpecification ?? .fullExtent`.
  Since the attribute post-dates every sidecar written before 2026-08-18, such
  a sidecar saved from a **cropped** view is now asserted as full-extent rather
  than unknown — the app stating a specification it does not have. A P1
  violation; belongs with the trust fixes. Related: `mac4dstem_session_schema`
  stayed `"5"` across a format addition (`4e01c24`), so the schema stamp no
  longer identifies the format — which is exactly what S5's minimum-reader
  marker has to fix.

  **Both reproducers were destroyed on 2026-08-19 and nobody should go looking
  for them.** The two pre-2026-08-18 sidecars in `References/training_dataset/`
  were the only artefacts demonstrating this, and Track B driving overwrote
  both: `sim_Au_data_all_binned.mac4dstem.h5` at 09:35:21 and
  `downsample_Si_SiGe_exp.mac4dstem.h5` at 14:25:38 (6.38 MB of BraggVectors
  and a Strain map replaced by 8.9 kB of calibration). The **defect is
  unchanged** — `?? .fullExtent` still asserts a specification the file does
  not carry — but demonstrating it now needs a sidecar synthesised without the
  attribute, not one of these. Recorded because an item whose evidence has
  silently evaporated is how a real defect gets dismissed as unreproducible.

- **The status line leaks a full filesystem path.** The composed message runs
  ~330 characters including the absolute path, rendered raw at
  `ContentView.swift:1007` and `ProductWorkspaceViews.swift:427`. Track B
  screenshots go into public docs. Worth truncating the path for display while
  keeping it in the log. **Recurred visibly on 2026-08-19:** the S1 refusal
  line renders the full absolute path of the sidecar in the console pane, and
  it appears in the Track B screenshots taken that day. Still open.
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

  **Cost, since "taken for cost" is the reason the deviation exists:** the naive
  stride-1 window is O(qy·qx·bin²) per pattern against O(qy·qx) today, but a
  separable box filter restores O(qy·qx). The equivariant step is therefore
  probably cheap, and the shader header's assumption that it is expensive has
  never been measured. **S12 should weigh this on a measurement, not on the
  header.**
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
- ~~**"Save Calibration to Session Sidecar" wrote the file but never persisted
  the access grant.**~~ **FOUND BY TRACK B F1.3h AND FIXED, 2026-08-19.** Of the
  two publish paths, only `saveCurrentResultToSessionSidecar` stored a bookmark,
  so a calibration save granted access for that launch alone and the next launch
  hit the C10 failure again — while S1's own refusal message named that very path
  as the remedy. Both paths now share one `rememberSidecarGrant`. **No automated
  test could have caught it** (it needs a save panel and a real HDF5 write, and
  the defect was a missing call, not wrong logic) — the narrative is in
  [`docs/archive/s1-sidecar-under-the-sandbox.md`](archive/s1-sidecar-under-the-sandbox.md).

- **Once a sidecar grant exists there is no way to rename or relocate it — the
  save panel never appears again.** `writableSessionSidecarURL`
  (`Support/ResultExport.swift`) returns the granted URL immediately and only
  falls through to `NSSavePanel` when there is no grant. **The logic is
  pre-existing and unchanged by S1** — but before S1 no bookmark ever resolved,
  so the panel appeared on every save. Now grants resolve, so for any dataset
  whose sidecar has been saved once, it never appears again. **Third instance of
  the same shape in one session** (with the warm-cache defect and the
  InspectorPanels label): dormant code that arms itself the moment a grant
  starts resolving.

  Observed 2026-08-19 14:41, driving Track B F1.3i: three consecutive saves at
  :27, :31 and :46, each logging *"Saved calibration →
  downsample_Si_SiGe_exp.mac4dstem.h5"*, no panel, no opportunity to change the
  name.

  **Consequences, in order of how much they cost:**
  1. **A misplaced sidecar is permanently misplaced.**
     `calibrationData_bullseyeProbe.mac4dstem.h5` currently sits on the Desktop
     rather than beside its cube; there is no longer any way to move it back
     through the app. That directly undercuts release claim 3 — the sharing unit
     is *the cube plus the sidecar beside it*, and the app can strand the second
     half somewhere else with no way home.
  2. **It blocks Track B row F1.3i by construction** — that row asks the owner to
     rename the companion, which cannot be done. The row's *substance* was closed
     by unit test instead
     (`SessionSidecarLocatorTests.testTheInspectorLabelForARenamedSidecarNamesTheFileTheAppReads`,
     verified by breaking `location`), leaving only "does the SwiftUI view read
     that property" unverified — one line, checked by reading.
  3. Saving a copy elsewhere, or splitting a session into two companions, is
     impossible.

  **Shape of the fix, for whoever takes it:** a *Save Session Sidecar As…* item
  beside the two existing save commands, or a **Change…** control next to the
  sidecar name in the inspector's *Saved session sidecar* row — the place the
  user is already looking at the filename. Either re-offers the panel and calls
  `sessionSidecar.adopt` + `remember` with the new URL, which the seam already
  supports. **→ S4**, with the other two sidecar items; they are one coherent
  piece of work about the companion file's identity.
- **Opening a `.mac4dstem.h5` sidecar directly dumps a 60-line wall of tried
  paths and never says what the file actually is.** Hit by the release owner on
  2026-08-19 while looking for the saved session — a completely reasonable thing
  to try, and the app's answer is *"No 4D or 3D dataset found. Tried paths:"*
  followed by every probed path in the sidecar
  (`/braggvectors_root/result_strain_exx_42329a38/metadatabundle/mac4dstem/…`),
  rendered into both a modal **and** the background welcome screen at once.

  The app has everything it needs to answer properly: the sidecar carries
  `mac4dstem_session_schema` (`BraggVectorEMDWriter.swift:151`), which nothing on
  the open path ever checks. Recognising it should produce one sentence —
  *"This is a mac4DSTEM session sidecar, not a dataset. Open
  `sim_Au_data_all_binned.h5` beside it and this session loads with it."* — and
  ideally offer to open that sibling.

  **This is on the critical path for release claim 3, "hand a colleague the
  recipe."** The sharing unit is two files, the colleague receives both, and the
  one named after the session is the wrong one to double-click. The failure mode
  is therefore *expected*, not exotic. **→ S4** with the configurator work, or
  S7 if it is treated as error honesty; either way it is small, and the
  path-list wall is worth truncating for every error of this shape, not only
  this one.

  **Hit a SECOND time the same day, 2026-08-19 11:2x, and that is the argument
  for its priority.** The release owner — who designed the format — was
  deliberately driving Track B row F1.3h, was told in writing to open the cube,
  and still opened `downsample_Si_SiGe_exp.mac4dstem.h5` instead of
  `downsample_Si_SiGe_exp.h5`. The open panel offers both because the sidecar is
  a `.h5`, and the two sort adjacently under near-identical names. If the person
  who invented the convention picks wrong twice in one afternoon, a colleague
  receiving the pair will too, and the app's answer is a 30-line path dump. It
  also cost a Track B attempt, which is the scarcest resource this project has.
  **Two cheap parts, either of which alone would have prevented both incidents:**
  recognise `mac4dstem_session_schema` on the open path and say what the file is,
  and give sidecars a distinguishing extension or exclude them from the open
  panel's default filter.
- **The configurator never says what a detector crop COSTS, and it will let you
  crop the direct beam off the detector without a word.** Found by the release
  owner driving the build, 2026-08-19 — his question was "why is cropping in
  there at all, instead of only 2x/4x binning?", which is the right question to
  ask of a control that explains neither of its two reductions.

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
- **Nothing pins the virtual-detector mask boundary convention against
  py4DSTEM, and no harness can currently see a change to it.** Found by Gate B
  during S2 (2026-08-19). The app's circle mask uses `r2 < rOut2`
  (`Core/Analysis/VirtualDetector.swift:473`) and py4DSTEM uses strict `<`
  (`References/py4DSTEM-dev/py4DSTEM/datacube/virtualimage.py:636`), so **the app
  is correct today** — this is not a live defect. The gap is that flipping it to
  `<=` leaves both `tools/two-spec-analysis-test` and `tools/virtual-detector-test`
  at exit 0, because every comparison in both runs the same `makeMask` on each
  side, and a boundary-pixel change cancels. It is the shared-code limit of any
  self-comparison, and the fix is one assertion pinning `makeMask`'s output
  against an analytic mask, not a new harness. Cheap; nobody has done it.
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
  diagnostic (`FourDArray.swift:213`, `ResidencyAdmission.shouldAdmit`) that the
  same sources compiled bare do not produce at all — measured three ways.
  **But the warning does not gate:** `swiftc` exits 0 on it, so `set -e` never
  fires and `scientific` stays green. Making it bite needs `-warnings-as-errors`,
  which today would fail the build on that very warning. The app build therefore
  remains the only real gate; the flags buy visibility, not enforcement. Gate B
  also caught the first version of the flag list carrying three of the five
  features `SWIFT_APPROACHABLE_CONCURRENCY` enables while claiming to "match the
  app target"; all five plus `MemberImportVisibility` are there now.
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

- **Eight standing build-warning classes, two of them errors-in-waiting under
  the Swift 6 language mode — surfaced 2026-08-18 by the first full rebuild
  in weeks.** The actor-isolation class documented for `LoadSpecification`
  (fixed in L3) persists at more sites: `ResidencyAdmission.shouldAdmit`
  called from nonisolated contexts (`Core/Data/FourDArray.swift:213` —
  flagged *"error in the Swift 6 language mode"* — and
  `Core/Data/LoadConfiguration.swift:201`), `measuredWorkingSetFraction`
  referenced nonisolated (`LoadConfiguration.swift:199`), `defaultByteBudget`
  (`Core/Analysis/DatasetPreview.swift:114`), a MainActor-isolated
  `Equatable` conformance on `DatasetDescriptor` (also a Swift-6-mode error),
  a weak/strong capture mismatch (`App/DatasetResidency.swift:127`), and a
  no-op `await` (`App/AppState.swift:2044`). **Why nobody saw them: warm
  incremental builds re-emit nothing** — a raw `xcodebuild` run over the same
  code the same day printed zero warnings, because nothing recompiled. Found
  by the first `build_macos` through XcodeBuildMCP, which builds into its own
  fresh workspace. Most sites are the residency-admission surface that **S3
  touches anyway — take them as an S3 rider**; the `DatasetDescriptor`
  conformance may be wider, check its call sites there too.
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
