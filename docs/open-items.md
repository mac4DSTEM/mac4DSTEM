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
  for S1's investigation. ~~Three sidecar-identity questions headed for
  **S4**~~ — **closed by S4, 2026-08-24** (rename/relocate, sidecar
  recognition on the open path; the extension/open-panel-filter half is an
  owner question queued for TB1). Still open from S1: the concurrent-HDF5
  crash, the fabricated `?? .fullExtent` provenance, and the status-line
  path leak, all below.
- The Track B §F1 queue → **TB1** (after S1, S3–S6).
- Strain frame → **S8**; ~~iDPC gate, iDPC zero-fill, disk-detection error
  attribution and the burned-in caption truncation → **S7**~~ — **all four
  closed by S7, 2026-08-25** (see `docs/v2-release.md` §9); **#18** → **S8**.
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
- **The residency threshold is unmeasured; `.automatic` is DROPPED (v2 S3,
  2026-08-19), not dormant.** The mode that consulted the threshold no longer
  exists — the shipped default request is `.streamed`, holding a cube takes an
  explicit `.resident` request, and behaviour is unchanged because `.automatic`
  always streamed. The mechanism a returning `.automatic` needs is kept and
  pinned: `ResidencyAdmission.admits`, `measuredWorkingSetFraction` (nil, by
  decision — never set it), and `tools/residency-sweep/`. Why it cannot come
  back yet: the threshold can only be set from a sweep past ratio ~0.5, and the
  three checked-in training cubes top out at 0.19 on this machine (1.00 GB
  against a 5.33 GB working set), where residency still pays 106x — no knee
  exists in the data. **Post-v2, per the 2026-08-18 owner decision:** a
  second-machine sweep re-opens `.automatic`; if two machines disagree, the
  rule needs a second term, not a compromise value.
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
- ~~Physical iDPC does not require the origin fit to be quantitative.~~
  **Closed by S7, 2026-08-25:** both call sites now ask one owner
  (`App/SessionGates.originQuantitativeRefusal`, which IS
  `Calibration.originFitRefusal`); a refused fit renders qualitative iDPC and
  the DPC controls quote the refusal (`AppState.idpcOriginFitRefusal`).
  Track B row F1.25 drives it on `downsample_Si_SiGe_exp`.
- ~~`DPC.integrateIDPC` returns a zero-filled image on invalid input.~~
  **Closed by S7, 2026-08-25:** every failure throws a typed `DPC.IDPCError`
  naming the precondition; `applyDPCDisplay` clears the image and presents on
  a throw; `tools/idpc-test` gained the negative controls.
- ~~Disk-detection tile read errors are reported as an FFT failure.~~
  **Closed by S7, 2026-08-25:** the tiled `detectAll` returns nil only on
  cancellation and otherwise throws `DiskDetection.FullScanError` naming the
  scan rows and the underlying error; `runDiskDetection` reports it verbatim.
  `TiledDiskDetectionErrorTests` pins the attribution with a failing source.

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

- **The vendored HDF5 dylibs carried invalid code signatures — found and
  fixed 2026-08-25, with one half honestly unexplained.** The first
  `run-tests.sh unit` after S6 killed every HDF5-touching test at 0.000 s,
  each in a fresh process. Crash reports (primary evidence, not the test
  output): `SIGKILL (Code Signature Invalid)`, `CODESIGNING / Invalid
  Page`, inside `dlopen` — dyld rejecting a library. `codesign -vv` on the
  repo-root `libhdf5.dylib` / `libaec.0.dylib` / `libsz.2.dylib`: *"code or
  signature have been modified"* — the committed bytes are self-inconsistent
  (machine-independent fact). The unsigned gate embeds them verbatim; the
  signed MCP build re-signs on embed, which is why it never failed. Fixed by
  ad-hoc re-signing the three source dylibs (`codesign -f -s -`); verified:
  the gate's HDF5 cluster went fully green on the next run. **Recorded
  unknown, per Gate D:** the same bytes passed this same gate on 2026-08-19
  on the same OS build (no update since 08-10, dylibs untouched in git since
  commit `e7fb809`) — why dyld tolerated them then is not established, and
  the first diagnosis ("an OS update tightened enforcement") was refuted by
  `softwareupdate --history` before it could ship. Release builds are
  unaffected (embedding re-signs with the real identity).
- **One unreproduced flip of the new binned-detector replay test,
  2026-08-25.** `ReplayExecutionTests.testARecipeRecordedOnABinnedDetector…`
  failed once (0.413 s, parallel full-suite gate run, assertion text
  swallowed by `-quiet` — the S17 observability gap, bitten again) and then
  passed: twice under MCP, once in isolation under the gate's exact
  configuration, and once in a verbose full-suite re-run (320/1,
  sidebar-only). One flip in five runs, no captured assertion. **Watch
  item:** if it flips again, reproduce with the non-`-quiet` form (full
  suite, fresh DerivedData, `CODE_SIGNING_ALLOWED=NO`, grep `Test case|
  XCTAssert`) so the assertion survives; do not chase it on one anecdote.
- **Carried findings and decisions from S6 (2026-08-25)** — the replay
  executor landed with the honest-refusal rules below; each residual names
  its owner:
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
  - **Fitted origin maps do not survive a promote** (pre-existing, surfaced
    by S6's DPC precondition): per-position maps fitted on a rehearsal are
    crop-sized, and the full-extent restore's shape check drops them — so a
    recipe recorded against "calibrated origins" refuses after promote with
    a calibrate-then-run-by-hand message. Same inverse-mapping family as the
    S10 item; also means replayed disk/strain/ACOM run against whatever
    origin basis the promoted session holds (their own scale guard catches
    the ACOM case). TB1 should expect the DPC refusal, not read it as a bug.
  - **Parallax/ptychography are NOT in the replay record** — S6's decision,
    carried from S5's deviation: no recording sites exist, the family is
    seven inter-dependent product stages, and ptychography is not
    bit-reproducible. A promoted session re-runs that family by hand.
    Folding it in is its own post-v2 session; the per-result controls
    already travel in `SessionControlRehydration`.
  - **A user-initiated analysis mid-replay steals the Cancel control**
    (pre-existing operation semantics, newly relevant): a run started while
    a replayed step executes replaces the current operation token, so Cancel
    targets the newer run and the hours-long replayed step loses its cancel
    path. The recipe-side half was fixed in S6 (caller-keyed recording
    suppression); the operation-collision half is S18-class polish.
  - **The custom-cubic model id does not encode the lattice constant**
    (`custom_cubic_<structure>_z<Z>`), so ACOM replay's custom-cubic
    resolution arm could, in a restored session whose custom fields drifted,
    resolve the recorded id with a different a₀. Same-session promotes are
    exact. Fix belongs with the next recipe-vocabulary change: record the
    lattice constant in the acom step and require it to match.
  - **Per-kind replay contracts live in three places** (record site, parser,
    applier) held together by tests, not structure — a plan field parsed but
    never applied compiles clean. Noted for whichever session next adds a
    recorded kind: co-locate the three limbs per kind in `ReplayPlan.swift`.

- **Carried findings from S3's Gate A review (2026-08-19)** — real, verified
  against the tree, deliberately not fixed in-session; each names its owner:
  - **The open unwind choreography exists in three copies** —
    `openFileAsync`, `commitPendingLoad`, `promoteToFullExtent` each hand-roll
    `begin → activate → cancelled/!hasDataset → discard+finish →
    runCurrentAnalysis → cancelled → discard → [remember] → finish`, and the
    ordering rules are documented in only one copy. Collapse into one shared
    tail when any of the three is next touched. Includes two shared hazards,
    both pre-existing shapes: a cancel landing between the last check and
    `finishDatasetLoading` is silently swallowed (the load completes as a
    success), and a second initiator's `beginDatasetLoading` (e.g. ⌘O during a
    running load) replaces the shared `datasetLoadCancellation` token so
    Cancel only cancels the newer load. S3 guarded promote's own entry
    (`!isLoadingDataset`); the open-during-load direction remains. → **S18**,
    or whichever session next edits an open path.
  - ~~**Promote and the recovery record disagree about frames.**~~
    **FIXED 2026-08-24 (S5).** `DatasetRecoveryRecord` now carries the load
    specification its coordinates are expressed in; the restore applies a
    position only in its own SCAN frame and inside the extents — it **never
    clamps** (the clamp was the fabrication) — and a successful promote
    re-stamps the record so the persisted pair describes the promoted view.
    Pinned by `SessionReplayTests` frame-rule tests, each observed failing
    under a discriminating mutation; old persisted records without the frame
    still decode (pinned on the production coder).
  - **Owner design question: should promote carry the scan position across?**
    Today a successful promote lands on Prepare at (0,0) — inherited from the
    2026-08-05 "reopens land on Prepare" decision. Promote is a continuation
    gesture, and `specification.scanOffset` makes carrying the position
    well-defined. Not asserted as a defect; queued for the owner at **TB1**
    alongside F1.14.
  - **Multi-window recents can lose updates** (pre-existing, surfaced by the
    S3 extraction): each window's `AppState` holds its own `RecentDatasets`
    snapshot over one `UserDefaults` key, so window B's save can clobber an
    entry window A just persisted. Single-window use — the shipped reality —
    is unaffected. Fix wants a shared instance or store-level merge; unclaimed.
  - **`openRecent`'s failure path leaves `recoveryRecord` dangling**
    (pre-existing asymmetry, faithfully carried by the extraction): a dead
    recent is removed from the list but the "Reopen" menu item survives and
    dead-ends in "No recoverable dataset is available." Unclaimed, low.

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
  | 2026-08-19 ~15:26 (S3 baseline; S1+S2 in tree) | exit 0 | passed (8.66 s) |
  | 2026-08-19 ~16:00 (S3's changes in tree — new inspector control) | exit 0 | passed |
  | 2026-08-25 (S6 in tree, MCP `test_macos`) | — | **failed** (1029/945/961 pt vs 871+allowance) |
  | 2026-08-25 (S6 STASHED — clean tree, same session) | — | **failed, byte-identical heights** |
  | 2026-08-25 (S6 committed, owner freed disk, gate run ×3) | exit 65 ×3 | **failed all three** (first run also hit the dylib-signature defect below) |
  | 2026-08-25 (S7 session: MCP `test_macos` ×3 + `run-tests.sh unit` ×1) | exit 65 | **failed all four**, heights byte-identical across the day (1029/945/961) — a red day end to end, as 08-19 was a mixed one |
  | 2026-08-25 later (S8 session: MCP `test_macos` ×2, pre- and post-seam) | — | **failed both**, heights byte-identical to each other (1027/943/963) but **2pt off the S7 numbers from earlier the same day** — the measured heights drift BETWEEN sessions while staying frozen within one, which fits the machine-state hypothesis and rules out anything in S8 (pre-change run identical) |

  **2026-08-25 adds two facts.** (1) S6 is excluded the same way S1 was: the
  stash experiment produced the identical three failures with identical
  measured heights on the clean tree, same machine, same hour. Red again
  after green on 08-19 — the fourth flip on an unchanged-code axis. (2) The
  failing measurements ARE reachable from the command line **via the MCP
  `test_macos` route** — the assertion text with both numbers came through
  intact, which the 2026-08-19 note said `xcodebuild` alone could not
  produce. S17's "make the number reachable" job has a working path.

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
- ~~The burned-in caption on exported figures truncates.~~ **Closed by S7,
  2026-08-25:** the caption wraps and the figure grows to hold it, and the
  full provenance record additionally travels as machine-readable PNG
  metadata (a JSON `Description` chunk beside `Title`/`Software`) —
  `AppState.exportedImageProvenanceRecord` / `pngProperties`, round-trip
  pinned through a real file by `ExportProvenanceTests`. Track B row F1.24.
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
- **One remaining `contentVersion` staleness hazard.**
  `UI/ProductWorkspaceViews.swift:719` passes a constant `0`, so the comparison
  panel uploads its texture once and never again — swapping products of the same
  shape would show stale pixels. Still latent; owned by **S18**. *(The other two
  instances of this class — both preview call sites hashing dimensions only —
  were fixed by S4 on 2026-08-24 with `MetalImageView.contentVersion(of:)`,
  which S18 can reuse here.)*
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
  violation; belongs with the trust fixes. *(The related schema-stamp defect —
  `mac4dstem_session_schema` stayed `"5"` across a format addition, so the
  stamp identified nothing — was **fixed by S5, 2026-08-24**: schema "6"
  derived from one constant, plus `mac4dstem_min_reader_schema` with refusal
  on read and rewrite. The `?? .fullExtent` fabrication itself is UNCHANGED
  and still owed to the trust fixes.)*

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
- **The configurator's real-space and diffraction-max panes render a
  single flat colour ON SCREEN — the data behind them is verified
  healthy.** Found on TB1 sitting 1 (2026-08-25, sim_Au, screenshots
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
- **The configurator sheet still clips a text line at its bottom edge.**
  Same screenshots: the caption below "GPU budget" is cut mid-height at
  900×760 — the clipping S4's `:44` fix was meant to end. Small, but the
  row (F1.17) explicitly requires no clipped content, so it is a finding,
  not a nit. Likely the same fix session as the item above or S18.
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
  **Still open — why the app's 2026-08-04 session succeeded** on (reportedly)
  the same inputs. That is now a 5-minute owner probe, not a session: run the
  app on Si_SiGe from Xcode with env `MAC4DSTEM_STRAIN_DEBUG=1`
  (`StrainMapping.estimateLatticeBasis` dumps origin, radius quantiles, top
  clusters and candidate pairs to stderr — S8's instrument, print-only),
  compute strain, send the STRAIN_DEBUG lines. If the app fails too, the
  2026-08-04 record's inputs were not what the frame analysis concluded; if
  it succeeds, its dump names the differing input directly. **Candidate code
  fix, deliberately NOT made in S8** (science change, own Gate B): the
  `typicalRadius` estimator should not admit the direct-beam residual cloud —
  e.g. floor `minRadius` at the probe radius or at a multiple of the
  origin-fit RMS when the fit is judged non-quantitative (the same
  `SessionGates` policy iDPC consults). Until then every Si_SiGe strain
  parity record remains evidence about the campaign, not the app.
- **#15, #19, #20** — open measurement questions, low priority.

## Code hygiene

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
- **31 `.fixedSize(horizontal: false, vertical: true)` sites in `UI/`**
  (measured 2026-08-19 by S3's review; an earlier claim of 22 had already
  drifted — the count moves with every UI change, the *audit* is the item),
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
