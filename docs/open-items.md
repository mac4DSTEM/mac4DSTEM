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

Closed items are not here — the v1.0-era record is
[`docs/archive/v1.0/ui-workflow-backlog.md`](archive/v1.0/ui-workflow-backlog.md);
v2-era closures move verbatim to
[`docs/archive/closed-items-2026-08.md`](archive/closed-items-2026-08.md)
(dated siblings follow as months pass), leaving a one-line tombstone here
only where something live leans on them. Cited numbers are prefixed `#` and
refer to the v1.0 backlog.

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
- ~~`SidebarLayoutTests` intermittent → **S17** (Gate D).~~ **Diagnosed and
  formally quarantined 2026-08-27**; two owner-visible rows remain in Track B.
- Colorbar/scale-bar collision, **#38**, the scan-extent two-orders question,
  the comparison-panel `contentVersion`, `pattern(ry:rx:)` ignoring the
  resident cube, **#37** re-measure → **S18, all landed 2026-08-27**; each
  entry below carries its own outcome. **Two things S18 could NOT finish and
  did not pretend to:** the Gate B second read of the two `Core/` changes
  (`pattern(ry:rx:)` and the staging-copy elimination) has not run — the
  session that wrote them is still the only one that has approved them, which
  is the one thing this repo's refusal rule forbids — and the
  `mac4DSTEMUITests` deletion below was refused by the environment, not
  declined. Both need the release owner.
- The stale `all` claim in README/CHANGELOG → **S19**; the legacy `.icns` →
  mooted by S19's floor raise to macOS 26; the `docs/releasing.md` gap →
  **S19**.
- The free-space preflight → **S0, done 2026-08-18**. CI for `unit` + the
  synthetic half of `scientific` on the public repo → **S21, authored
  2026-08-26** (`.github/workflows/ci.yml` + the README badge +
  `tools/lib/py4dstem-ci-constraints.txt`). **Run #1 (2026-08-26, `bbfd8b0`,
  owner push): `scientific` PASSED, exit 0 in 8m 30s — the first pass of the
  parity gate on any machine but the dev Mac (macos-26 runner, paravirtual
  Metal, pinned pip env all held). `unit` FAILED, exit 65 in 1m 40s — an
  early `xcodebuild` abort, far too fast to be the test suite, so NOT the
  S17 intermittent. Cause read from the log (owner pasted it, same day) and
  the project-format hypothesis (`objectVersion = 90`) is REFUTED — Xcode
  26.6 opened the project and compiled the tree fine. Confirmed diagnosis:
  `ContentView.swift:1728` as it stood that day (the decomposed expression now
  lives at `:1739-1740`, after S21's fix and S18's edits above it) hits
  "the compiler is unable to type-check this expression in reasonable time"
  on the runner's Xcode 26.6, while the dev machine's Xcode 27 beta
  type-checks it — a compiler-version-sensitive expression, not a semantics
  bug. Fixed same day (`5f98ded`, named sub-expressions; app built locally
  and on the runner). **Run #2 (`5f98ded`): `scientific` PASSED again
  (7m 59s); `unit` built and ran all 377 tests — the sole failure is the
  then-unresolved S17 sidebar test, reproduced on the runner. So that red badge
  was accurate. **S17 settled the test locally on 2026-08-27** (default-collapsed
  state isolated; uncalibrated Prepare explicitly skipped with diagnostics),
  but the workflow change has not been pushed: the next CI run is the evidence
  for a green badge, not this local result. The 180-min `scientific` timeout can
  be tightened from the ~8-min data when the workflow is next touched.
- The resident-cube staging copies → **S18, landed 2026-08-27** (the
  `setBuffer(_:offset:)` elimination; second read still owed). The
  second-machine sweep → **post-v2** (`.automatic` is dropped in S3, so the
  threshold no longer blocks anything).

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

Closed structurally — a different specification means a reopen, so one array
can never hold a buffer for a crop other than its own; pinned in
`tools/virtual-detector-residency`. Record, with the 2026-08-18 amendment
that corrected its first version, in [the closed-items archive](archive/closed-items-2026-08.md).

New work that came out of the session:

- ~~A free-space preflight in `tools/run-tests.sh`~~ — **DONE 2026-08-18
  (S0)**; record in [the closed-items archive](archive/closed-items-2026-08.md).
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
  sitting. ~~**Ride v2 S18**~~ — **S18 tried and was refused, 2026-08-27: the
  environment's permission classifier blocked every attempt to rewrite
  `project.pbxproj`, so nothing was deleted and the file is byte-identical.**
  The survey is done and holds: all eleven UITests object UUIDs begin with `2`
  (the app target uses `0…`, `mac4DSTEMTests` uses `1…`), they are referenced
  only by each other and by the project's own `children` / `targets` /
  `TargetAttributes` lists, and there is no shared scheme. The prepared script
  removes every block keyed by such a UUID plus every remaining line naming
  one. **Needs the release owner to run it**, then a build and
  `run-tests.sh unit` in the same sitting. Also still to do when it lands:
  CLAUDE.md's placement table and its `mac4DSTEMUITests/` bullet, and
  `tools/run-tests.sh`'s `-only-testing` comment, all of which name the target.

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
- **The app has never been driven on the macOS version it claims to support.**
  `LSMinimumSystemVersion` is 14.0; manual sessions to date have been on macOS
  27. CI now builds and runs the unit suite on macOS 26, but no Track B pass has
  exercised that OS and nothing from 14–25 has been exercised at all. Only a
  real older machine answers the visual/runtime half.
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

  At that point the honest claim was **"every part of `all` except one
  intermittent layout test"** — not "exit 0, N harnesses". The test was the
  single thing between that evidence and an aggregate run.

  **S17 update, 2026-08-27:** the uncontrolled persisted-disclosure state is
  now isolated and uncalibrated Prepare is an explicit diagnostic skip;
  `unit` exits 0 (378 passed / 4 skipped / 0 failed). That removes the old
  early-abort condition, but `all` still has not been run end to end. S19 owns
  the aggregate run and claim restatement; do not infer its result from the
  component table above.

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

- ~~Strain computed/exported in the DIFFRACTION frame, displayed over scan
  coordinates~~ — **Closed by S8, 2026-08-25** (owner decision: scan frame,
  live-derived; `Core/Analysis/StrainFrame.swift`; pinned by
  `tools/strain-frame-test`). Full closure record, including the py4DSTEM
  median-reference DEVIATION, in [the closed-items archive](archive/closed-items-2026-08.md).
  **Live residual (S8 Gate B finding 5):** a strain result restored from a
  pre-S8 sidecar is frame-silent on display and re-export
  (honest-by-omission; synthesizing `strain_frame=detector` at the restore
  site would be a true claim if anyone wants it closed). On-screen:
  F1.28/F1.29 queued.
- ~~Physical iDPC does not require the origin fit to be quantitative~~ —
  **Closed by S7, 2026-08-25** (one policy owner, `App/SessionGates`);
  record in [the closed-items archive](archive/closed-items-2026-08.md). Track B row F1.25.
- ~~`DPC.integrateIDPC` returns a zero-filled image on invalid input~~ —
  **Closed by S7, 2026-08-25** (typed `IDPCError`s); record in [the closed-items archive](archive/closed-items-2026-08.md).
- ~~Disk-detection tile read errors are reported as an FFT failure~~ —
  **Closed by S7, 2026-08-25** (`FullScanError` names the scan rows);
  record in [the closed-items archive](archive/closed-items-2026-08.md).

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
  - ~~Detector-frame recipe parameters do not replay after a
    detector-reduced rehearsal~~ — **CLOSED by S10, 2026-08-26**:
    `ReplayRecordFrameMap` re-references them at plan time (the exact
    inverse of the load-time re-reference), both carriers say so, and the
    S19 note is satisfied — "binned view re-runs unchanged" now holds for
    detector-reduced rehearsals (a nonzero absolute-intensity threshold
    still refuses by name); record in
    [the closed-items archive](archive/closed-items-2026-08.md).
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
  - ~~Promote and the recovery record disagree about frames~~ — **FIXED
    2026-08-24 (S5)**; record in [the closed-items archive](archive/closed-items-2026-08.md).
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

- **S17 diagnosed and removed the sidebar test's uncontrolled state; one
  visual case remains formally quarantined.** The historical 1029/945/961pt
  failure triplet is reproduced exactly by the persisted
  `sidebar.displaySection.expanded` preference. The numeric gate now injects a
  private, default-collapsed AppStorage store and still covers every calibrated
  workspace plus every uncalibrated workspace except Prepare. Collapsed,
  uncalibrated Prepare is an explicit dynamic skip: 933pt against 871pt on
  2026-08-27, because the former 60pt allowance is not a product invariant.
  CI retains and prints its geometry attachment. Local `unit`: **exit 0,
  378 passed / 4 skipped / 0 failed** (2026-08-27). Still live: the owner must
  drive the two S17 rows in Track B (collapsed uncalibrated Prepare and an
  intentionally expanded Display disclosure), and the changed workflow has
  not run on GitHub yet. Full diagnosis, observation history and deviations:
  [`docs/archive/v2-session-records/s17.md`](archive/v2-session-records/s17.md).
- ~~The burned-in caption on exported figures truncates~~ — **Closed by S7,
  2026-08-25** (wraps, figure grows, full provenance as PNG metadata);
  record in [the closed-items archive](archive/closed-items-2026-08.md). Track B row F1.24.
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
  version of this entry wrongly claimed it did (Gate A, same day). **Unverified on screen: Track B row F1.32**, which scores
  the WIDE case as well — a fix that stacked them always would pass a glance
  at a narrow pane and waste a third of every normal pane's bottom edge.
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
  `FourDArray.scanTileRows()` (`Core/Data/FourDArray.swift:353-359`) sizes a tile
  at `recommendedMaxWorkingSetSize / 8` ≈ **683 MB** here, and the tiled pass
  holds three at peak — current tile, prefetched next tile
  (`Core/Analysis/VirtualDetector.swift:233,238-240`) and a full
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
- ~~A session sidecar that provably opens fine can still fail to restore~~ —
  **CLOSED 2026-08-19 (S1)**: the sandbox denial was observed (EPERM), fixed
  by the `App/SessionSidecarLocator.swift` seam. Investigation:
  [`docs/archive/s1-sidecar-under-the-sandbox.md`](archive/s1-sidecar-under-the-sandbox.md);
  closure record in [the closed-items archive](archive/closed-items-2026-08.md).

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

- **The sidecar-restore path adopts a calibration in the SIDECAR'S frame
  without checking it against the opened view (S10 Gate B finding 2,
  2026-08-26).** `applySessionCalibration` (`AppState.swift`) adopts the
  saved calibration verbatim, and `loadSessionSnapshot` never compares
  `snapshot.loadSpecification` against the view actually opened — so a
  sidecar saved at full extent, restored onto a reconfigured
  (cropped/binned) view, leaves a source-frame calibration beside reduced
  pixels: the state the pre-S10 export refusal blocked wholesale, now
  covered only partially by the writer's bounds net (an origin numerically
  inside the smaller extent slips it — the net says of itself it is a net,
  not a proof). Pre-existing (S5-era mechanism); S10's lift arms the export
  half, and S10's `exportableRecipe` frame guard closes the RECIPE half of
  the same hole. Same family, found in the same review: a post-promote
  sidecar save stamps `loadedView.specification` (full extent) beside a
  rehearsal-frame replay record, so a later restore adopts the recipe as
  `.detectorIdentity` and a replay would run rehearsal numbers unmapped.
  Fix wants a specification comparison (or a re-reference) at
  `applySessionCalibration`, and the record's frame carried on save. Owner:
  unclaimed — trust-fixes family, predates S10.
- **Cross-frame recipe export refuses rather than composing (S10 decision;
  the composition is this item).** `AppState.exportableRecipe` carries a
  recipe only when its recorded frame EQUALS the live view's — a promoted
  or reconfigure-restored session's recipe is refused with the reason in
  the export status line. Mapping it honestly is a three-frame composition
  (recorded → source → exported) needing the source→view forward transform
  `ReplayFrameTransform` deliberately does not have. Related, same owner:
  `mac4dstem_replay_record` on an exported cube's `datacube_root` carries
  no version or frame marker — inert while nothing reads it there,
  load-bearing the day an "adopt recipe from an exported cube" feature
  lands. Owner: whichever session builds that feature.

- ~~A save after a FAILED crop restore erases the sidecar's crop and
  mislabels its preserved results~~ — **Closed by S7, 2026-08-25**
  (`SessionGates` blocks all three rewrite entry points by name); record in
  [the closed-items archive](archive/closed-items-2026-08.md). Track B rows F1.26/F1.27.
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
  not a nit. **Not taken by S18 (2026-08-27):** it is not on the S18 brief's
  list, and that brief is explicitly bounded to the list. It also cannot be
  confirmed fixed without driving the sheet, so it wants a session that ends
  in an owner pass. Still open, owner unassigned.
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
- **#17a — aspect-aware pane arrangement.** Built, then reverted on sight
  2026-08-05. Needs a design decision, not an implementation.
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
  **Landed by S18, 2026-08-27; the Gate B second read is still owed** (see the
  caveat at the top of this file). When resident, `FourDArray.scanTile` copied
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
  S18, 2026-08-27; the Gate B second read is still owed.** It always read
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

## Code hygiene

- **`tools/free-space.sh` duplicates producer-side path knowledge it cannot
  see change (M1 Gate A finding, 2026-08-26).** The `mac4dstem-unit-tests.`
  temp prefix is spelled by the producer (`tools/run-tests.sh:37` mktemp)
  and twice by the reaper (`free-space.sh` guard + glob) with no shared
  constant — the 2026-08-17 spelled-three-ways class: rename the template
  and the reaper silently reports "nothing to clear". Same shape, same
  entry: the XcodeBuildMCP workspace root is hardcoded (a relocation is
  caught only by the printed missing-root note); the script reports
  `df -g /` while `require_free_space` gates on `$ROOT` and `$TMPDIR`'s
  volumes, which can differ on a non-boot checkout; and ~35 harness
  `run.sh` files use bare untagged `mktemp -d`, invisible to any reaper.
  Fix wants one `tools/lib/` constants file sourced by both sides. Owner:
  whichever session next touches `run-tests.sh`, or S18.

- ~~Eight standing build-warning classes~~ — **all cleared by the S3 rider,
  2026-08-19** (a fresh clean `build_macos` reports zero warnings); record
  in [the closed-items archive](archive/closed-items-2026-08.md). The lesson stands: warm incremental builds re-emit nothing —
  only a clean build can verify a warning claim either way.
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
