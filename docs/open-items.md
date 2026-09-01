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

> **Entry format, standing rule — adopted 2026-08-28 after this file reached
> 1,683 lines and the three-file kickoff tax hit 2,548.** An entry here is a
> **finding**, not the story of finding it. Keep: what is wrong (or was), the
> evidence that pins it, the trap a future reader would fall into, the owning
> session, and any live residual. Move to the dated archive: refuted
> hypotheses, superseded observation rounds, and the narrative of how the
> diagnosis converged — with a one-line pointer left behind, because the
> `diagnose` skill is right that refuted accounts have value; they just do not
> need to be read by every session. **Target ≤ 20 lines per entry.** An entry
> that outgrows it is usually a session record wearing the wrong hat — the
> record belongs in `docs/archive/v2-session-records/`.
>
> The cost this rule exists to stop is real and recurring: every session reads
> these three files before doing any work, so a line added here is paid by all
> of them. M1 cut the tax to 1,901 on 2026-08-26; it was back to 2,548 two days
> later, and the growth was narrative, not findings.

Closed items are not here — the v1.0-era record is
[`docs/archive/v1.0/ui-workflow-backlog.md`](archive/v1.0/ui-workflow-backlog.md);
v2-era closures move verbatim to
[`docs/archive/closed-items-2026-08.md`](archive/closed-items-2026-08.md)
(dated siblings follow as months pass), leaving a one-line tombstone here
only where something live leans on them. Cited numbers are prefixed `#` and
refer to the v1.0 backlog.

## Owner decisions — 2026-09-01 (v2 endgame scope)

Taken in conversation with the release owner; they resolve
[`docs/v2-ship-plan.md`](v2-ship-plan.md) Step 0 and sequence the endgame:

1. **All five remaining Group A items ship FIXED** (WS₂ shell selection, the
   provenance leak `app-appstate-01`+`support-export-01`, the hexagonal IPF
   legend, the invented/mislabelled units, ~~the readiness-row truncation~~ —
   **truncation CLOSED by S22d, 2026-09-01**, on-screen wrap verified; see
   `docs/s22-ux-design.md` §6), plus the ride-alongs (~~ui-07~~ — **closed by
   S22b** — and Group D's five green-but-worthless tests).
2. **The §1 claims "hand a colleague the recipe" and "promote overnight" are
   DISCARDED from v2** — S19 restates them. The clean-account run stays
   (owner, local second account); the colleague/second-machine test dies
   with the claim. **The bounded ~30-min promote run STAYS** — the replay
   feature ships regardless, and the run closes F1.14/F1.15/F1.19/F1.22/
   F1.23; the owner drives it after the fixes land.
3. **Group B splits: the CIF pair (`core-crystal-02`, `core-crystal-04`)
   joins v2** — one session, one fixture, seeded by
   `References/training_dataset/WS2.cif` (verified to carry explicit
   symmetry ops; the negative control is the same file with the ops loop
   stripped, which must be *refused*, exactly the case py4DSTEM survives
   because pymatgen derives the ops from the space group). The remaining
   trio (sidecar string reads, restore shape check, DM4 trap) goes to v2.x
   as documented limitations.
4. **The probe-radius defect joins Step 1 as item 7** (Gate D first — the
   recorded mean-DP/vacuum discriminator — then Gate B; covers the SPED_MgO
   observation and the 2.15× demo over-measurement). Manual radius entry
   only AFTER the estimator is fixed or qualified, stamped `.manual`.
5. ~~**Two owner-promoted UI changes ride v2**~~ — **DONE 2026-09-01; F1.50
   and F1.51 queued.** The redundant scan-position X/Y sliders are removed;
   click/drag, marker-handle and keyboard navigation remain, with exact X/Y in
   the inspector; the marker also restores native accessibility adjustment and
   named four-direction actions. DP and Result colormaps now occupy one
   permanent adaptive row; the first three-row version made Map overflow
   (caught by the existing layout gate), so log scale and Q units moved into
   its options menu. Gate A then caught a 513pt intrinsic-width first pass; the
   final minimum-width DP/Result/options fallback measures 193pt in ~218pt of
   row content.
6. **Working split, standing:** the assistant plans and implements;
   Haiku/Sonnet subagents do exploration and mechanical fan-out; every
   Gate B/D review gets an independent subagent refuter, requested from the
   owner explicitly each time.
7. **S22 pulled forward — decided 2026-09-01 evening, overturning the ship
   plan's "No S22".** The owner's playthrough verdict ("this is not a good
   v2") blocks his own testing: **the UI-pair work is HELD uncommitted and
   the owner's Track B sittings are PAUSED until S22's fixes land** — he
   will do one final playthrough + report after. **The design phase RAN the
   same evening** — [`docs/s22-ux-design.md`](s22-ux-design.md) is the
   single S22 thread (evidence, design, slice plan, status; owner approval
   pending, blocks all S22 code) — then S22 implementation slices, then the
   provenance leak and remaining Group A. Bullseye disk detection stays a SEPARATE Gate D
   science session, not S22.
8. **Token conservation, standing directive:** route work to lower-tier
   models when possible and safe — Haiku for exploration/mechanical
   fan-out, Sonnet for bounded well-specified implementation, the default
   model only where judgement or science is at stake. Keep doc updates
   terse (the ≤20-line findings rule); no further whole-codebase
   meta-passes; design on paper before SwiftUI rework. The science gates
   stay — they caught three wrong fixes — but their heavy form is reserved
   for science-affecting changes; UI slices take light Gate A. The
   structural rethink for the future is
   [`docs/v3-development-process.md`](v3-development-process.md).

Sequence agreed: docs tidy (ran 2026-09-01) → CIF pair (**DONE 2026-09-01 —
Gate B ran, verdict stand-with-corrections, all four corrections applied;
[record](archive/v2-session-records/cif-pair.md)**) → probe-radius
(**DONE 2026-09-01 — Gate D confirmed, fixed, Gate B stand-with-corrections
all applied** — [record](archive/v2-session-records/probe-radius.md)) →
UI pair (**DONE 2026-09-01, held uncommitted — decision 7**) →
**S22 design phase (NEXT)** → S22 implementation slices → provenance leak →
remaining Group A → owner runs (clean account, bounded promote) → the owner's
final playthrough (Track B finish) → S20. The 036 view-vs-full
performance A/B stays queued as its own sitting (parameter matrix if the
owner's exact load spec stays unknown).

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
- ~~`measureOrigin` frame-dependence and single-refinement → weighed in
  **S12**; **#29** → **S12** reads the campaign data that settles it.~~
  **Both done 2026-08-28.** #29 is **answered** and the coarse step is
  recommended **OUT** of S13 on a measurement — the design, the numbers and
  what S13 should build are
  [`docs/q-calibration-design.md`](q-calibration-design.md). Entries below
  carry the outcomes; S13 inherits the implementation.
- **#11** WS₂ → **S14–S16**.
- ~~`SidebarLayoutTests` intermittent → **S17** (Gate D).~~ **Diagnosed and
  formally quarantined 2026-08-27**; two owner-visible rows remain in Track B.
- Colorbar/scale-bar collision, **#38**, the scan-extent two-orders question,
  the comparison-panel `contentVersion`, `pattern(ry:rx:)` ignoring the
  resident cube, **#37** re-measure → **S18, all landed 2026-08-27**; each
  entry below carries its own outcome. **Two things S18 could NOT finish and
  did not pretend to.** (1) ~~The Gate B second read of the two `Core/`
  changes~~ — **RAN 2026-08-28, and both changes SURVIVED**; outcome recorded
  below. (2) The `mac4DSTEMUITests` deletion below was refused by the
  environment, not declined — **still outstanding, needs the release owner.**
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
  was accurate. **S17 settled the test locally on 2026-08-27** (the persisted
  disclosure state isolated; uncalibrated Prepare explicitly skipped with diagnostics),
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

- ~~**`README.md` and `CHANGELOG.md` claim `tools/run-tests.sh all` — exit 0, 30
  harnesses**~~ — **CLOSED by S19, 2026-08-28.** `all` was run end to end on the
  current tree: **exit 0, 40 harnesses, zero FAIL lines, zero exit-69 refusals,
  unit stage 387 passed / 4 skipped / 0 failed** — counted by grep over the
  retained log, not inferred from the exit code. `README.md` now states that
  reproducible figure and points at the Track B checklist for what the numerical
  gate does not cover; `CHANGELOG.md` keeps v1.0.0's 30-harness numbers as the
  record of what THAT release was verified by, with a pointer to the current
  ones. The single SKIP is `real-data-acceptance` correctly refusing to read a
  session sidecar as a datacube (#43). The two years of historical detail this entry accumulated — the 2026-08-18
  measurements, the component table, the S17 update — are **moved verbatim** to
  [the closed-items archive](archive/closed-items-2026-08.md#the-stale-run-testssh-all-claim--closed-2026-08-28).

### Owner playthrough — 2026-09-01 second sitting (S22's evidence starts arriving)

The owner drove the current Xcode build (the uncommitted UI-pair tree)
~15:56–16:10 across `calibrationData_bullseyeProbe.h5`, `NP_data.h5`,
`twisted_bilayer_graphene.hdf5` and `COPL_Ni65Cu35_…bin_4_20240912.h5`, and
sent seven screenshots. Nothing under `mac4DSTEM/` changed — eval-only. The
overall verdict, in the owner's words: **"this is not a good v2"** — the
workflow reads worse than v1's, and UI polish is harder than presumed. That
judgement is the exact input S22's stub says it cannot start without.
Findings:

1. **Bullseye disc detection judged unacceptable — SCIENCE, Gate D owed, own
   session.** Map ▸ Bragg disks on `calibrationData_bullseyeProbe.h5`
   (100×84 scan, 250×250 detector), synthetic kernel r = 6.8 px, correlation
   power 1.00, parabolic subpixel, funnel `absolute 187 · relative 72 ·
   spacing 68`: accepted circles sit across noise regions far from any disk.
   Two recorded neighbours are NOT this item: the permissive acceptance
   thresholds (F1.49's trap) and owner decision #4's estimator repair. The
   bullseye-specific question — what kernel a ringed probe needs, and what
   py4DSTEM does for the same data — is for the Gate D session to establish,
   not this note (review the diagnosis, not the code).
2. **The DPC & iDPC task pane offers no task** — S22. What selecting the task
   shows (`mac4DSTEM/UI/ContentView.swift:267-330`) is one Display picker plus
   read-only rows, refusal text and tips; on an uncalibrated cube that is
   orange text with nothing actionable. Owner: "just useless."
3. **A colormap change takes three interactions through a redundant submenu.**
   `colormapMenu` wraps its Picker in a Menu
   (`mac4DSTEM/UI/ContentView.swift:1185-1190`), which macOS renders as a
   single "DP colormap ▸" parent item duplicating the button's own label —
   confirmed by the owner's screenshots. The flat idiom is already in-tree:
   the orientation control's `.pickerStyle(.inline)`
   (`mac4DSTEM/UI/StemImageView.swift:221`). Scored into F1.51 (PARTLY).
   Candidate ride-along for the first S22 slice.
4. **Sidebar text truncates, and the workaround clips the sidebar itself.**
   To read calibration/readiness detail the owner must drag the sidebar far
   right; on `COPL…` in Prepare the wide sidebar then clips its own labels off
   the LEFT window edge while the detail column crushes — the first captured
   reproduction of the 2026-08-05 "content clipped off both edges" report,
   which could never be reproduced headlessly
   (`docs/archive/v1.0/ui-design-pass-2026-08-05.md` §1.7; the soft floor at
   `mac4DSTEM/UI/ContentView.swift:966-980` was slack, not a fix, and says so).
   The truncation half re-confirms the first sitting's Group A readiness-row
   finding. Owner asks for wrapping instead of width.
5. **The View-orientation flyout is disproportionate** — five items rendered
   into a panel covering roughly a quarter of the window
   (`mac4DSTEM/UI/StemImageView.swift:213-235`; the single-line footer Text at
   `:225` is the plausible width-setter, unconfirmed). Seen on `COPL…`'s ACOM
   full-scan pane.
6. **The inspector cannot be resized and its preview is fixed-small** — S22,
   structural. The right panel is not a split column: `DatasetInspector` is an
   HStack member with `.frame(minWidth: 220, idealWidth: 300, maxWidth: 340)`
   and no draggable divider (`mac4DSTEM/UI/ContentView.swift:985-991`);
   preview thumbnails (`mac4DSTEM/UI/DatasetInspector.swift:34-48`) scale with
   nothing. The owner wants the right panel resizable like the left, the
   preview following it, and the histograms adapting. The system-standard
   shape — macOS 14's `.inspector`/`inspectorColumnWidth`, or a real split
   column — is S22's first design question.
7. **iOS-port question, answered 2026-09-01:** the owner asked whether porting
   to iOS would let the assistant iterate in the iOS simulator. Refused as a
   polish route: the motivating loop — the assistant building, launching,
   driving and screenshotting the UI — already works on macOS (F1.32/F1.34
   found real defects that way; F1.3c closed by CGEvent drags), and a port
   forks the windowing/file/NAS/Metal surface v2 depends on. The real question
   inside it — are there standard macOS patterns being ignored — is answered
   YES and folded into S22's design doc (item 6, plus Form/`LabeledContent`
   wrapping versus the hand-rolled HStacks behind items 4 and 5).

**Sequencing DECIDED the same evening — owner decisions 7 and 8 above:**
S22's design phase runs next, the UI-pair work is held uncommitted, and the
owner's Track B sittings pause until S22's fixes land; one final owner
playthrough after. A standing token-conservation directive landed with it.

### Track B playthrough — 2026-09-01 (full record archived)

Two sittings: the interrupted review's recovery, then a joint Track B drive
(assistant driving, owner steering) across `downsample_Si_SiGe_exp`,
`Particle_1`, `polycrystal_2D_WS2` and `sim_Au`. **Nothing under `mac4DSTEM/`
changed — every item below is eval-only.** Full narrative, including the
hypotheses that were refuted and the two I retracted:
[`docs/archive/2026-09-01-trackb-playthrough.md`](archive/2026-09-01-trackb-playthrough.md).

**Rows: 31 passed / 7 partly / 15 unverified / 1 blocked.** Moved this session —
F1.28, F1.33(a), F1.39, F1.40, F1.41, F1.44 passed; F1.38 and F1.45 advanced;
F1.26 unblocked. **Done criterion 8 met on screen** (`polycrystal_2D_WS2` reached
ACOM: `ACOM full ✓ … Physical · measured in app · 16.384 positions · 5.6 s`).
**F1.28 also confirmed S8's live-derivation contract**, unverified since S8.

**Live findings, by owner:**

- **Restored provenance reaches a fresh product's trust badge — `app-appstate-01`
  REPRODUCED AT RUNTIME.** Controlled A/B, same cube, one variable: with a session
  restored `Virtual detector · Annulus` badges **Quantitative**; from a fresh path
  with nothing restored, **Relative** (correct — units are `intensity`,
  `App/AppState.swift:745-748`). **Group A.** Not established: the export half, and
  whether any *number* is affected. Gate D part-satisfied.
- **Readiness rows truncate mid-sentence, cutting the caveat.** `(27% excluded
  as…` and `File metadata takes precedence — check…` — the actionable half is
  what is lost, at any sidebar width tried. **Recommend Group A**: it defeats
  disclosures that are already implemented and correct.
- **The reference-shell defect is isolated, with a control.** Same code path:
  Gold FCC `shell ratio 1.148 vs 1.155 predicted` (0.6%, and 2/√3 = 1.1547 is
  exactly right); WS₂ basal `1.633 vs 2.000` (18.4%). The estimator is sound; the
  **WS₂ shell selection** is what is wrong. Owner: whoever takes the reference-shell item.
- **`ui-07` confirmed on screen** — the Performance inspector still reads *"GPU
  budget 5461 MB"* where the configurator reads *"GPU working-set limit"*
  (F1.39, same day). One word; the cheap pull-forward in the triage.
- **S22 leads, observed not inferred:** the empty result pane gives
  virtual-detector instructions under every pending result kind
  (`UI/StemImageView.swift:633-645`); the welcome screen's entry points open
  **below the fold** and ⌘N is the only route back to *Open with Options…*; the
  sidebar divider restores at a **measured 144.0 pt** against a declared
  `min: 250`, degrading the Calibration section to *"Ori… Missing"*.
- **Row defects fixed in the checklist:** F1.42 named a menu item that does not
  exist; F1.8 described an unreachable state; F1.40 can only pass on
  `Particle_1`; F1.41 needs Bragg vectors first; **F1.45's "IPF·Z is nearly
  uniform" expectation is wrong** — the map is strongly grained (owner's eye).
- **F1.46 written** — Done criterion 4 had no numbered row. Its Gate D **refuted**
  the fear that the only grant route overwrites the colleague's sidecar: saves are
  refused while the restore fails (`App/AppState.swift:1490` →
  `App/SessionGates.swift:179`), and choosing the same file is an identity-matched
  no-op. What survives: the first remedy the app prints is one it then refuses.
- **F1.47 queued 2026-09-01** — the DPC angle repair changes the scalar
  colourbar/export numbers from normalized turns to radians while normalized
  colours may remain identical. Owner drive still owes the current-build
  on-screen and PNG carrier check; the numerical contract is pinned by Track A.
- **Method trap:** renaming a sidecar does **not** withhold it — the bookmark
  tracks the inode. Use a different source path. Driving mechanics are now in
  [`.claude/skills/track-b/DRIVING.md`](../.claude/skills/track-b/DRIVING.md).

**Triage of the 39 confirmed review findings:**
[`docs/v2-triage-2026-09-01.md`](v2-triage-2026-09-01.md) — Groups A+B (+D) are
the v2 case, ~5–7 sessions; C/E/F are v2.x. **Owner decision, not scheduled.**

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

**The four leads were triaged by S11 on 2026-08-28** — verdicts here, evidence
in the entries they point to. Read against the tree at `b15ac0b`.

| Lead | Verdict |
|---|---|
| The file/session mean origin not reaching the estimator | **CONFIRMED, and it is the worst of the four** — it silently substitutes the detector's geometric middle for the file's recorded beam centre in Q calibration, strain, ACOM and the Bragg map. Entry below, owner **S13** |
| The Q estimator differing from py4DSTEM's fit | **CONFIRMED as a structural difference** — one unindexed shell vs a multi-shell indexed least squares. Entry below, owner **S12**, which already owns the design |
| ACOM omitting `power_radial=1.0` | **CONFIRMED absent**, and it was already recorded as un-ported in `docs/py4dstem-pipelines.md` §10.1. Materiality still untested; the experiment that settles it is named in the entry below. Owner **S16** |
| HDF5 assuming `[Ry,Rx,Qy,Qx]` / auto-selecting `/data` | **PARTLY DISMISSED** — the assumption is real and unchecked, but the check the lead implies would only catch the case that is already obvious on screen, and the app does name the dataset it chose. Entry below, no owning session |

The fifth S11 item, the **bounds-convention sweep**, is **DISMISSED** — the
finding is that this repo already did the work. Continuous positions have two
named owners: `UI/RealSpacePointerPolicy` maps a scan *index* to
`(i + 0.5)/N` of the box and picks back with a floor, so each pixel owns its
own area; `UI/PeakOverlayGeometry` maps a *continuous* detector coordinate the
same way, which is the correct reading of the index-names-the-centre
convention the mask kernels use (`dx = float(x) - centerX`). Each carries the
defect that created it (the aperture drawn at the pixel's corner, 2026-08-05). `CalibrationReReference.binnedCoordinate` is
`(x + 0.5)/b - 0.5`, documented, and matches the actual bin blocking in
`LoadSpecification.binned` (`[j*b, j*b+b)`, remainder off the end, py4DSTEM's
rule). The annulus mask's `r² > rIn² && r² < rOut²` is py4DSTEM's predicate
character-for-character (`datacube/virtualimage.py:649-651`). The one residual
is `Shaders/OriginMeasure.metal`, which seeds `coarseX = qx * 0.5` at line 44
but sets the winning block's centre as `0.5*(bx + xEnd - 1)` at line 60 — two
conventions half a pixel apart in one kernel. The seed is unreachable in
practice (any block sum beats `-FLT_MAX`) and only seeds a CoM refine, so this
is a tidy-up, not a defect; S12 is already re-weighing that coarse step.
**S12, 2026-08-28: confirmed cosmetic and handed to S13** — **DONE 2026-08-28**,
`coarseX/Y` now seed at `0.5*(qx-1)`, the same pixel-centre convention the
winner uses, with the reachability stated in the comment. Original note:
as a one-line fix,
since S13 is editing that file's neighbourhood anyway. The seed is reachable
only when no block sum beats `-FLT_MAX` — an all-NaN pattern, where the CoM
produces garbage regardless — so it is a readability fix and must not be
written up as a defect.

**That review's own errors and its stale v1 framing** — the MLX claim, the App
Store assumption, the mid-L2 resident-cube findings, the file paths that do not
exist here — are recorded verbatim in
[the closed-items archive](archive/closed-items-2026-08.md#the-external-reviews-own-errors--do-not-import),
moved there by S11 on 2026-08-28 now that every live lead it raised is triaged.
**Read them before importing anything else from that document**; its line
citations cannot be trusted without checking.

## Known, scoped, not blocking

- **CIF import: a non-P1 declaration with a PARTIAL ops list still imports a
  wrong crystal silently** — Gate B refuter escape E2, 2026-09-01, recorded
  not fixed. E.g. Fm-3m declared with only identity + inversion imports the
  2-site CsCl-shaped cell; `verifyFamily` can pass it. Detecting an
  incomplete list needs the declared group's order — space-group tables the
  importer deliberately lacks (see the DEVIATION in
  `Core/Crystal/CIFImport.swift`). Cheap partial mitigation if ever wanted:
  an IT-number → group-order table (230 integers), new scope. The
  missing/identity-only case is guarded and gated
  ([record](archive/v2-session-records/cif-pair.md)).

- ~~**Disk-detection radius looks ~3x too large on a strongly-diffracting
  dataset (`SPED_MgO.hdf5`)**~~ — owner observation 2026-08-28; **DIAGNOSED
  AND FIXED 2026-09-01**
  ([record](archive/v2-session-records/probe-radius.md)). Gate D on the real
  cube confirmed the recorded hypothesis exactly: the shipped 14.1 px IS
  `probeSize(maxDP)` (reproduced to the digit), the mean gives 5.4,
  substrate-only patterns ~3 — and within one file, nested sub-scans read
  16.07 → 16.50 → 19.07 px as the scan grows, the max-union's causal
  signature (a per-pattern property cannot grow with scan area; Gate B's
  like-for-like version, replacing the dtype-confounded cross-file pair).
  Both `OriginCalibration` call sites now feed
  **meanDP** (DEVIATION noted: py4DSTEM's own origin path feeds the max,
  against its own docstring). **Still live from the original observation:**
  (1) the permissive acceptance thresholds (`Minimum absolute 0 CC`,
  `relative 0.5%`) admit noise peaks regardless of kernel size — separate
  factor, untouched by this fix; (2) the kernel label **"Measured ROI ·
  N px" implies a provenance the number does not have**
  (`ProbeKernel.measured` takes the radius as a parameter); (3) manual
  radius entry stamped `.manual` is unblocked by the owner's fix-first
  ruling, not yet built. Track B row queued for the on-screen radius
  surfaces.

- ~~**A file's mean origin never reaches the analyses that claim to use it**~~
  — found by S11, **CLOSED by S13, 2026-08-28.** The recorded beam centre now
  has a home of its own (`Calibration.recordedOriginX/Y`, written at both the
  `.fileMean` and `.sessionMean` sites and carried into the export snapshot),
  and there is **one** derivation of which origin an analysis re-centres on:
  `Calibration.referenceOrigin(detectorQX:detectorQY:apertureCentre:)`, which
  returns the value *and its kind* (`fittedMaps` / `recordedMean` /
  `apertureCentre` / `geometricMiddle`). The four divergent call sites S11
  catalogued all ask it. Q calibration refuses a kind that is not a measured
  beam centre, through the new `SessionGates.reciprocalMetrologyRefusal`.
  **Closed structurally rather than watched for, and S13 E1 measured why that
  was the only option:** the geometric-middle substitution is **1.14 px on
  `sim_Au`** — below the estimator's 2 px floor, invisible to every check — and
  **7.07 px on `downsample_Si_SiGe_exp`** — above the band the radius check
  covers. No plausibility check straddles that range. **S11's blind spot is
  closed too:** `QCalibrationOriginGateTests` now nulls the origin explicitly to
  reach the nil branch (the demo's disk detection calibrates one, so the branch
  had never run), and three mutations were applied to confirm the new cases go
  red. The original S11 entry is moved verbatim to
  [the closed-items archive](archive/closed-items-2026-08.md) (2026-09-01 tidy).

- ~~**The Q estimator is a single unindexed shell where py4DSTEM fits many**~~
  — S11, designed by S12, **IMPLEMENTED by S13, 2026-08-28, with the design
  corrected against measurement.** `KnownCrystalQCalibration.estimate` now
  collects a second shell and compares median(r₂)/median(r₁) against g₂/g₁,
  reporting `.agreed` / `.disagreed` / `.notSelfChecked` — the third state
  surfaced rather than folded into a pass. **S12's §3.2 as written was refuted
  by S13's pre-registered experiment**: `Crystal.reflections` returns every
  symmetry equivalent separately at the same |g|, so the second-smallest radius
  at a position is usually another equivalent of the FIRST shell. Measured on
  healthy `sim_Au`, the design's formulation reads **1.02048** against an
  expected 1.15470 and would fire on good data. The repair is one added
  condition whose size is derived rather than chosen — r₂ must exceed r₁ by
  `(g₂/g₁ − 1)/2` — at which `sim_Au` agrees to **−0.57%** with 99.7% coverage
  and `Si_SiGe` misses by **+18.2%**. Threshold ±3%, the geometric centre of
  that gap; **the sound side is one dataset and this is the thinnest of the
  three thresholds.** Stated asymmetry, in the code: because r₂ is *selected*
  as separated, a ratio that is too small cannot be detected — only the
  direction the check exists for. Full numbers:
  [`docs/archive/v2-session-records/s13.md`](archive/v2-session-records/s13.md)
  §1. The original entry follows.
  **The Q estimator is a single unindexed shell where py4DSTEM fits many —
  S11, 2026-08-28. Designed by S12, 2026-08-28.**
  `KnownCrystalQCalibration.estimate` takes the *innermost* non-central peak
  at each scan position, medians them, and divides one reference radius by
  the result (`QCalibration.swift:19-51`). py4DSTEM's
  `get_dq_from_indexed_peaks` (`process/calibration/qpixelsize.py:26-65`)
  least-squares-fits `q ≈ c·sqrt(h²+k²+l²)` across **indexed** shells. The
  reference side is sound — `Crystal.reflections` applies structure-factor
  extinction and sorts ascending, so `.first` is genuinely the first *allowed*
  shell (`Crystal.swift:131,139`). The unverified assumption is on the
  observation side: that the innermost *detected* peak is that same shell. If
  the first shell is too weak to detect in a given zone, the second is read as
  the first and the scale is wrong by the shell ratio — √4/√3 = 1.155 for FCC,
  a 15% error, silently stamped `.measuredInApp`. Multi-shell fitting is
  self-checking about this; single-shell cannot be. Compounds the known
  `minimumRadiusPixels = 2` limit already recorded against #46.
  S12's answer is a **shell-ratio self-check inside the estimator** — collect the
  innermost *two* radii per position and compare median(r₂)/median(r₁) against
  g₂/g₁ from `Crystal.reflections` — rather than porting py4DSTEM's indexed
  least squares wholesale, which would need indexing the app does not do at this
  stage. Its stated limit: when only one shell is detectable the check cannot
  run and must report *not self-checked*, never silently pass.
  [`docs/q-calibration-design.md`](q-calibration-design.md) §3.2.

- ~~**The origin-fit refusal leads with three remedies that cannot work and
  buries the one that can**~~ — S12, **FIXED by S13, 2026-08-28.**
  `Calibration.originFitRefusal` now names which failure it is — broad
  measurement failure ("trimming outliers changed nothing, so the origin
  measurement is failing across the whole scan") versus outlier contamination
  ("the robust fit excluded N% of positions as outliers and the rest still do
  not agree") — leads with manual entry, and demotes the fit functions with the
  reason they cannot help. Pinned by `tools/q-calibration-gate-test`, which
  asserts the *position* of "manually" is before "Constant / Plane / Parabola";
  the mutation that restores the old order goes red on exactly that assertion.
  The original entry follows.
  **The origin-fit refusal leads with three remedies that cannot work and
  buries the one that can — S12, 2026-08-28.** `Calibration.originFitRefusal`
  (`Core/Data/Calibration.swift:506-511`) appends *"Try another Origin fit
  (Constant / Plane / Parabola) and re-run Calibrate Origin, or enter the scale
  manually."* On **both** training datasets where that text is shown, all three
  fit functions miss the gate — `downsample_Si_SiGe_exp` 13.133 / 11.655 /
  11.302 px against a 5.026 px gate (2.2× at best), `Particle_1…bin8` 18.720 /
  18.295 / 18.138 against 10.624 (1.7× at best). **The fourth remedy DOES
  work** — manual entry bypasses the estimator and the field is rendered in
  both branches, which is why `AppState.swift:4951` says refusing "is never a
  dead end" (a Gate B decision, 2026-08-25). *S12's first draft of this entry
  said the refusal was a dead end; it quoted the string truncated before the
  manual-entry clause, and a refuter caught it.* The live defect is that the
  text spends its words on the three that cannot succeed: it should name what
  actually failed — broad measurement failure versus excluded outliers, which
  the app can now tell apart — and lead with manual entry. Numbers from
  `tools/training-dataset-campaign` (`origin_calibration` stage).

- ~~**The plane origin fit is not robust, so a contaminated scan gets a
  DISPLACED origin and the residual reports the contamination instead**~~ —
  S12, **FIXED by S13, 2026-08-28, and both halves landed together as S12
  insisted they must.** `OriginCalibration.fitOriginTrimmed` (three rounds at
  median + 3·1.4826·MAD, the constants S12 measured with) is now what both
  `tiledRun` and `run` call, marked `DEVIATION` from py4DSTEM's `fit_origin`
  with its reason; `OriginMaps` carries `excludedFraction` and `robustResidual`;
  and the gate — renamed `originFitIsSane` — reads the **robust** residual,
  which is the half without which the fit change would have altered nothing the
  user sees. The excluded fraction is carried **on the product** per the owner's
  §6(a) decision: the calibration panel, the readiness detail, the displayed-
  result metadata record, the publication caption, and the strain and
  orientation bundles' provenance (`origin_fit_excluded_fraction`,
  `origin_fit_positions_used_fraction`, `origin_reference`).
  **§6(b) — the hard ceiling — is ANSWERED and the answer is "none defensible".**
  S13 E2 measured the fitted origin's own uncertainty across a trim sweep and
  then across *forced* kept fractions on five datasets: at **2% kept** it is
  still **0.10 px**, two orders of magnitude below the pre-registered 2 px
  criterion. Recommendation: ship without a ceiling, refuse on the robust
  residual, report the fraction — the branch §6(b) permits. **The owner can
  overrule this**, and the limitation is stated: bootstrap SD measures the
  fit's precision, not its bias, so a ceiling justified by *representativeness*
  is neither supported nor refuted. Numbers in
  [`docs/archive/v2-session-records/s13.md`](archive/v2-session-records/s13.md)
  §2. The original entry follows.
  **The plane origin fit is not robust, so a contaminated scan gets a DISPLACED
  origin and the residual reports the contamination instead — S12, 2026-08-28.**
  This is the actionable half of **#29's answer** (below). On
  `Particle_1…bin8` a quarter of scan positions fail origin measurement
  (median/RMS residual ratio **0.183**, p50 3.35 px but p95 47.93 px), and the
  unweighted least-squares plane is dragged by them: the shipped fit differs
  from an iteratively-trimmed one by p50 **2.03 px**, p95 4.64 px, **max 6.00
  px** across the scan. #29's own item 1 puts the Q estimator's breakdown at
  ≈2 px, so the app today computes an origin up to 6 px wrong **and refuses it
  on a statistic that describes the contamination rather than the
  displacement**. **Two changes are needed, not one** — a robust fit alone does
  NOT clear the shipped gate: `originFitIsQuantitative` thresholds a *full-scan*
  RMS, and the trimmed fit's full-scan RMS is **18.475 px**, marginally worse
  than the shipped 18.295, a direction forced by full-scan OLS minimizing
  exactly that quantity. The 2.19 px figure is over the 72.7% of positions
  trimming kept, which is not what the gate reads. *S12's first draft claimed
  the trimmed fit "clears the same gate"; a refuter measured the full-scan
  number and refuted it.* So the fit must become robust **and** the gate must
  read a robust residual plus the outlier fraction (§2 of the design); either
  alone changes nothing.
  Measured by `tools/origin-fit-diagnostics/run.sh residuals`; design and the
  gate split in [`docs/q-calibration-design.md`](q-calibration-design.md)
  §1–§2. **Owner decision, 2026-08-28: ADMIT the trimmed calibration and carry
  the excluded fraction on the product** — accuracy of the fitted origin
  outranks coverage of the input measurements, and the fraction is disclosure.
  A hard ceiling on that fraction is **still open**; S13 measures where one
  would go rather than inventing it (§6). **Blind spot to close with it:** S11 recorded that every
  `QCalibrationOriginGateTests` case builds origin *maps*, so the nil branch has
  never run; a test that exercises it is part of the fix and must be broken
  before it is trusted.

- ~~**`AGENTS.md` has been drifting since S17 and now states a claim S19
  refuted**~~ — **found and CLOSED by S12, 2026-08-28.** It was a tracked
  near-copy of `CLAUDE.md`, six sessions stale, still saying `run-tests.sh all`
  "has never been run end to end on this machine" after S19 ran it — and three
  of its four hand-made substitutions were themselves wrong (a `.Codex/skills/`
  directory that does not exist; the pre-move memory path `CLAUDE.md` had
  already corrected). **It is now generated**: `tools/sync-agents-md.sh`
  rewrites it from `CLAUDE.md` with three anchored substitutions, refuses
  rather than half-generating if an anchor moves, and `--check` exits 1 when
  stale. The closeout skill runs it. **Live residual:** nothing enforces it
  mechanically — no CI job or hook runs `--check`, so it relies on the closeout
  step being followed.

- ~~**The strain weighting deviation exists only as a source comment**~~ —
  S11, **FIXED by S13, 2026-08-28.** The strain bundle's provenance now carries
  `strain_weighting = w_r2` and `strain_weighting_py4dstem = w2_r2`
  (`ResultExport.scientificBundleMaps`), so a colleague reading an exported
  strain map can tell which estimator produced it. The original entry follows.
  **The strain weighting deviation exists only as a source comment — S11,
  2026-08-28.**
  `StrainMapping.fitLattice` minimizes `Σ w·r²`; py4DSTEM's
  `fit_lattice_vectors` minimizes `Σ w²·r²` (`StrainMapping.swift:585-592`).
  The note records the magnitude — **~5e-3 median per strain component on
  sim_Au, against ~2e-4 when the estimators are matched**, i.e. ~25× the
  agreement floor and comparable to real strain signals. Nothing carries it
  outward: `strainFrameProvenance` (`ResultExport.swift:397-409`) names the
  frame, and the bundle adds residual and validity (`:446-451`), but
  `grep -rn weighting mac4DSTEM/` returns exactly one hit — the comment. A
  colleague reading an exported strain map cannot tell which estimator
  produced it. One provenance key fixes it; it must not slip past S20.

- ~~**`OriginCalibration.probeSize` counts Bragg disks as probe area, and
  over-measures the probe radius 2.15× on the app's own demo**~~ — found by
  Gate B 2026-08-28; **DIAGNOSED AND FIXED 2026-09-01** together with the
  SPED_MgO observation above, by feeding **meanDP** instead of maxDP at both
  call sites ([record](archive/v2-session-records/probe-radius.md) — the
  full measurement table, the scan-size causal signature, and the
  pre-refuted alternatives: a single low-sum pattern returns a pathological
  31.8 px on Particle_1, so it is NOT a safe input). `probeSize` itself is
  unchanged — the 2.15× was the input, not the formula — and now has its
  first unit coverage (`mac4DSTEMTests/ProbeSizeTests`, incl. the pin that
  `tiledRun` reads the mean); `tools/origin-fit-diagnostics/run.sh
  probe-size` is the standing real-data instrument. **Live residuals:**
  meanDP's own failure modes stay recorded — descan blur (measured: 3.74 px
  vs ~2.4 substrate on Si_SiGe, bounded by real beam wander) and a strong
  amorphous background (unmeasured; no such cube in the corpus). The
  demo-fixture entry below carries downstream numbers (9.649 px, +3.3 px
  kernel shift, 1.62 px origin drag) that predate the fix and shift with the
  honest radius.

- **Which statistic should gate the origin fit is OPEN, and neither candidate is
  right — S13 + Gate B, 2026-08-28. No owner; it needs a design pass, not a
  session.** `originFitIsSane` reads the **full-scan** RMS. S13 changed it to the
  robust (kept-set) residual on S12's argument that a full-scan number describes
  contamination rather than displacement, and Gate B refuted the swap: RMS over
  the set that *defined* the fit cannot see bias, and a partially-excluded
  clustered contamination passes it at 9.94 px while the fit is displaced
  **15.03 px** (32×32 scan, probe radius 10.624, a 12×12 corner thrown +40 px).
  It was reverted. **But the original criticism still stands** — on
  `Particle_1…bin8` the full-scan number is 18.47 px, describing outliers the
  trimmed fit correctly ignored, and the app refuses a calibration whose fitted
  origin is good over 73% of the scan. The gate is on the conservative error,
  not the correct one. What a fix needs and does not have: a statistic that sees
  displacement rather than contamination, which probably means comparing the
  trimmed fit against something other than its own residuals.

- **The trimmed origin fit is blind to spatially clustered failure and to
  contamination at or above 50% — Gate B, 2026-08-28. Recorded, not fixed.**
  Measured: a contiguous quarter of the scan thrown 40 px gives **100.0% kept**
  and a fit **20.6 px** off; 40% of rows gives 100% kept and **42.3 px** off;
  50% scattered gives 0.0% excluded and **30.4 px** off. A third case found
  while building a control: an **exactly bimodal** residual distribution makes
  every majority deviation equal, so the MAD is exactly zero and
  `fitOriginTrimmed`'s zero-MAD guard exits having excluded nothing — that one
  arrives at 33%. In all of them the trim degrades to ordinary least squares
  rather than excluding everything, which is the safe direction, and
  `excludedFraction` reads **0**. The refusal text no longer draws a conclusion
  from that zero (it used to say the whole scan was failing), but nothing
  detects the state. **S13's E2 swept five real datasets and never varied the
  contamination *shape*, so this whole regime is unmeasured on real data.**

- **The ACOM bundle exports no origin provenance — S13 + Gate B, 2026-08-28.
  Owner: whoever next touches `ACOMRunSemantics`.** The strain bundle carries
  `origin_reference` and the excluded fraction, snapshotted when the map is
  computed (`StrainProduct.originProvenance`). ACOM has no equivalent, and
  reading the live calibration at export time is exactly what Gate B found
  wrong — it produced keys describing an origin the product was not computed
  against, and in the reverse case a full set of origin-fit keys on a product
  computed with no origin at all. An absent key is honest; the fix is one
  snapshot field on the run semantics.

- **The demo dataset's rings are a simple-cubic zone drawn on a gold lattice
  constant, and the app's probe radius is over-measured 2.15× on it — FOUND by
  S13, 2026-08-28, CORRECTED by Gate B the same day. NOT FIXED, and the obvious
  remedy is now known to make it WORSE. Owner: an owner call on scope, then
  Gate D (the probe radius) before Gate B (anything else).**
  `DemoFourDDataSource.pattern` draws two spot rings. **Measured from the
  fixture's own pixels:** the inner ring sits at **r = 17.03 px at ±45°/±135°**
  and the outer at **r = 24.50 px on-axis** — so it is exactly what the source
  comment says, *"{110} at 45° and {200} on-axis"*, i.e. a **simple-cubic [001]
  zone**. The comment's only error is the word "FCC". `Crystal.gold.reflections`
  returns **zero** reflections at any permutation of (110), so an FCC model
  cannot see the inner ring at all.
  **The declared 0.02 Å⁻¹/px is honoured**: g₍₂₀₀₎/24.5 px = 0.020017, exact on
  the outer ring to 0.09%. It is ground truth, not a stale label.
  **Magnitude, correctly attributed:** paired with `au_fcc` the fixture error
  alone is **+25%**; the app ships **+13.7%** only because two detector defects
  partly cancel it — see below. It is stamped `.measuredInApp`.
  **Not automatic:** `acomModelSelection` defaults to `.none` and `activate`
  resets it, so nothing under `mac4DSTEM/` selects gold — the user picks a
  phase, and **no library model matches what the demo draws.**
  **THE REMEDY THAT LOOKS OBVIOUS IS WRONG.** Gate B built the repaired fixture
  — gold's {111} at 21.24 px and {200} at 24.52 px at the declared 0.02, every
  other line copied verbatim — and ran it: `shellCheck` **AGREED** (1.142 vs
  1.155, 1.1% out), **no refusal**, and the accepted value is **0.018308, −8.5%
  wrong, stamped `.measuredInApp`.** Repairing the fixture converts a loud
  refusal into a silent wrong number that passes every check S13 added.
  **The real defect is upstream:** `OriginCalibration.probeSize` over-measures
  the probe radius 2.15× on this fixture — the `probeSize` entry above carries
  the mechanism, every measurement, and the Gate D ownership; it, not this
  entry, is where a fix starts. The bias it causes is invisible to every
  estimator check (a constant kernel bias moves the shell ratio by ~1.1%).
  **CURRENT BEHAVIOUR, after the thresholds were cut: the demo does NOT refuse.**
  An earlier version of this entry said it did. That was true for the few hours
  S13 shipped an estimator threshold; Gate B refuted the threshold's derivation
  and it was removed, so the app calibrates the demo to **0.021 Å⁻¹/px** again —
  wrong, as it has always been — and the shell-ratio disagreement is now
  *reported* beside the number ("shell ratio 1.373 vs 1.155 predicted") instead
  of refusing on it. That is strictly better than before S13 and strictly weaker
  than a refusal, and it is the honest position until a threshold can be placed
  on evidence. **Amended 2026-09-01 (probe-radius repair):** with the kernel at
  the kernel at 6.93 px (down from 9.649; still above the drawn 4.5 —
  the demo's rings are in every pattern, so the mean keeps them at reduced
  strength) the demo calibrates to **0.024472 Å⁻¹/px**, first shell
  17.36 px against the fixture's true 17.03 (the +3.3 px kernel-following
  shift collapsed as predicted), shell ratio **1.433 vs 1.155** — the
  disagreement is now larger and more honestly visible. The 9.649 px /
  1.62 px figures earlier in this entry are pre-repair history.
  The four specifics S13 originally claimed and Gate B refuted are in the
  session record, §6 (*Corrected rather than defended*). **One figure there is
  itself stale:** the record says the app reports **1.089** against 1.155, but
  the shipping tree's passing gate
  (`testTheDemoShellsDoNotMatchTheGoldModelItIsPairedWith`) pins the observed
  ratio **above 1.15× the prediction**, which supports the 1.373 quoted above
  and cannot be reconciled with 1.089. Corrected here and noted in the record,
  2026-08-29; F1.42's drive is what confirms the on-screen number.

- **ACOM omits py4DSTEM's `power_radial` — S11 confirmed absent, 2026-08-28.
  Owner: S16.** `orientation_plan` declares `power_radial: float = 1.0`
  (`crystal_ACOM.py:32`) and applies it to the **template** side only
  (`:810`, `:817`; the experimental-image use at `:1116` is commented out).
  `OrientationPlan.buildPolar` deposits `weight` with no radial factor, so
  relative to py4DSTEM the app under-weights outer shells by ~r. It cannot be
  absorbed into `normalizeUnit`, which is a single global scale. Already
  recorded as un-ported in `docs/py4dstem-pipelines.md` §10.1; **still
  untested**, and the apparatus to test it exists — the §10.1/§10.2 sweeps ran
  through `tools/acom-groundtruth`, so a `power_radial` arm is one more column
  in that table. What is missing is the Python driver that built those inputs,
  which was not retained. Note the app also subtracts each ring's mean
  (`OrientationPlan.swift:241-247`) where py4DSTEM leaves that line commented
  out (`crystal_ACOM.py:854`) — a second un-ported difference in the same
  function, and neither carries a `DEVIATION` note, which the hard rule
  requires. **If S11–S16 are severed at the cut line this goes with them**;
  say so deliberately rather than losing it.

- **HDF5 axis order is assumed, not checked — S11, 2026-08-28. No owning
  session: the lead is real but its remedy is weaker than it looks.**
  `H5Reader.describe` returns the file's dims verbatim and `DatasetDescriptor`
  reads them as `[ry, rx, qy, qx]` (`DatasetDescriptor.swift:24-27`); rank 3 is
  padded to `[1, d0, d1, d2]`. The EMD dim-vector fallback hard-codes the same
  order (`H5Reader.swift:642-651`, "dim1 = R, dim3 = Q"). **Why this is not
  promoted to a defect:** the units the app already reads could only refute a
  *scan↔detector* swap, and that case renders as a CBED pane full of scan
  image — obvious in the first second on screen. The cases that would be
  silent are Ry↔Rx or Qy↔Qx transpositions, and dim-vector units cannot
  distinguish those either, because both axes of a pair carry the same units.
  The app does name the dataset it chose (`DatasetInspector.swift:11`,
  `InspectorPanels.swift:76`), so "auto-selects without saying" is **wrong**.
  What remains genuinely unhandled: a file holding several 4D datasets picks
  one by `/data`-suffix, then depth, then alphabetical order
  (`H5Reader.swift:305-312`) with no user choice.

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
  failure triplet was reproduced exactly by the persisted Display-disclosure
  preference. The 2026-09-01 owner-promoted UI pair removed that disclosure,
  its AppStorage state and the measurement that could now only pass vacuously;
  the colormaps are permanent in a one-row Display control instead. The numeric
  gate still covers every calibrated workspace plus every uncalibrated
  workspace except Prepare. Uncalibrated Prepare is an explicit dynamic skip:
  933pt against 871pt on 2026-08-27, because the former 60pt allowance is not a
  product invariant. CI retains and prints its geometry attachment. The old
  expanded-Display Track B row is retired; still live is the default-width
  uncalibrated Prepare row, plus UI-pair rows F1.50/F1.51. The changed workflow
  has not run on GitHub yet. Full diagnosis, observation history and deviations:
  [`docs/archive/v2-session-records/s17.md`](archive/v2-session-records/s17.md).
- ~~The burned-in caption on exported figures truncates~~ — **Closed by S7,
  2026-08-25** (wraps, figure grows, full provenance as PNG metadata);
  record in [the closed-items archive](archive/closed-items-2026-08.md). Track B row F1.24.
- ~~**Colorbar and scale bar collide on tall, narrow maps.**~~ — **Fixed by S18, 2026-08-27**; Track B row **F1.32 PASSED on the original defect configuration** 2026-08-27. Record in [the closed-items archive](archive/closed-items-2026-08.md).
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
- ~~**One remaining `contentVersion` staleness hazard.**~~ — **Fixed by S18, 2026-08-27** (the comparison panel is built once in `init` and its version hashes the payload bytes). Record in [the closed-items archive](archive/closed-items-2026-08.md). **Live residual: Track B row F1.35 has never been driven.**
- ~~**The configurator's two preview panes draw nothing** (the 2026-08-18 entry)~~ — **fully superseded 2026-08-27/28.** Its three threads all closed: the flat-colour normalization defect (fixed 2026-08-18), the panes drawing nothing at all (the `contentsScale == 0` cause, fixed 2026-08-27 — see the tombstone above), and the aspect-stretched previews (#17a decided by the owner on the measurement, letterbox applied and verified on screen). S4's four adjacent items landed 2026-08-24. Record in [the closed-items archive](archive/closed-items-2026-08.md). **Live residual: Track B row F1.19** — the determinate sampling status line on a multi-GB `Open with Options…` — has still never been driven.
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

  **S9a LANDED 2026-08-28 — the tile budget half, and it is NOT a fix for this
  death.** The budget now takes the lesser of the GPU hint and a HOST bound of
  `physicalMemory / 24`, which holds the three-tile peak near 12% of RAM.
  Measured on this machine, which is the 8 GB M3 the death happened on:
  GPU working set 5461 MB (66% of physical), old per-tile **683 MB → 2048 MB
  three-tile peak** — exactly the ~2.0 GB this entry predicted — new per-tile
  **341 MB → 1024 MB**. Si_SiGe goes 54 → 27 rows per tile, sim_Au 136 → 68.
  **Physical, not free, memory is the bound, by owner decision (2026-08-28):**
  tile size sets how float partials are grouped and the tiled reducers are
  order-dependent in their low bits, so sizing from free memory would make the
  numbers depend on what else was running. Free memory is for refusing, never
  for resizing. **The diagnosis is still owed** — this is a guard that would
  have prevented the death, not an account of it.

  **Perf impact is UNMEASURED, and `tools/performance-baseline` cannot measure
  it** (found trying, 2026-08-28): every tiling benchmark there passes an
  explicit `maximumTileRows`, so `tile_rows` reads 4 before and after and the
  default budget is never exercised. A run against the recorded baseline showed
  18–77% regressions across benchmarks that do not touch tiling at all
  (`fft_radix2`, ptychography, ACOM plan generation) — that was 3 repeats
  against the baseline's 5 on a machine busy building, not a real signal, and
  the new numbers were deliberately NOT recorded over the baseline. Whoever
  wants this measured must add a benchmark that uses the default budget.

  **The concrete suspect is not the resident cube — it is `DM4Reader`.**
  `Core/Data/DM4Reader.swift:56` maps with `.mappedIfSafe`, which is a *request,
  not a guarantee*: Foundation declines to map on network or removable volumes
  and **silently falls back to reading the entire file into memory**. The run
  that preceded the death opened a **17.19 GB `055_STEM SI.dm4` from the NAS** —
  a 17 GB anonymous allocation on an 8 GB machine, which is exactly the profile
  of a jetsam kill with no `.ips` and a system-wide stall. It also explains why
  Cancel left the machine wounded: the allocation happens inside `DM4Reader.init`
  before any cancellation token is consulted. **S9b RAN IT, 2026-08-28 (Gate D):**

  **The mechanism is confirmed, and its predicate is `MNT_LOCAL && !MNT_REMOVABLE`
  — not "local vs NAS", which is how this entry framed it.** Measured by
  `getmntinfo` over every mount, 6/6 separation, no exceptions: `/` and
  `/System/Volumes/Data` map; **every externally-attached disk whatever its
  filesystem, every mounted disk image *including one stored on the internal
  SSD*, and smbfs all decline** and silently read the whole file into anonymous
  memory — held for the session, not a transient open spike. Reproducible:
  `tools/volume-mmap-probe/run.sh --mounts` prints the predicate for every mount
  in a millisecond, and `run.sh <file>` measures it. Proven both ways on
  one identical dense 2.44 GB file: `vmmap` shows a real `SM=COW` region and a
  **2.8 MB** footprint on the internal volume, and **no mapped region at all**
  with footprint = 100% of file size on the rest. Note `MNT_REMOVABLE` tracks
  *external attachment*, not removable media (`diskutil` calls that SSD's media
  "Fixed"), so **reformatting an external SSD to APFS is predicted not to help** —
  and that is now a one-millisecond `statfs` check on any volume rather than an
  argument.

  **Three of S9b's own claims were refuted before they landed.** (1) "Internal vs
  external" is the wrong axis — an APFS image *on the internal disk* declines, so
  "keep it on the internal disk" is unsafe as stated. (2) The disk-image arm was
  filed as a confounded control when it was in fact *the* de-confounding one.
  (3) `URL.volumeIsRemovableKey` returns **false** for that SSD while the kernel
  flag says removable — the two answer different questions, and believing the
  Foundation key is what sent the first reading down the wrong road. Anything
  shipped from this must read `statfs`, never the URL key.

  **Scope is much narrower than this entry implied: DM4/DM3 only.**
  `.mappedIfSafe` appears exactly once in the app (`DM4Reader.swift:64`).
  `H5Reader` reads hyperslabs through libhdf5's sec2 driver and
  `VendorRawReaders` uses `FileHandle` seek/read, so HDF5/EMD, MIB and EMPAD are
  immune — **a colleague opening an `.h5` from a share is unaffected.** But
  `DM4Reader`'s own header promises "the data blob is never copied into RAM";
  on a removable-flagged volume that promise is silently void.

  **The decline is a choice, not an impossibility:** `.alwaysMapped` maps on
  every volume that refused. So the fix is a reader question, not storage
  guidance — though not a free swap, since `alwaysMapped` trades a jetsam kill
  for a SIGBUS if the volume disappears mid-read. Streaming the DM4 as the HDF5
  path already does is the other candidate. **No fix landed here; owner: a later
  session, Gate B.** A CI fixture is free and mandatory for it: a disk image
  created *on the internal disk* carries `MNT_REMOVABLE`, so it reproduces the
  declining case with no external hardware — without it a guard is tested only
  on the one volume class where the bug does not occur.

  **STILL NOT EXPLAINED — the 2026-08-18 death itself, and S9b must not be read
  as closing it.** `docs/visual-acceptance-checklist.md` F1.1d records that the
  cancelled 17.19 GB open *recovered cleanly* that day ("a different file opened
  straight afterwards"), the `Data` is released on the cancel branch rather than
  retained, and the only jetsam report is from 17:38 — over two hours before the
  ~19:55 death. What allocated at 19:55, and from which files on which volumes,
  is nowhere recorded. The mechanism above is real, reproducible and worth
  fixing; it is **not** established as the cause of that incident.

  **No upstream guard exists.** `AppState.makeReader` (`:1990-1996`) does the read
  inside `DM4Reader.init`, before any cancellation or free-memory check — which
  is also why Cancel could not interrupt it, and why S9a's tile guards all sit
  downstream of an allocation that has already completed. Consequence worth
  saying out loud: `openFileForConfiguration`'s comment that "everything done
  here is cheap" (`:1524-1527`) is **false for DM4**, so *Open with Options…* is
  not a safe way to look at a big DM4 first.
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
- ~~**The configurator's preview panes render NOTHING on screen**~~ —
  **CLOSED 2026-08-27 (Gate D + Gate B).** Open from 2026-08-18 through three
  wrong diagnoses. **Cause:** inside SwiftUI's sheet the hosted `MTKView`'s
  `CAMetalLayer` sits at `contentsScale == 0`, and a layer at scale 0 cannot
  display a drawable — while `drawableSize`, the render-pass descriptor,
  `currentDrawable` and the uploaded texture all read healthy, which is why it
  survived so long. Fixed by `MetalImageView.ScaleAwareMTKView`. Track B row
  **F1.3b PASSED**. The full record — the refuted diagnoses, the colour-census
  evidence, the ablation, the Gate B corrections — is in
  [the closed-items archive](archive/closed-items-2026-08.md).

  **Two residuals stay LIVE and are the reason this tombstone is more than a
  pointer:**
  1. **What writes the 0 is unknown.** A detached `MTKView` reads
     `contentsScale == 1.0`, not 0 — measured 2026-08-27, refuting the first
     write-up's "created outside a window comes up with 0", which had reached
     four files before the Gate B read caught it. The 0 was only ever observed
     on a view already in its window, through `AppKitPlatformViewHost`. The fix
     therefore targets an observed state whose producer is unidentified, and its
     `!=` guard is coupled to that unknown writer. Owner: whoever next has cause
     to touch `MetalImageView`, or a session willing to spend an hour in
     SwiftUI's hosting path.
  2. **Regression scope is one workspace.** The subclass applies to EVERY image
     surface in the app; only Prepare (CBED + virtual detector), the inspector
     thumbnails and the sidebar card were seen on screen. Track B row **F1.38**.

  *(Reusable lesson, and it is the transferable part: **a sibling of a different
  KIND is not a control.** The 2026-08-18 dismissal — "`MetalImageView` cannot
  draw inside a sheet" is wrong because the crop rectangle draws in the same
  ZStack — compared a SwiftUI shape against a hosted `CAMetalLayer`. That is a
  valid control against "nothing in this region reaches the screen" and says
  nothing about layer compositing; over-generalising it sent two sessions the
  wrong way.)*
- **TB1 sitting 2: an open froze for minutes at "Checking for a saved
  session…" until cancelled (2026-08-25, ~18:54). The freeze itself is still
  UNREPRODUCED end to end.** Gate D refuted two accounts (a leftover staged
  sidecar; a stale bookmark for the opened path), then measured a real one:
  resolving a stored bookmark whose volume is an unmounted network share
  blocked **30.03 s** on the main actor. **Fixed** with `.withoutMounting` in
  `WorkspaceRecoveryStore.resolve` and `SessionSidecarLocator.grant` — all six
  stored bookmarks now resolve-or-refuse in 27 ms, pinned by
  `BookmarkResolutionLatencyTests`. A second reader then refuted that fix's
  first catch blocks (they deleted a recents entry, and a sidecar grant, for a
  merely-unmounted volume); both now branch on `unmountedVolumeName(forBookmark:)`.
  **But a probe bounded the account:** no stored sidecar bookmark targets
  `/Volumes`, so on this machine that path could not have produced the freeze.
  **A competing account the fix does not address is still open** — a mount that
  succeeded SLOWLY followed by a slow SMB read. Which cube sitting 2 opened was
  never recorded. **If it recurs, run `sample mac4DSTEM 3` in Terminal while it
  hangs** — that is the one observation that would settle it.
  Refuted hypotheses and the full Gate D narrative:
  [the closed-items archive](archive/closed-items-2026-08.md).
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
- **The configurator sheet still clips a text line at its bottom edge —
  RE-OBSERVED 2026-08-27, and it is worse than a caption.** Driven on sim_Au in
  a 2200x1250 window: at scroll position 0 the Size block was cut mid-row at
  *"This selection (f32)"*, and **`Loaded shape` and `GPU budget` were entirely
  below the fold**, along with the closing float32 caption. `Loaded shape` is
  the row a crop actually changes, so the clipped content is the load-bearing
  part, not decoration. A scrollbar exists and reaching the rows works
  (`AXScrollBar` value 0 -> 1), so nothing is unreachable — but S4's intent,
  recorded at `LoadConfiguratorView.swift:44`, was that the standing content
  fits **without** scrolling at this sheet size, and it does not. Enlarging the
  window did not help: the sheet keeps its own size. **F1.17 stays PARTLY
  PASSED / clipping unresolved.**
  Same screenshots: the caption below "GPU budget" is cut mid-height at
  900×760 — the clipping S4's `:44` fix was meant to end. Small, but the
  row (F1.17) explicitly requires no clipped content, so it is a finding,
  not a nit. **Not taken by S18 (2026-08-27):** it is not on the S18 brief's
  list, and that brief is explicitly bounded to the list. It also cannot be
  confirmed fixed without driving the sheet, so it wants a session that ends
  in an owner pass. Still open, owner unassigned.

  **Third observation, 2026-08-27 (late), now with exact geometry rather than
  screenshots.** Re-driven on `downsample_Si_SiGe_exp.h5` in a 1470x923 window:
  the sheet's scroll area runs **y 188-809**, and the closing caption below
  *GPU budget* occupies **y 805-831** - 22 of its 26 points below the visible
  edge, sliced through mid-height. The defect therefore reproduces on a second
  dataset AND a second window size, ruling out the "only at 2200x1250" reading
  the earlier entry could not exclude. Better news too: at scroll position 0 the
  Size block is now visible down to *GPU budget*, so **`Loaded shape` is no
  longer below the fold** - only the trailing float32 caption is cut. The
  load-bearing half of the earlier finding is gone; what remains is the caption.
  Still a finding under F1.17's wording, and still not fixed here - eval-only:
  the row must not be made to pass by resizing the sheet.
- **Unreconciled: the `unit` count is 387, and 384 + this session's 2 new tests
  is 386.** Measured 2026-08-27 on TB1 sitting 1's tree: **387 passed / 4
  skipped / 0 failed, exit 0**, and the 387 are 387 DISTINCT case names — the
  log was checked for retried/duplicated lines, so it is not a counting
  artefact. The last recorded baseline is 384 / 4 / 0 (S18, and again at
  `dc2a532` and `53d6449`), and `MetalLayerScaleTests` adds exactly 2. That
  leaves **one test unaccounted for**, with the skip count unchanged at 4, so it
  is not a skip that started running. No explanation is offered here because
  none was established: the honest options are that a baseline commit message
  under-counted, or that something between S18 and now added a case without
  saying so. Cheap to settle whenever someone wants to — check out `dc2a532`,
  run `unit`, and diff the case-name lists. Recorded rather than smoothed over
  because "384 + 2 = 387" is exactly the kind of arithmetic a reader would
  otherwise assume nobody checked.
  **Second observation, 2026-08-29 (S13 closeout), and it does not resolve —
  it flips.** That run: 392 distinct total (390 passed / 2 skipped). The suite
  diff main → `s13-q-calibration` is exactly +2 cases, in one file, so the
  expected total was 391 + 2 = 393: now one SHORT, where 2026-08-27 was one
  over. Both counts were distinct-name counts, so one case that ran on
  2026-08-27 did not appear on 2026-08-29 while nothing removed it from the
  suite. That rules out "a baseline commit message under-counted" as the whole
  story and points at a case whose existence is environment-conditional. The
  settle-it recipe is unchanged and now needs the two retained logs' case-name
  lists, not a re-run.

- **Gate B outcome for S18's two `Core/` changes — RAN 2026-08-28, both
  SURVIVED.** A separate agent briefed to refute attacked
  `pattern(ry:rx:)` served from the resident cube and the `TileGPUSource`
  staging-copy elimination. Twelve mutations across both, each producing a red
  harness with a distinct named failure. **The debt is cleared**; the model that
  wrote them is no longer their only approver.

  **What it found, and what was done:**
  - **The sharpest lead — that the resident pattern slice indexes with the
    SOURCE scan width and would serve the wrong pattern on a cropped view — is
    REFUTED as a defect**, by demonstration rather than argument: `descriptor`
    is the loaded VIEW's descriptor, which is exactly the stride `makeResident`
    fills at. **But the shipped fixture could not see the class at all** —
    every array it builds is full extent, where the two are equal, so mutating
    the line stayed green across all 27 of its assertions. **Closed:
    `tools/resident-cropped-view` is a new gated harness on a scan-cropped,
    detector-cropped AND binned view (view row stride 144 B against a source row
    of 2880 B), with ground truth computed from source coordinates rather than
    through `LoadView`'s own helpers. Verified by breaking it before trusting
    it:** it goes red at view (1, 0) — got 3813.19, want 2923.57 — on the exact
    mutation the old harness sleeps through. `scientific` is now 38 harnesses.
  - **`residentTileCopies` does NOT prove the staging copy is gone**, though its
    doc comment claimed to. Reinstating a copy *inside* `TileGPUSource.binding`
    leaves every value bit-identical and the counter reading 0. What catches it
    is the fixture's `bound.buffer === cube.buffer` identity assertion. Comment
    corrected in `Core/`.
  - **"The equality was not previously asserted anywhere" is false** —
    `tools/load-spec-test` already pins `readScanTile` against `readPattern`
    across crops, bins and five readers, against independent ground truth. The
    residency fixture's retraction comment cites two harnesses that do not
    actually do it.
  - **The bit-identical claim holds, and its control is load-bearing:** the
    measured-origins mutation differs by 8.5231 against 8.5035 — a 1% tolerance
    would swallow it. The "do not widen a tolerance" warning in that file is not
    decoration.
  - Two smaller corrections landed in `Core/`: the pattern-slice doc comment's
    formula disagreed with the code, and `TileGPUSource` now documents that it
    **pins the resident cube for a whole pass** (before S18, a mid-pass
    `releaseResident()` freed it and the pass finished from disk).

  **Still NOT established, and these are real:** neither change has ever run
  against a real reader on a resident cube — `real-data-acceptance` never goes
  resident; **all coverage of both changes lives in `tools/`**, since
  `mac4DSTEMTests/DatasetResidencyTests` covers the `DatasetResidency`
  lifecycle only and mentions neither `pattern`, `TileGPUSource` nor
  `cubeOffset` — the unit gate contributes zero coverage here; and
  `tools/residency-sweep` is not in `run-tests.sh` at all and measures the
  dropped `.automatic` knee, so it must not be cited as a Gate B fixture for
  these changes. Both changes also remain **unreachable in the shipping app** —
  nothing requests `.resident` — so they are correct, gated, and exercised only
  by harnesses.

- **TB1's WS₂ sidecar fixture is re-staged, and the recipe is now in the repo.**
  It went missing before sitting 2 (found 2026-08-27), which blocked Track B row
  **F1.26** and left `TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes`
  skipping indefinitely — a fixture nobody can rebuild is one that will vanish
  again. `tools/stage-tb1-ws2-fixture/run.sh` rebuilds it: it copies a real
  app-written sidecar beside `polycrystal_2D_WS2.h5` and writes a
  `mac4dstem_load_specification` recording a **200x200 scan crop**, plus the
  minimum-reader marker of 6 that a reduced specification requires. WS₂'s scan
  is 128x128, so `LoadView(source:specification:)` throws and
  `gates.sidecarRestoreFailure` arms as `.doesNotFit` — the state F1.26 reads.
  **Synthesised on purpose:** Si_SiGe is 50x200, sim_Au 100x84, WS₂ 128x128, so
  nothing in the training set can produce a specification WS₂ cannot fit by
  being driven. Verified by rebuilding from nothing and re-running the probe,
  not only by inspecting attributes; `unit` is **388 passed / 3 skipped / 0
  failed, exit 0**. Not gated — it needs gitignored multi-GB data, so it is
  deliberately absent from `run-tests.sh`.

  **Owner drive 2026-08-29: F1.26 remains BLOCKED in the sandboxed app, for a
  different reason than the earlier missing fixture.** The cube loaded at full
  128×128 extent and drew a virtual-detector result, but the inspector reported
  that HDF5 could not open `polycrystal_2D_WS2.mac4dstem.h5`: `errno = 1`,
  `Operation not permitted`. The app therefore never read the staged 200×200
  specification and never armed `.doesNotFit`; its rewrite-refusal surfaces
  cannot be scored from this run. The screenshot proves the boundary cleanly:
  cube access works, sidecar access does not. This is a grant blocker, not a
  failure of the headless fixture or S7's gate, and no app-code change was made
  during acceptance.

  **Assistant-driven follow-up 2026-08-29, exact Xcode Debug product: the
  same-file re-grant reached macOS's Replace confirmation, but the required
  status line is still not scored.** The release owner explicitly approved the
  Replace action. An independent refuter checked the implementation first:
  `NSSavePanel` returns only a URL/grant, and the exact-URL branch of
  `copySidecarFile` returns `.nothingToCopy` before any remove or copy. The
  staged sidecar independently remained byte-for-byte and identity unchanged
  after the click (SHA-256
  `7d21932fc9b48bde4cd2d6439b8fb64df2a53d4d951bac2aea5a08d0579935e9`,
  543,856 bytes, inode 317831317, mtime 2026-08-28 11:20:59). However, the
  Debug app's accessible window disappeared as the modal returned; the process
  remained alive under Xcode, and the accessibility service timed out instead
  of exposing the expected long *"access … re-granted"* status. Asking macOS
  for the app by display name activated the installed `/Applications` release;
  that window was discarded as evidence and closed.

  **Gate D pre-registration for that window loss (written before relaunch):**
  current diagnosis is deliberately narrow — the sidecar was not overwritten,
  and the observed failure is the Debug app losing an accessible window after
  the save-panel return; there is not yet evidence for crash, deadlock, or an
  app-state cause. A clean Debug relaunch that produces a responsive window and
  can reopen WS2 would refute a persistent app/sidecar failure and leave a
  one-run window-lifecycle or harness interaction. Predicted experiment: stop
  the still-alive Debug process, relaunch the exact built product, and reopen
  WS2; the window should return and the persisted grant should let the app read
  the sidecar far enough to arm `.doesNotFit`. A second no-window outcome, an
  unresponsive stack, or another `errno = 1` would refute that prediction and
  split the diagnosis further. No code change is authorised or attempted in
  this acceptance pass.

  **The experiment ran, its prediction held, and nobody wrote the result down.
  Recovered 2026-08-31 from the Codex transcript, NOT from the docs.** The
  2026-08-29 sitting ended at a usage limit moments after the relaunch; its last
  statement was that the window returned, the grant worked, and WS2 reached the
  intended incompatible-session state with all three required inspector
  statements visible. **Treat it as recovered testimony, not a score** — no
  second reader saw those screenshots, so F1.26 stays UNSCORED until re-driven.
  What it does establish cheaply: **the sandbox blocker is clearable**, so a
  re-drive should reach the gate rather than dying at `errno = 1`.

  **The durable lesson:** Gate D requires writing the prediction before the
  experiment, and nothing requires writing the outcome into the *same* edit — so
  a session cut between the two loses the half with the answer in it. Amend one
  entry as the experiment proceeds.

  **Un-actioned review note from the same session.** The independent refuter
  flagged that F1.27's ID cell says *"REOPEN RESULT PASSED"* while that row's
  Status cell is UNVERIFIED and its actual requirement — the same-file re-grant
  message — remains unscored. The reopen evidence is real but belongs beside
  the row as context, not in its identity. Not yet corrected.

- **~~`real-data-acceptance` fails: `report count 8, expected 4`~~ — FIXED
  2026-08-31 by matching on the `file` key instead of by position.** The old
  comparator asserted equal list lengths then `zip`ped positionally, pinning the
  gate to an exact directory listing and able to compare mismatched pairs. Not a
  code regression: the harness's inputs were unchanged and `main.swift` can only
  drop a file from the report on `noDatasetFound` or `sessionSidecarOpened`; the
  data directory had grown to 8 readable cubes against 4 pinned. **Live
  residual — do not treat the fix as having settled the history:** the named
  discriminator (grep S19's retained `all` log for `report count`) was never run,
  and both hypotheses stay open — the cubes were absent that day, or the
  2026-08-28 claim never covered this harness. The fix was justified on the
  defect reproducing on the current tree. Owner holds the log. Evidence:
  [`archive/2026-08-31-comparator-gate-b.md`](archive/2026-08-31-comparator-gate-b.md).

- **A gate that aborts at the first failing harness cannot tell you how many are
  red. Two were.** `run-tests.sh all` stops on the first non-zero harness, so
  `real-data-acceptance` failing hid `package-test`, which had been red since
  2026-08-28. Both fixed 2026-08-31; `all` is exit 0 over 42 harnesses. Whether
  the runner should continue-and-summarise instead is open, and it is the
  general form of this pair. Owner: unassigned.

- **`package-test` asserted the pre-S19 macOS floor, so S19's "green end to end"
  claim cannot be true.** `run.sh:34` pinned `LSMinimumSystemVersion = "14.0"`;
  `aeaeacc` (S19) is the only commit that raised `MACOSX_DEPLOYMENT_TARGET` to
  26.0 and it did not touch that file, so after it the harness must fail — and
  did, silently, `set -euo pipefail` on a bare `test` printing nothing. **Fixed**
  (assert `26.0`): a stale test, not a widened gate — the floor is the reviewed
  product decision. **Live residual:** S19's aggregate claim is therefore not
  evidence for anything, and the `real-data-acceptance` discriminator (grep S19's
  retained log for `report count`) is still unrun and still owner-only.
  Evidence: [`archive/2026-08-31-comparator-gate-b.md`](archive/2026-08-31-comparator-gate-b.md).

- **OWNER DECISION: the 15 s acceptance budget no longer applies to unpinned
  datasets.** `main.swift` records `elapsedSeconds` but never gates on it, so the
  budget lived only in `compare.py`, which now checks pinned datasets only —
  4 of 8 cubes, and the four unchecked ones are the large ones. What was lost is
  a forcing function: a new dataset used to be unable to go green until a human
  pinned it. Pin-or-refuse, or accept the advisory `UNPINNED` line? Recorded as a
  dropped property in `compare.py`'s docstring, not silently absorbed.

- **OWNER DECISION: `abs_tol=1e-3` on the virtual-image fields exceeds the whole
  dynamic range of the real `polycrystal_2D_WS2` image (5.3e-4).** A regression
  *halving that image's contrast* passes the gate and also satisfies
  `main.swift`'s `guard maximum > minimum`. **Pre-existing** — tolerances
  unchanged — and it matters most for exactly the dataset W4 is about to point
  ACOM at. The fixture now carries a WS₂-magnitude entry so the boundary is
  testable; the tolerance is NOT changed, because tightening it could redden
  legitimate runs. Trap: the comparator suite reports 46/46 over this hole.

- **The comparator matches by name; Gate B (three refuters) took its claims
  apart and the core survived.** `compare.py` no longer asserts a report count.
  Corrected in place: two false comments this session wrote, an unciteable "8 of
  9" statistic, a dead `"file"` assertion, a fixture symmetric in both axis pairs
  (the S8 lesson, repeated), and both `math.isclose` parameters being
  individually deletable with the suite green. Suite is now **46 checks** in
  `tools/comparator-test`, which is in the `scientific` array so **CI runs it** —
  it was previously reachable only from `all`, which CI never runs. **Residuals,
  stated in the files:** `rel_tol` on `diskProbeRadiusPixels` is inert below a
  50 px radius (real radii 1.8-6.2), and `if not actual:` is subsumed and
  unkillable by any mutation. Full narrative and the refuters' findings:
  [`archive/2026-08-31-comparator-gate-b.md`](archive/2026-08-31-comparator-gate-b.md).

- **`real-data-acceptance/run.sh` never adopted `tools/lib/sources.manifest`.**
  It hand-spells 18 source paths plus a `Shaders/*.metal` glob, while e.g.
  `q-calibration-gate-test/run.sh` sources the manifest — which exists because
  hand-spelled lists broke five of eight harnesses on 2026-08-17. That is what
  let a "these inputs are byte-identical" audit miss `OriginMeasure.metal`.
  Not fixed; own session.

- **`run.sh`'s empty-glob SKIP exits 0, so a machine with zero datasets passes
  this gate.** Deleting all four pinned cubes leaves it **green** — the
  missing-dataset guard never runs. Pre-existing and deliberate (the data is
  gitignored), but it bounds what that guard is worth, and `compare.py`'s
  docstring now says so rather than claiming the guard is unconditional. Whether
  the SKIP should consult `expected.json` is open.

- **The exported Euler angles are NOT py4DSTEM/orix-comparable, and two source
  comments say they are. A colleague who compares them to py4DSTEM is off by a
  median 38.55°.** Found 2026-09-01 by the first-principles Gate B refuter while
  verifying the ACOM convention (below). **The numbers are right; the label is
  wrong** — this is a presentation/provenance defect, not a math defect, which
  is exactly the class §1's fourth commitment exists to prevent.
  **Evidence.** `Core/Analysis/OrientationResult.swift:12-13` says
  "py4DSTEM/orix-compatible Bunge Euler angles in radians" and `:88-90` says the
  columns match py4DSTEM's `Orientation.matrix` convention. But the app's columns
  are (detector x = COLUMN, detector y = ROW, n = DOWNSTREAM) while py4DSTEM's
  are (qx = ROW, qy = COLUMN, lab z = UPSTREAM). They differ by `P`, a proper
  180° rotation about [110]_lab (measured det +1, trace −1, fixed axis (1,1,0)).
  **The repo already knows this in two other places and contradicts itself
  here:** `Core/Crystal/OrientationPlan.swift:163-165` states "the two lab frames
  differ by the x↔y swap plus a z flip", and
  `tools/training-dataset-campaign/parity_py4dstem.py:415-428` applies `lab_swap`
  for precisely this reason.
  **The decomposition itself is fine** — `EulerAngles.init(py4DSTEMOrientationMatrix:)`
  (`:31-52`) transcribed into numpy and compared against SciPy
  `R.from_matrix(M.T).as_euler("zxz")` (py4DSTEM's own export at
  `crystal_ACOM.py:2519`) over 2000 random proper rotations: max discrepancy
  **1.30e-12°**; `crystalToLabMatrix` round-trips to 2.69e-15. Only the INPUT
  MATRIX'S FRAME differs.
  **Why it is not a comment nit:** those angles ship to users.
  `Support/ResultExport.swift:552-554` exports `orientation_phi1` /
  `orientation_Phi` / `orientation_phi2`. Over 3000 random orientations the
  cubic-symmetry-reduced misorientation between `M_py` and `M_app = M_py @ P`
  for the SAME physical state is median **38.55°** (p10 17.97, p90 55.53, only
  0.7% under 5°).
  **The trap:** "fixing" this by changing the matrix would break the app's own
  internally-consistent frame and every result already exported. The likely
  right fix is to state the frame in the export metadata and correct the two
  comments — or to export both frames. **Owner: decision needed (relabel vs
  convert vs both), then Gate B.** Pairs with the projection-frame item below.

- **A projection-frame defect in `OrientationPlan.project` is invisible to
  EVERY gated ACOM harness. THE SHIPPING CONVENTION ITSELF IS CORRECT —
  verified 2026-09-01, three independent ways — so this is a COVERAGE GAP, not
  a live wrong-science defect.** Read that first: the item was filed before the
  verification and its original wording ("wrong science") described the
  mutants, not the app. **The verification** (one investigator, two refuters,
  all three agreeing): a first-principles derivation of the whole chain; an
  analytic fixture whose experimental peaks are built in the harness and never
  call `project()` — cubic FCC Au, 144 trials, median |Δφ| 1.10° against a
  2.81° azimuthal bin; hexagonal WS₂, 240 trials, 240/240 within 20°, median
  misorientation 0.79° — and an end-to-end run against **py4DSTEM 0.14.17's own
  forward model** (40 random orientations through
  `Crystal.generate_diffraction_pattern`, median symmetry-reduced misorientation
  2.06°). A refuter then swept **all 24 proper signed-permutation frame maps**:
  the shipping best map is the expected `lab_swap` at 2.06° with second-best at
  22.72° — selected by a factor of 11, so the agreement is not an artefact of a
  hand-picked frame, and neither mutant is rescued by any map (best 20.46°).
  W4b Gate B, 2026-08-31. Two mutations at
  `Core/Crystal/OrientationPlan.swift:192-194` — swapping the in-plane basis
  (`x = g·e2, y = g·e1`) and flipping handedness (`atan2(-y, x)`) — leave
  `acom-matching-test`, `fit-overlay-test` and `acom-orientation-test`
  **byte-identical at exit 0**. **Wrong science, not a frame choice:**
  `ACOMOrientation.matrix` (`Analysis/OrientationResult.swift:99-106`) composes
  `basis * Rz(angle)`, asserting the template azimuth zero is `e1` and the
  experimental zero is detector +x (`OrientationMatcher.swift:242`); the
  transpose breaks that, so every in-plane angle, Euler triple, IPF colour and
  exported `orientationMatrixRowMajor` is wrong on real data. **The trap:** the
  cancellation is structural — every gated ACOM fixture builds its experimental
  pattern with the same `project` that builds the templates, and `normalizeUnit`
  then forces self-correlation to exactly 1. **An in-plane-angle assertion does
  NOT close it** — written and measured, both mutations still pass (w4b.md §3).
  **Measured on the harness that actually gates, 2026-09-01:**
  `tools/acom-matching-test` — WS₂ scale-sensitivity arm included — runs
  **completely green, exit 0, every PASS line, against the e1/e2 transpose**,
  which produces 20–63° orientation errors. Control and mutant are
  indistinguishable. Root cause: `tools/acom-matching-test/main.swift:55` builds
  the harness's peaks by calling `OrientationPlan.project` itself, and the WS₂
  in-plane check at `:321-327` reduces modulo π, so it is blind to a π-flip too.
  **The score cannot save you:** mean correlation on identical py4DSTEM input
  was 0.799 shipping vs **0.811 for BOTH mutants** — the wrong answer scores
  *higher*. Same shape as the reliability blind spot above.
  **A global mirror survives a shared-convention check:** MUT-C (mirror template
  AND experimental azimuth together) and MUT-D (drop the negation at
  `OrientationMatcher.swift:313-314`) both scored **0.799, identical to
  shipping**, while landing 26.02° and worse from truth.
  **CORRECTION to this entry, 2026-09-01:** it previously called
  `tools/acom-groundtruth` "the only py4DSTEM ACOM comparator". **It compares
  nothing** — a JSON-in/JSON-out CLI wrapping Crystal + OrientationPlan +
  OrientationMatcher with no reference, no assertions and no pass/fail; it exits
  0 whenever the plan initialises. Its value is that it takes peaks from JSON,
  so it is the natural host for a real fixture.
  **Fix:** experimental peaks not produced by `project` (an analytic [0001] hk0
  fixture, sign-discriminating angle 37.2° per the S8 lesson), and give
  `acom-groundtruth` a committed driver plus expectations. **Working probes
  already exist and are known to discriminate** — landing them as a gated
  harness is the whole of the remaining work. Suggested thresholds from the
  measurements: cubic median misorientation < 3° with ≥120/144 trials inside
  20°; hexagonal median < 2° with 240/240 inside 20°. Both mutants miss those by
  an order of magnitude. **Owner: Gate B, unscheduled.**

- **The exported ACOM orientation matrix can be decoupled from the reported
  template index, unnoticed by any gate.** W4b Gate B, 2026-08-31. Building the
  result from `detectorBases[(bestTemplate + 1) % count]`
  (`OrientationMatcher.swift:315`) leaves `acom-matching-test` at exit 0 with
  identical output: the reported `templateIndex` is right, the exported
  orientation comes from a different zone axis. `acom-orientation-test` pins
  `ACOMOrientation.matrix` in isolation and never calls `matchAll`, so the
  wiring between them is untested. **The trap:** the obvious assertion is wrong
  — rebuilding the matrix from the reported template/angle matches at fixture
  position 1 (4.5e-8) and disagrees at the other seven by O(1), because `euler`
  is symmetry-reduced; a correct check compares modulo the symmetry group.
  **Owner: Gate B, pairs with the projection-frame item above.**

- **Three smaller ACOM blind spots, measured 2026-08-31, none gated.**
  (a) An **additive** radial offset survives — `+ 1` on
  `OrientationPlan.swift:221` displaces every ring on both sides and
  `acom-matching-test` stays green; the WS₂ arm pins a *multiplicative* scale
  error only. (b) **Reliability is entirely unpinned**: inverting the
  distinctness test at `OrientationMatcher.swift:297` (`>` → `<`) leaves the
  harness green, and the gold arm cannot see it because its "scalar reference"
  calls the production `selectOrientation`. Given that reliability ranked a
  wrong Q scale above the right one, this is the metric most needing a pin.
  (c) **`intensityPower = 0.25`** (`OrientationPlan.swift:96`, locked to
  `crystal_ACOM.py:33`) can be changed to 0.5 with the harness green.

- **`MAC4DSTEM_ACOM_SCALE_OVERRIDE` leaves one run emitting two artifacts that
  disagree about Å⁻¹/px.** W4b Gate B, 2026-08-31; two of four findings fixed
  the same day (it now refuses an unparseable or non-positive value instead of
  falling back silently, and records `.manual` provenance plus an `issues` line
  rather than claiming `.measuredInApp` for an env-supplied number). **Live
  residual:** (a) `calibration.qPixelSize` keeps the *estimate* while the
  orientation map was matched at the *override* — verified on
  `e4-corrected/polycrystal_2D_WS2_h5.mac4dstem.h5`, `Q_pixel_size` 0.008788661
  beside a product matched at 0.019448; whether the sidecar should carry the
  matching scale or refuse to be written under an override is a design call.
  (b) On a *cubic* dataset an override run would compare apples-to-oranges:
  `parity_py4dstem.py:compare_acom` never reads `invAngstromPerPixel` and builds
  its own plan from `bragg.setcal(pixel=True)`. Cannot arise for WS₂ (that
  comparator returns `"pass": None` for non-cubic).

- **`KnownCrystalQCalibration.estimate` measures the reference ring by the
  per-pattern MINIMUM radius, biased low by an order statistic — 1.92% on
  `polycrystal_2D_WS2`, making the Q scale ~1.9% too large.** W4b Gate B,
  2026-08-31, found while checking why the record's two scales did not divide to
  the predicted factor. `Analysis/QCalibration.swift:138-157` takes each
  pattern's innermost non-central radius then the median → **18.46677 px**, and
  0.162298/18.46677 = 0.008788661 reproduces the shipped value to nine digits;
  but ring 1 carries **5.26 spots/pattern at σ = 0.2992 px**, so
  E[min] ≈ mean − 1.28σ ≈ 18.45 against a population mean of **18.8283 px**.
  **Independent of the (0002) shell defect and survives fixing it:** correcting
  only the shell and keeping this statistic gives 0.019830 vs the data-derived
  0.019448, a residual +1.97%. It is also why w4b.md quoted a 2.2564× defect
  factor when its runs produced 2.2129× — two different radius statistics.
  **The trap:** the bias grows with spots-per-ring and with peak noise, so it is
  dataset-dependent and no constant corrects it. **Owner: Gate D first** (mode,
  trimmed mean, or radial-profile fit?), then Gate B; take it together with the
  reference-shell item below — same estimator, one fixture can cover both.
  Evidence: [`w4b.md`](archive/v2-session-records/w4b.md) §1 E3(b).

- **The Q-calibration reference shell has no l-filter and no visibility filter,
  and on 2H-WS₂ it selects (0002) — a reflection a [0001]-zone 2D specimen
  never shows. Predicted mis-scale on this dataset's own geometry: 2.2564×,
  silent.** Found by the W4 feasibility review (mechanism), MEASURED by
  `tools/ws2-crystal-test` 2026-08-31 (outcome): `AppState.swift` ~5038-5051
  takes the first distinct |g| of the full 3D `reflections(kMax: 2.5)` list;
  for the cited WS₂ cell that is 0.16230 Å⁻¹ ((0002), strongly allowed), while
  the first in-plane shell is 0.36621 ((10-10)). S13's Gate B cut every
  threshold that could refuse the resulting scale, so the shell-ratio check
  would *report* the disagreement and pass the number through. **The trap:**
  the demo/SPED_MgO probe-radius findings look similar but are a different
  mechanism — do not merge them. **Evidence:** the REPORT line and check 5 of
  `tools/ws2-crystal-test` (which pins the CURRENT selection, so whoever fixes
  the rule must update that check and this item together). **Not fixed, by the
  owner's 2026-08-31 safe-defaults decision** — the fix touches W3 territory
  (`QCalibration`/`AppState`), needs its own design (which shells ARE
  observable given zone axis and precession?), and the right statistic for the
  origin gate is already an open design question next door. **Owner: W4b or a
  dedicated W3 follow-up, owner's call.** Until then, known-crystal Q
  calibration on ws2_2h against [0001]-zone data will be wrong by ~2.26× and
  labelled calibrated; also note WS₂'s fitted probe radius (1.859 px, S12) sits
  UNDER the ~2 px breakdown onset the Q-cal fragility entry documents.
  **Data evidence, added same day:** the Gate B refuter measured the cube's
  mean pattern — ring ratios 1 : 1.7355 : 2.0130 : 2.6463 : 3.0012, exactly the
  hk0 set (1, √3, 2, √7, 3), with no interior (00l) ring (inner-annulus mass
  350× below ring 1). The specimen really is basal, the first observed ring
  really is (10-10), so the mis-scale would bite exactly as predicted; c is
  invisible to this dataset, so the mp-224-vs-literature difference that
  matters for W4b's matching is a (+1.19%), not c.
  **The bite, MEASURED end to end (W4b, 2026-08-31):** on the real cube the
  estimator returned 0.008789 Å⁻¹/px (data-derived correct: 0.019448 — factor
  2.213 under, vs 2.256 predicted from geometry alone). Matching the same
  vectors at both scales: the correlation score HALVES at the defective scale
  (median 0.214 vs 0.399) and the assigned zone axis is wrong (4.6° off beam
  vs 0.0°). **Trap discovered in the same experiment: median
  `reliability` was HIGHER at the wrong Q scale than at the right one** (0.115
  defective vs 0.094 corrected — near-[0001] templates are nearly degenerate at
  the right scale), so a reliability-ranked comparison BETWEEN CANDIDATE SCALES
  would prefer the wrong one, and no fix or UI surface for this defect may lean
  on reliability to choose. **Narrowed by Gate B, 2026-08-31**: this entry
  previously said reliability is "anti-correlated with correctness on basal
  specimens", which the session's own data refutes — *within* the corrected run
  the correct basal template has the higher median reliability (t0 0.0940 vs
  non-t0 0.0827), Spearman(score, reliability) is +0.011, and mean reliability
  falls across the sweep as noise enters. One ordered pair between two runs is
  not a correlation.
  Evidence: [`w4b.md`](archive/v2-session-records/w4b.md).
  **The scale-sensitivity control LANDED 2026-08-31** in
  `tools/acom-matching-test` (gated, in `scientific`): at the true scale the
  WS₂ fixture recovers 8/8 generating templates, at the mis-scale 0/8, and the
  median score drops 68.2%.

- **Working method: do NOT drive the app while `run-tests.sh unit` is running.**
  Observed once, 2026-08-27. A gate run made while a build-under-test instance
  was open for Track B reported
  `SidebarDensityMeasurementTests.testMeasurePrepareSectionCosts()` **failed at
  0.000 s** (the test-host crash signature), exit 65. The identical tree, re-run
  minutes later with no app running, was **387 passed / 4 skipped / 0 failed,
  exit 0**. So the failure was the environment, not the tree.
  **The mechanism is plausible but NOT established:** the layout-measurement and
  sidebar suites inject private `AppStorage` into the app's own defaults domain
  (S17), and a live instance writing the same domain is the obvious suspect —
  but that was inferred from one observation, not measured, and nobody has
  reproduced it deliberately. Recorded because the failure looks exactly like a
  real regression in the one test class whose history is already a long-running
  intermittent, and a session that assumed the worst would chase it for an hour.
  If it recurs, the cheap discriminator is the one used here: re-run with the
  app closed before diagnosing anything.

- **The status line leaks a full filesystem path.** The composed message runs
  ~330 characters including the absolute path, rendered raw at
  `ContentView.swift:1007` and `ProductWorkspaceViews.swift:427`. Track B
  screenshots go into public docs. Worth truncating the path for display while
  keeping it in the log. **Recurred visibly on 2026-08-19:** the S1 refusal
  line renders the full absolute path of the sidecar in the console pane, and
  it appears in the Track B screenshots taken that day. Still open.

### 2026-08-18 Track B pass and its follow-up thread — untangled 2026-09-01

The 661-line narrative that lived here — the 2026-08-18 drive of the 4.25 GB
036 cube, the L4 review notes, and every follow-up entry appended under this
heading through 2026-08-29 — is verbatim in
[`docs/archive/2026-08-18-trackb-036-and-followups.md`](archive/2026-08-18-trackb-036-and-followups.md).
Below is only what is still live; the archive carries the evidence, the
refuted hypotheses and the closed items' full records.

- **Recents-row location labels are unverified on screen** (fix landed
  2026-08-18: shortest-distinguishing volume/path label per recent). Track B
  row F1.1c.
- **Detector-bounds convention sweep owed.** `CalibrationReReference`'s
  off-by-half (index convention `[0, width)` used for a continuous position;
  correct is `[-0.5, width-0.5)`) was fixed 2026-08-18 — but other
  detector-bounds tests may use the index convention for continuous positions
  too; nobody has looked.
- **`measureOrigin` coarse-grid equivariance: weighed OUT of v2 on a
  measurement.** S2 proved the coarse grid is the cause (0.609 px → 1e-6 px
  with stride 1); S12 measured the remedy's cost (2.5× at bin 2 up to 86× at
  bin 11 — up to 3.6× the whole origin stage) and recommends against; re-entry
  condition in [`q-calibration-design.md`](q-calibration-design.md) §4. The
  0.337 px absolute error is a separate defect; both are pinned by
  `tools/two-spec-analysis-test` (`P4_KNOWN_BOUND` 0.65,
  `ORIGIN_ABSOLUTE_BOUND` 0.40). Also standing: `measureOrigin` does ONE CoM
  refinement, not an iteration to convergence — a harness assuming the origin
  is a fixed point of its own CoM will fail and look like a crop bug (it did,
  2026-08-18).
- **Sidecar rename/relocate residuals** (feature shipped by S4): the stranded
  `calibrationData_bullseyeProbe.mac4dstem.h5` on the Desktop can now be
  brought home by the owner; a retarget made before any save exists survives
  only until the next dataset change (stated in the status message); rows
  F1.20 + F1.3i queued.
- **Repeating Save Session Sidecar As… can prefill a doubled `.h5.h5`
  suffix** — owner drive 2026-08-29, screenshot + the resulting 494,336-byte
  file as evidence; a naming/Save-panel finding only, no cause claimed.
- **Pre-S4 calibration-only sidecars remain unrecognisable**, and the
  extension/open-panel-filter half is an owner decision queued for TB1.
  Track B row F1.21.
- **The configurator's beam proxy (mean pattern's brightest pixel) has no
  "load anyway" override** — owner question queued for TB1; unifying this
  gate with `CalibrationReReference`'s into one policy owner is queued on
  that decision (S7 built the seam, `App/SessionGates.swift`, and
  deliberately did not unify — s7.md deviation 2). Rows F1.17/F1.18.
- **The virtual-detector mask boundary is unpinned against analytic truth.**
  The app is correct today (`r² < rOut²`, matching py4DSTEM), but flipping it
  to `<=` stays green everywhere — every harness runs the same `makeMask` on
  both sides. Fix: one assertion against an analytic mask. Cheap; not done.
- **Runner source lists: the manifest-sourced count is still one.** S7
  patched `SessionReplayRecord.swift` into seven hand-listed runners after
  the predicted breakage recurred; the 2026-08-18 manifest policy stands,
  unimplemented for those seven.
- **`Aperture` is declared in `App/AppState.swift`; scientific harnesses
  carry their own copies** that would still compile and pass if the app's
  gained a field. Honest fix: move it into `Core/` — belongs to a session
  already touching that area, not a harness session.
- **The app build is the only real gate for actor isolation.**
  `tools/load-spec-test` compiles nonisolated; the manifest's
  `MAC4DSTEM_ISOLATION_FLAGS` (S2) buy visibility, not enforcement — swiftc
  exits 0 on the one diagnostic they surface.
- **Load-cancel residuals:** F1.1d (cancel a real load on screen) has never
  been driven; teardown of a resident buffer / cropped view is unpinned —
  the demo path cannot reach those states (the honest gap in
  `DatasetLoadCancellationTests`).
- **#17a — the wider pane-ARRANGEMENT question is still open** (design
  decision; built and reverted on sight 2026-08-05). The configurator-pane
  half was settled on measurement 2026-08-27/28 and is archived. Kept lesson:
  a claim whose only witness is a blocked Track B row is not a verified
  claim — write it in the unverified voice until the row scores.
- **A DPC result on an uncalibrated dataset is badged "Quantitative" while
  the banner above says it ran in qualitative units — and it escapes into
  exports.** Mechanism read from code:
  `AppState.quantitativeStatus(for:units:)` (`App/AppState.swift:735-746`)
  pattern-matches kind/units strings and falls through to `.quantitative`
  for anything it does not recognise; it never consults calibration state
  (S7's `originFitIsQuantitative` exists and is not consulted). Verified
  escaping 2026-08-27: the exported PNG's XMP carries
  `"quantitative_status":"quantitative"` beside
  `"value_units":"detector_px"`, and the strain export contradicts itself
  inside one dictionary (`"quantitative"` +
  `"strain_frame_reason":"qr_rotation_not_calibrated"`). Fix is a judgement
  call (the status consults readiness, or the badge says what it means);
  owner: the trust-fixes / error-honesty session. Full record in the archive.
- ~~TB1's staged WS₂ foreign sidecar is GONE; F1.26 blocked~~ — **re-staged
  2026-08-28** (`tools/stage-tb1-ws2-fixture`, recipe in the repo, commit
  `1888b15`); `polycrystal_2D_WS2.mac4dstem.h5` is present beside the cube.
  F1.26 is drivable again.
- **Launch-screen Prepare/Analyze/Preserve cards are too large** — owner
  suggestion 2026-08-27: lay them out side by side; today they push the real
  entry points below the fold (see also the welcome-screen ⌘N finding,
  2026-09-01, in the triage doc). UX queue.
- **At the 171pt pane-width floor the pane header degrades** — the title
  truncates and the "Relative" badge wraps one letter per line. Pre-existing;
  fix likely `lineLimit(1)` + `fixedSize`, or hide the badge below a width.
  UX queue.
- **Selected-area diffraction's scan-mask-to-tile correspondence is
  unpinned.** Gate B demonstrated (2026-08-27): replacing the per-tile mask
  slice at `Core/Analysis/VirtualDetector.swift:354` with row 0's mask is
  green on every harness in the repo — scan rows the user excluded would be
  summed in: wrong science, plausible numbers. Fix: a ground-truth case in
  `tools/virtual-detector-test` with ry ≥ 4 and a region covering only some
  rows, `tiledDiffraction(maximumTileRows: 1)` against the whole-cube path.
  Owner: whichever session next touches virtual diffraction.
- **`releaseResident()` is asserted by a derived number** —
  `ResidentCube.byteCount` is computed from the descriptor, never measured,
  so a leaked `MTLBuffer` is invisible to every test (the Gate B mutation
  held the buffer; everything stayed green). Fix: observe the buffer weakly
  across the release rather than asserting a derived count.
- ~~No fixture exercises the resident read paths under any
  `LoadSpecification`~~ — **closed 2026-08-28**: `tools/resident-cropped-view`
  gates a scan-cropped, detector-cropped AND binned view, including
  `pattern(ry:rx:)`.
- **#37 — virtual-detector cancellation cost is I/O, not check granularity;
  owned by S9.** Measured (S18): the streaming per-tile bound is single-digit
  ms and dispatch-only; the resident bound did not reproduce between two
  same-day runs (13.2 vs 20.3 ms — anything quoting it, S20 especially, gives
  a range). The synthetic harness excludes the read half; on a real file the
  read is the whole story. Re-measure against a real reader when S9 has NAS
  access.
- **`TiledDiskDetection.detectAll` still stages each tile into a fresh
  `MTLBuffer`** — out of S18's bounded staging-copy elimination (the offset
  must thread through the whole multi-dispatch chain, not one `setBuffer`).
  Owner: whichever session next touches disk detection.
- **Resident cancellation is 2.5× coarser than streaming** (one indivisible
  dispatch, checks either side) — measured, academic until a shipping control
  requests `.resident`: nothing under `mac4DSTEM/` calls
  `DatasetResidency.request(_:on:)`.
- **F1.33 has never been driven** — the #38 scroll-monitor fix is unverified
  on screen.
- **#31 — `validationIssues` is O(n²) and runs in a SwiftUI view body.**
- **#32 — `isSymmetry`'s bijection check has no fixture coverage**, and its
  stated counterexample does not exercise it.
- **#30 — origin calibration over a NAS runs at ~3 MB/s.** Investigation.
- ~~#11 — no WS₂ crystal model~~ — **CLOSED by W4a, 2026-08-31**: the 2H-WS₂
  model from the 1987 refinement, with its review-hardened fixture;
  `polycrystal_2D_WS2` reaches ACOM (W4b). Records in
  [`docs/archive/v2-session-records/`](archive/v2-session-records/).
- **#18 — the campaign cannot reproduce the app's strain result on Si_SiGe;
  mechanism RESOLVED, fix owed.** The single differing input is the
  reference origin: the campaign faithfully uses its fitted mean origin
  (~7 px off centre — the non-quantitative #46 fit), so the direct beam
  survives `minRadius` at every position and poisons
  `estimateLatticeBasis`'s clustering scale (tolerance ≈ 1.05 px against
  true shells at 17–42 px → candidates = 0). The app succeeded because its
  gate rejected that fit and the detector-centre fallback happened to be the
  true beam. Two candidate fixes, neither made (science changes, own
  Gate B): floor `minRadius` at the probe radius or scale it with origin-fit
  quality; or the campaign adopts the app's origin gating. Latent app-side
  risk: a genuinely off-centre beam with `meanOrigin` nil fails exactly as
  the campaign does. Si_SiGe strain parity stays campaign-evidence-only
  until one lands. Full instrumented-diff narrative in the archive.
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

  **A second, sharper limit, measured 2026-08-28:** with the boot volume at
  **10 GB free** — one build from the 8 GB preflight refusal — `free-space.sh`
  reported **0 B across all six targets**. The docs name it as *the* remedy for
  an exit-69 refusal; on that day it had nothing to give, because the pressure
  was entirely outside its two roots: Claude Desktop's VM bundle (10 GiB
  `rootfs.img`), `~/.cache/codex-runtimes` (3.4 GB) and package-manager caches
  (~1 GB). Clearing those by hand took the volume to **24 GB**. So the script's
  scope is narrower than the problem it is cited for, and a session that runs
  it, sees `0B` and concludes "nothing to reclaim" will be wrong. Either widen
  it to the agent-tooling roots (they are regenerable, but one held 33 MB of
  live VM session state that had to be preserved first — so it needs the same
  structural care the existing guard has, not a bigger glob), or amend the
  places that call it the remedy. Owner: same as above.

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
