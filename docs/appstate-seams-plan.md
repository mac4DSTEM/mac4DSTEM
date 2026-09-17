# AppState seams — the plan to empty `AppState.swift`

Pre-registered 2026-09-18. Governs the audit's refactor row 5 (`open-items.md`)
until `AppState.swift` holds owners, the window and publishing, and nothing
else. Decision of record: one owner per feature on the `Session/StrainProduct`
pattern; no store framework (`architecture.md`).

**To run the overnight part, paste this into a fresh session in the repo:**

> Run `docs/appstate-seams-plan.md`, seams 1–4 in order, under its "Overnight
> protocol". Do not stop for questions. Append the log section. Do not push.

`/pickup` finds the same target through the `docs/status.md` handoff row.

## Where it stands (measured 2026-09-18, commit a0ffb2a)

`AppState.swift` is 4 699 lines (5 476 before the Calibration/PhaseContrast
placement split). Ten features already have an owner type held by AppState as
one instance: replay, gates, strain, diffraction groups, phase mapping,
Q-calibration, calibration session, ACOM session, learned detection, disk
labels. Still inside, by cluster (stored properties): Parallax 23, display 18,
ACOM 15, result 8, dataset 7, disk 5, DPC 2, virtual 2, Bragg 2. Sections still
inside: Configured open 1 523 lines, Analyses 492, Disk detection 425, ACOM
355, DPC 217, Strain 213.

## What a seam is

An `@Observable @MainActor package final class` in `Session/` that is the one
owner of a feature's retained results, run controls and last failure cause.
AppState holds it as `let x = XProduct()`, no forwarding properties; views read
`appState.x.…`; orchestration in `App/AppState+X.swift` mutates it through the
owner's own methods, so the owner's results are `package private(set)`.
What never moves in: the shared display derivation (`resultImage`,
`resultColormap`, `displayed*`) — an owner signals a presentation change and
AppState re-derives (see `StrainProduct.onPresentationChange`).

## Rules for every seam

1. State moves **verbatim** with its `didSet` observers; an observer may be
   relocated or turned into a named method, never deleted or rewritten.
2. No logic changes. The diff of each moved function body against the
   pre-seam file must be identical except for the owner prefix and access
   keywords; the seam session records the diff command and its result.
3. Every reader outside AppState is repointed and **listed in the commit**;
   the compiler finds them (the old names stop existing), so a build that is
   green is the proof the list is complete.
4. Tests: the new owner gets a test file on the `StrainProductTests` pattern
   — construction defaults, one mutation through a method, one observer effect
   — and each test is broken once (a wrong default, a removed observer) before
   it is trusted; the log records the red run.
5. Gates on the tree, in this order, each to a retained log with its exit
   line read from the log: scratch app build (`build/prepush/DerivedData`),
   `tools/run-tests.sh unit` (count reconciled against `func test` in
   source), `tools/run-tests.sh inventory`. `core` is not affected (App/ and
   Session/ are outside the packages; Session/ files ARE compiled by tools
   harnesses via `tools/lib/sources.manifest` only when listed there — a new
   Session file that a harness needs is added to its group, else left out).
6. Nothing is claimed on screen. Each seam lands in the `docs/status.md`
   "Unverified on screen" cell as "Phase/ACOM/… workspace after seam N".
7. Placement only where an owner is impossible: if state cannot move (a
   property the whole app shares), the seam moves functions to
   `App/AppState+X.swift` and says so — that is tonight's Calibration split,
   and it is the fallback, not the goal.

## Overnight protocol (seams 1–4, unattended, sequential)

- One seam at a time, on `main`, no branches or worktrees. Before touching a
  file, copy it to the session scratchpad; restore with `cp` and prove with
  `cmp`, never with `git checkout`.
- **The run does not stop for a failed seam.** A seam that hits a stop
  condition is restored from the copies, its reason appended to the log, and
  the run continues with the next seam. Stop conditions: a gate red after two
  compiler-fix rounds; a `didSet` whose relocation would change ordering; a
  reader outside `mac4DSTEM/` (a tools harness) that would need a manifest
  change; more than 5 access widenings left after the move. The night halts
  only if the tree cannot be restored to a green build — then the log says so
  and the morning starts from the last green commit.
- Each green seam is **one commit** with the gate numbers and log names, the
  widening count, the readers list, and the "unverified on screen" line;
  `docs/status.md` (handoff row + unit gate row), `open-items.md` row 5, and
  `CHANGELOG.md` Unreleased are updated in the same commit.
- Budget: about 250k tokens per seam including gates; the unit gate is
  ~10 min; disk must stay above 4 GB (`tools/free-space.sh`).
- Morning report = the log section below plus the status table; nothing is
  pushed.

## The seams

### 1. `PhaseContrastProduct` — Parallax and single-slice ptychography

- **Moves:** the 23 `parallax*` and `singleslicePtychography` properties
  (`AppState.swift` 329–358) — six results, sixteen run controls, the selected
  depth plane and product — with the two `didSet` observers on
  `parallaxAlignment` and `parallaxHigherOrderFit`.
- **Owner:** `Session/PhaseContrastProduct.swift`; results `package
  private(set)`, mutated by `reset(from:)`-style methods the orchestration in
  `App/AppState+PhaseContrast.swift` calls.
- **Readers:** 2 UI files (`UI/PhaseSettings.swift` and one more), the
  orchestration file, `ResultExport` if it names any (`grep -n parallax
  Support/`).
- **Reverses:** the 11 `private(set)` widenings of 2026-09-18.
- **Predicted:** `AppState.swift` ≈ 4 650 lines; unit count unchanged plus the
  new owner's tests.

### 2. ACOM leftovers into `ACOMSession`

- **Moves:** the 15 `acom*` properties (measured template count, backend, scan
  selection, work summary, duration estimates and their text, primary action
  title, model-selection issue, scale semantics, scale, interpretation label,
  effective reliability threshold) into the existing owner `ACOMSession`; the
  355-line ACOM section (`calibrateQFromCrystal`, `generateOrientationPlan`,
  `runACOM`, `applyACOMDisplay`) to `App/AppState+ACOM.swift`.
- **Readers:** 8 UI files — the widest of the four; the build lists them.
- **Stop condition specific to this seam:** any `acom*` property that
  `ReplayPlan`/`SessionReplay` reads for the recipe — repoint, and add a line
  to `ReplayPlanTests` if the name appears there.
- **Predicted:** ≈ 4 280 lines.

### 3. `DiskDetectionProduct`

- **Moves:** `diskParams`, `diskDetectionContext`,
  `diskDetectionValidationIssues`, `diskDetectionConfigurationIsValid`,
  `diskDetectionSettingsAreStale`; the 425-line section (probe kernels,
  `detectCurrentPattern`, `performLiveDetection`, `runDiskDetection`,
  `showBraggMap`, `runDiskDisagreement`, `calibratedBraggVectors`) to
  `App/AppState+DiskDetection.swift`.
- **Stays:** `braggVectors` and `braggPeakCount` — a result strain, ACOM and
  export all share; it moves with seam 5.
- **Readers:** 2 UI files; `LearnedDetectionSession` and `DiskCentreLabelStore`
  already exist beside it and are not merged.
- **Predicted:** ≈ 3 850 lines.

### 4. `DPCProduct`

- **Moves:** `dpcDisplay`, `dpcMilliradiansPerDetectorPixel`; the 217-line
  section (`runDPC`, `flipRotation180`, `applyDPCDisplay`) to
  `App/AppState+DPC.swift`. `computeCoMField` stays in
  `AppState+Calibration.swift` (R–Q and DPC share it).
- **Readers:** 2 UI files.
- **Predicted:** ≈ 3 630 lines.

## Attended seams (morning kick-offs, one session each)

Each is its own session brief; paste the quoted line into a fresh session.

### 5. `ResultPresentation` — the shared display derivation

> Run `docs/appstate-seams-plan.md` seam 5 with me present; stop at every
> decision point named in it.

- **Moves:** the 18 `display*` and 8 `result*` properties (`displayedProduct`,
  `displayedResultImage/RGBA/Name/Kind/ValueUnits/Colormap/RangeLo/RangeHi/
  Gamma/Version/PixelMetadata`, `displayedQualityField`, `displayRangeLo/Hi`,
  `displayedPattern`, `displayName`, `resultImage/RGBA/Version/Colormap/Gamma`,
  the two caches) plus `braggVectors`/`braggPeakCount` and the virtual detector
  pair (`virtualShape`, `virtualDiffractionPattern`); from the Analyses section:
  `showComputedProduct`, `scheduleLiveVirtualDetector`,
  `computeVirtualDiffraction`, `scrubTo`, the aperture/region updates.
- **Why attended:** every analysis mode ends in `apply*Display`, and 5 + 4 UI
  files read the result. A wrong move is a blank map in every workspace.
- **Decision points:** (a) whether `DisplayedProduct` (Session/, exists) is the
  owner or a new `ResultPresentation` wraps it; (b) whether the two caches are
  state or derivation; (c) the ordering of `displayedResultVersion` bumps —
  verified by `SessionReplayAppStateTests` and a drive of all five workspaces.
- **Verification:** unit; `tools/rotation-parity-test` and
  `strain-frame-test` (frame re-expression goes through this state); a drive
  of every workspace with `sim_Au`, scored on the Track B checklist.
- **Predicted:** ≈ 3 100 lines.

### 6. Dataset lifecycle — `DatasetSession`

> Run `docs/appstate-seams-plan.md` seam 6 with me present.

- **Moves:** `datasets`, `datasetPreview`, `datasetEpoch`,
  `datasetLoadingProgress/Status`, `datasetLoadCancellation`,
  `datasetLoadWasCancelled`, `reader`, `fourD`; from Configured open:
  `selectDataset`, `openRecent`, `removeRecent`, `rememberOpenedDataset`,
  `refreshStoredBookmark`, `persistRecoveryPosition`, `reopenLastDataset`.
  `RecentDatasets`, `DatasetResidency`, `LoadedView`, `PendingLoad` already
  exist and become the owner's collaborators, not its contents.
- **Why attended:** `datasetEpoch` is the guard every async publish checks; a
  moved guard that is read before it is bumped publishes a stale result into
  a new dataset. Decision points: who bumps the epoch, and whether `reader`
  and `fourD` (widened today) live in the session or in `LoadedView`.
- **Verification:** unit, `ReplayExecutionTests`, the sidecar bookmark case in
  `open-items.md` (the cdhash residual), a drive: open → switch dataset →
  reopen ignoring sidecar.
- **Predicted:** ≈ 2 700 lines.

### 7. The load pipeline — Configured open (L5), 1 523 lines

> Run `docs/appstate-seams-plan.md` seam 7 with me present, placement first.

- **Step one, placement:** split the section by stage into
  `App/AppState+Open.swift` (`openFileForConfiguration`, preview handler,
  `openDemoFixture`, `openManualPath`, `importCrystalModel`),
  `App/AppState+Promote.swift` (`commitPendingLoad`, `promoteToFullExtent`,
  `discardPendingLoad`) and `App/AppState+Replay.swift`
  (`promoteAndReplayRecipe`, `executeReplay`, `replayRefusal`,
  `executeReplayStep`). Tonight's recipe: verbatim, compiler loop, byte-diff.
- **Step two, owners:** `ReplayRun` and `PendingLoad` exist; the promote stage
  gets `PromotionRun`. Decision points: the L5 configured-open contract
  (`docs/archive/v2/…` L1–L6) is the wire the sidecar and replay depend on —
  no stage boundary moves without `ReplayPlanTests` and
  `SessionReplayTests` naming it.
- **Why attended and last:** this is the code every session starts in;
  Gate B-lite (a second model reads the diagnosis, not the diff) before
  step two.
- **Predicted end state:** `AppState.swift` ≈ 1 200 lines — owners, window,
  publishing, the epoch — and the gate stops reporting it as the largest file.

## Log (appended by the sessions that run this plan)

| Date | Seam | Commit | Gates (log names) | Widenings | Stop reason, if any |
|---|---|---|---|---|---|
| 2026-09-18 | 0 — placement split of Calibration/PhaseContrast | a0ffb2a | build 0; unit 696/0/2=698 (`unit-split-20260918.log`); inventory 0 | 17 | — |
