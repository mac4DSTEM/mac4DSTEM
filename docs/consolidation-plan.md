# Consolidation review and plan — 2026-09-07

A read-only review of the app, the learned-detector work and the docs, with
a bounded consolidation plan. Written by an agent on a Linux session that
cannot build, run or see the app; every claim is **source-confirmed** at the
cited line unless marked **reported**. Nothing here is owner-approved until
the owner says so. The earlier review the owner pasted the same day is called
"the earlier review" below. Why a new file: `status.md` is the one live table,
`open-items.md` is ≤ 12-line defects, `v3-plan.md` is features — this spans
all three and proposes changes to each, the way `archive/v2/v2.5-plan.md` did
for the v2.5 train. It archives when §7 holds. This session nets positive
markdown lines by instruction (read-only review); executing §6 C1 nets
≥ 600 lines negative. **Revised the same evening** after the owner pushed
`ml/disk-detector` (`18bb13b`), inverted the runtime decision to Core ML
and decided consolidation-first (`decisions.md`, 2026-09-07). §1 is revised
against that tip; §2a re-verifies the Python side and the runtime swap at
`18bb13b`. **Still owed: the Swift-side claims** (§2 rows 1–3, 5, 8, 10,
and the AI room's own §4-class findings) against `18bb13b` — the C1 session
runs that read-only check first, before anything else.

## 1. First finding, revised the same evening: the work is now on GitHub

When this review began, the remote held `main` (`84b2498`),
`ml/disk-detector` at `e0e0dc8` (+8 commits, Python tooling only) and a dead
`s13-q-calibration` (+0 / −134); none of the Swift the earlier review cites
existed in any pushed ref, and every claim about it was **reported** only.
The owner pushed that evening. `ml/disk-detector` is now `18bb13b`,
**25 commits ahead of `main`, merge-base `84b2498`** (a fast-forward), 74
files, +15 340 / −76 — exactly the tree the earlier review described
(`AppState.swift` 5 819 lines, `decisions.md` 485). By area:
`tools/disk-detector/` (19 files: simulator, trainer, export, checks,
fixture, a run3 with visibility targets), `Core/ML/` (2 files),
`Core/Analysis/Precipitates/` (3), four new `Session/` owners, a sixth
"AI Analysis" workspace (4 new `UI/` files), `docs/ai-ml/` (2), five new
test files, and the removal of the AGPL package. Tags are still `v1.0.0`,
`v2.5.0`, `v2.5.1` — **no `v2.0.0`**, which `CLAUDE.md` and `status.md:13`
called tagged.

What survives of the afternoon finding: for a day the earlier review
described work nobody else could see, which the branch's working method
permits (`v3-plan.md:544-558`) but the plan's own sequencing did not — the
branch went from step 3's "NOT passed" verdict (`status.md:66`, `e0e0dc8`)
to step 4, step 5, precipitates and diffraction groups within the same
day, against `v3-plan.md:537-540` and its own handoff's "finish ONE model
through step 4 before a second prototype". §2 re-verifies the earlier
review's claims against `18bb13b`.

## 2. Verdict on the earlier review

Status is against the pushed tree. Line numbers are the ML worktree's.

| # | Its claim | Status | Note |
|---|---|---|---|
| 1 | Density reaches past `sourceValidity` to the on-screen mask | cannot verify | the code is unpushed; `publishProduct(validityMask:)` exists, so the fix it names is plausible |
| 2 | `PrecipitateProduct` has no `isStale`; `DiffractionGroupsProduct` does | cannot verify | `ProductWorkflow.productState` is the one staleness verdict on `main` (`open-items.md:145`); any new product must enter it |
| 3 | Replay never reads `detector_class` while neighbours refuse | cannot verify | the neighbour pattern is real (`ReplayPlan.swift:650-661`); the finding is plausible and cheap to check once pushed |
| 4 | Train/validation share backgrounds and cubes; `best.pt` selected on them | **confirmed**, understated | `train.py:72,85,139,172-173`; backgrounds from the two evaluation cubes `simulate.py:372-389` vs `evaluate.py:56-57,130-131`. The leak itself is weak (backgrounds are texture-free azimuthal medians, `simulate.py:356-369`); the real defect is that **no test set exists** and the fixture's probe is a training probe (`simulate.py:419-420`, `train.py:57`) |
| 5 | Comparison map matches counts only | cannot verify (Swift) | counts-first is the plan's decision (`v3-plan.md:312-315`) and `evaluate.py:142-146` does match positions; the recommendation stands either way |
| 6 | **"Sharpest defect"**: target amplitude = visibility, so threshold 0.9 discards faint disks by construction; recall 0.963 measured at 0.3 | **refuted here** | `heatmap_target` writes amplitude **1** at every truth centre, extinct 0–2 % reflections included (`simulate.py:166-167,313-325`); no `visibility` symbol exists. The branch's handoff says exactly this (`status.md:77-80`, item b). `0.963` appears nowhere; the figures are 0.967 (classical, and the net after refinement), 0.796/0.82 validation, 1.000 fixture raw — also 1.000 at 0.9 (`status.md:85-87`). If the unpushed tree changed the target, the 0.9 question reopens; the argument as written does not hold |
| 7 | WS₂ "agreement" is both detectors finding the beam | confirmed, not new | the plan's own evidence says so and names normalisation (`v3-plan.md:730-735`); false for run2, where the net proposes 15 spots (`:772-774`). Either way the classical baseline finds one peak per position at every scale, so WS₂ carries no information |
| 8 | `decisions.md:427` cites the median-0 as acceptance evidence | cannot verify | 425 lines here; no such entry |
| 9 | Root cause: precipitates v1 built before the §1.5 design session | consistent | §1 (3) above; `v3-plan.md:35-41,537-540` |
| 10 | AI room: ~255 controls, silent toolbar no-op, no overlays, four blocking ops, discarded failure strings | cannot verify | the room does not exist here. The generic parts are confirmed: no `UndoManager`; the `Advanced` pattern it points to exists. The shipped UI's own findings are §4 |
| 11 | `AppState` 5 819 lines, +280 on the branch; docs +1 219 | partly | 5 593 on `main`; the "nothing moved out" admissions are the repo's own (`status.md:28,29`) |
| 12 | 2.2 GB free against an 8 GB gate floor | consistent | the branch handoff reports 1.75 GB and a `benchmark` gate that could not run (`status.md:110-115`) |

**What it got right that matters:** the validation story has drifted from
the claims; density needs a denominator it can name; a per-object result is
a data-model change and was pre-registered as a design session; the AI room
must join `ProductWorkflow`'s readiness and staleness; the docs grew.

**What it missed, all source-confirmed (detail in §3):**

- the pre-registered 2× throughput gate **failed**, and the plan's
  "Recommended verdict" plus `tools/disk-detector/README.md:125` still say it
  passed on the very commit whose `status.md:66-76` retracts it;
- Core ML is **not slower** than Core AI in the owner's own table
  (`v3-plan.md:679,761-767`), which removes the measured reason for "Core AI
  exclusively, macOS 27 only";
- refinement **rejects nothing** (`evaluate.py:73-91`), so every precision
  figure and "net + refinement" count is undefined;
- `check_export.py` has **no tolerance and cannot fail**;
- the classical correlation is **CPU**, not Metal (`DiskDetection.swift:919-964`;
  no correlation kernel has ever existed under `Shaders/`), so §3a's "one
  extra array the Metal engine already computes" and "leave the GPU free for
  correlation" (`v3-plan.md:133-134,335-336`) rest on a false premise;
- there is **no real ground truth anywhere** — not contaminated, absent;
- nothing about the net is **reproducible from the repo**; and the parity
  environment is py4DSTEM 0.14.17 (`tools/disk-detector/README.md:13`) while
  `fetch-py4dstem.sh:12` pins 0.14.19;
- the AGPL package compiled into every build of `main`, the missing
  `v2.0.0` tag, and the docs drift in §5.

## 2a. Re-verification at `18bb13b` — Python side and the runtime swap

**Closed on the branch since `e0e0dc8`** (each line names the §3 item):

- (1) The target is visibility-scaled: `heatmap_target` takes per-disk
  amplitudes from `disk_visibility` (`simulate.py:236-273,356-373`), so
  extinct disks vanish and §2 row 6's mechanism DOES hold at this tip — the
  earlier review was right about `18bb13b` and wrong only for `e0e0dc8`.
  Three truth rules now coexist: the target's continuous scale, validation's
  visibility ≥ 0.5 (`train.py:91`), evaluation's intensity ≥ 10 %
  (`evaluate.py:156`); "241 accepted for 153 eligible, precision 0.61"
  (`tools/disk-detector/README.md:177-178`) is uninterpretable until one rule
  is chosen.
- (3) Refinement rejects candidates that are not a local correlation maximum
  and suppresses duplicates, on both sides (`evaluate.py:88-128`,
  `DiskDetection.swift:726-773`, `LearnedDiskDetector.swift:257-270`, Gate B
  tests in `LearnedDiskDetectorGateBTests.swift:86-135`).
- (4) Backgrounds keep real texture with the disks masked
  (`simulate.py:404-454`); but the committed CLI (`simulate.py:560-562`)
  still builds the old medians, and no committed command builds the
  `ingredients.npz` the trainer needs (`README.md:146-147`).
- (5a) Evaluation runs the exported `.aimodel` through the Python Core AI
  runtime (`evaluate.py:44-65`); the Swift fixture test binds the same asset
  through the framework at ≥ 98 % agreement (`LearnedDiskDetectorTests.swift:105-153`).
- (7) The ceiling is measured from Swift (`scan-bench/main.swift:32-127`,
  `detectAll` on every core): learned end to end **1.87–1.99×** classical at
  128 px, **2.81×** at the cube's native 250 px with tiling, **~5×** in the
  app on the loaded machine. `decisions.md` (branch) records the owner's
  acceptance "at ≤ 1.9×" with Gate B's correction that this is "the measured
  edge of the ceiling"; the 250-px decision is open (`status.md` tiling row).

**Still open:**

- (2) No hand-labelled truth exists anywhere; training and validation share
  probes and backgrounds (`train.py:70,84`); the fixture's probe is training
  probe 3 (`train.py:60`, `simulate.py:511`). The in-app label tool
  (`Session/DiskLabelStore.swift:32-66`) records a per-position verdict on
  the candidate list, not disk centres, so as built it cannot yield per-disk
  recall or precision; `decisions.md:444` (branch) defers the operating
  threshold to "a frozen hand-labelled bullseye set, later".
- (5b) `check_export.py` is byte-identical to `e0e0dc8`: no tolerance, exit 0
  always — while `docs/ai-ml/README.md:249` states the opposite requirement.
- (6) No count scaling for float cubes on either side; Swift and Python
  normalisation match (`LearnedDiskDetector.swift:118-132`,
  `simulate.py:346-353`).
- (8) Ships at 0.9 (`LearnedDiskDetector.swift:28`,
  `Session/LearnedDetection.swift:36`); every quoted recall/precision
  (0.963 / 0.78) is at 0.3 on simulation (`train.py:95`); the committed record
  `Models/DiskDetector/disk-detector-heatmap-b32.json` quotes those numbers
  for an asset shipped at 0.9 without saying so; "marks every visible disk"
  (`README.md:126`, `v3-plan.md:729,748`) rests on eye-read PNGs and run3's
  own account contradicts it ("missing some faint disks the classical finds").
- Reproducibility: the `.aimodel` (568 KB) and its hash record are committed
  and hash-tested (`LearnedDiskDetectorTests.swift:96-101`); no checkpoint, no
  `.mlpackage` for the shipping weights (run3 used `--skip-coreml`), no
  ingredients builder; the env is still py4DSTEM 0.14.17 against the 0.14.19
  lock.

**The Core ML swap, sized from the code:** 13–15 files, ~300–400 lines —
`Core/ML/LearnedDiskDetector.swift` (~110 lines of Core AI API: `AIModel`,
`InferenceFunction`, `NDArray`, cache retry, `learned_runtime`),
`LearnedDiskDetection.swift`, `Session/LearnedDetection.swift`, the
`AppState.swift` guards and four "needs macOS 27" strings,
`UI/AIAnalysisSettings.swift`, the `@available` and skip lines in three test
files, the 2 826-line Swift fixture regenerated from the Core ML runtime, a
Core ML re-export of run3 (none exists), the record JSON, `scan-bench`
re-measured (its 1.87× is Core-AI-specific) and its `run.sh` flags, and
~40 doc lines. The `.mlpackage` export targets macOS 15
(`export.py:140-146`): gate at `@available(macOS 15, *)` or re-export for 14.

**Owner questions and the owed list on the branch** (`docs/ai-ml/README.md:257-260`,
`status.md` handoff): the drive of the whole room ("Nothing is accepted on
screen"), `run-tests.sh unit`, the P4 reflection overlay, the D4
accessibility crash, recipe replay, the merge with its Gate B campaign; the
picker default, whether Propose computes the Max pattern, the width
convention, the area definition; the 250-px tiling decision.

## 3. The learned disk detector — where the science stands

**Proven on the branch (reproducible by a reader):** the simulator and
fixture discipline — SHA-256 of the patterns, exact sub-pixel Fourier
rendering, port parity of the flat kernel and cross-correlation against the
pinned py4DSTEM to 1e-9, four break modes that must each fail, no real data
committed (`verify_fixture.py:27-79`, `run.sh:17-29`); the one-line
`run-tests.sh:88` change gates exactly that and nothing about the net. Also
real, but only in owner-local logs: a 1.10 M-parameter U-Net trains on MPS,
exports to nine Core AI assets and one Core ML package, and runs on the
Neural Engine at ~0.35 ms per pattern.

**Not established.** Each line invalidates a number the branch quotes.

1. The target teaches the lattice, not the visible disks (§2 row 6); the
   validation metric counts extinct reflections as recall targets
   (`train.py:100-102`, no intensity floor) while `evaluate.py:116` uses a
   0.10·max floor — two definitions of "fixture recall 1.000".
2. Validation is a re-draw from the training generator; no test set.
3. Refinement has no acceptance rule; precision is undefined (§2).
4. Real backgrounds are radial medians — texture-free by construction — so
   the net has never seen the texture it fires on (~65 background proposals
   per real position at 0.3, `v3-plan.md:725-729`).
5. Step 3 numbers came from PyTorch heatmaps, not the exported asset
   (`status.md:84-85`, branch); the asset differs from PyTorch by 4–7× the fp16
   floor with no bound (`check_export.py`).
6. Training patterns are never quantised (`simulate.py:213-218`) while the
   fixture is uint16 and real data are counts; float-normalised cubes (WS₂,
   sum 0.25) make `log1p` linear (`simulate.py:306`) — inference
   normalisation into counts is undefined until step 4.
7. Throughput: the ceiling failed as pre-registered (§2); "22.6 s per
   65 536" is arithmetic from 256 patterns in Python (`check_export.py:132`),
   never a scan. And the correlation channel is not free: the classical
   detector correlates on the CPU (`DiskDetection.swift:919-964`), so
   channel 3 costs the same CPU pass the learned path was meant to spare.
8. Reproducibility: none of the weights, hashes, logs, commands or
   ingredients are in the repo (`v3-plan.md:621-623`, `.gitignore:15`); the
   py4DSTEM the fixture was checked against is 0.14.17, not the 0.14.19 the
   repo pins (`fetch-py4dstem.sh:12`).

**The pre-registered gates, one line each** (`v3-plan.md:584-602`):

| Gate | Stands |
|---|---|
| step 1 — fixture proven and broken before any net | met; the only reproducible item |
| step 2 — asset vs PyTorch "pixel for pixel" | measured, not gated (no tolerance) |
| step 2 — placement read in Xcode/Instruments | not done; inferred from a timing differential |
| step 2 — probe-as-state verified | fails (segfault on load, both runs) |
| step 2/3 — per-scan time vs the 2× ceiling | failed; wrong baseline, corrected to 4–5× over |
| step 3 — recall/precision vs drawn centres | recall on a lattice target; precision meaningless |
| step 3 — vs classical on bullseye and WS₂ | no truth; WS₂ baseline degenerate (one peak per position at every scale, `v3-plan.md:746-748`) |
| step 3 — verdict to `decisions.md` | not written; plan says "earns its place", branch status says "NOT passed" |

**Decisions to re-examine, with the reason in the owner's own evidence.**

- **Runtime: ship Core ML, keep Core AI as the insurance — the inverse of
  the current arrangement** (`decisions.md:418-425`). Same speed in the owner's table, macOS 14+
  (the floor decided 2026-09-04), a runtime stable since 2017, no beta, no
  segfaulting stateful asset, no GPU delegate returning half the peaks
  (`v3-plan.md:684-689`). One runtime that reaches every supported Mac is
  the stupid-simple macOS choice; Core AI can return when 27 ships and a
  measurement, not a direction, says so.
- **The ceiling: restate, do not shrink the net.** The plan itself says the
  ANE argument is power and a free GPU, "the wall-clock win is unproven"
  (`v3-plan.md:326-328`). A candidate stage that runs on demand where the
  classical path fails (bullseye, faint disks) is paid per use; 24 s per
  65 536 is acceptable for an opt-in and unacceptable as the default. Narrowing
  the net to chase a target the plan disowned trades recall for a number.
- **Defer the whole in-graph programme** — top-k, probe-as-state, compute
  streams, correlation-in-graph (`v3-plan.md:447-469`). A `heatmap` asset
  plus CPU peak-picking is one moving part and side-steps two of the three
  recorded defects. Optimise after the detector has earned its place, not
  before.
- **The precipitate chain and every other ANE candidate stay Python-free
  until step 4 lands** — the branch handoff's own recommendation
  (`status.md:98-109`, branch). Three half-features cost more trust than one
  whole one.

**The minimum bar before any UI shows a learned result** (the branch
handoff's item 2 already names the first three):

1. Visibility floor on the target and the same floor in every metric; the
   correlation channel computed from the *measured* probe, not the rendering
   probe; retrain.
2. Real texture in the backgrounds (disks masked out, not radial medians);
   background and probe pools disjoint between training and validation.
3. An acceptance rule and duplicate merge after refinement.
4. **A frozen, hand-labelled real test set** — bullseye plus one other camera,
   ≥ 30 positions, labelled by the owner with a small click tool (C6),
   never used for selection or fine-tuning. This is step 5's labelling tool pulled forward,
   as the handoff proposes; it is also the only thing that can ever make a
   sentence like "marks every visible disk" true.
5. Evaluate the *exported* asset, at one threshold fixed before the run, and
   report recall, precision and n per dataset; `check_export.py` gets a
   tolerance and a non-zero exit.
6. `detectAll` wall clock on the same cube, from the app.
7. An ingredients builder, exact commands and checkpoint/asset hashes in
   the repo — until then every number is **reported**.
8. On the branch, strike the "Recommended verdict" and the README's ceiling
   sentences; the verdict is *not passed*, in the owner's words.

## 4. The app on `main` — is it stupid simple macOS?

**The shell is.** `NavigationSplitView` + `.inspector`, `List(selection:)`
with `.listStyle(.sidebar)`, grouped `Form`/`Section`/`LabeledContent`, five
`ContentUnavailableView`s, one prominent toolbar action, one operation
centre with progress, ETA and Cancel on every whole-scan run, an honest load
indicator, letterboxing and "not a result" labels where the science is not
quantitative (`ContentView.swift:49-66`, `WorkspaceView.swift:86-118,492-514`,
`ProductWorkflow.swift:379-392`). Five workspaces, ⌘1–⌘5, as
`architecture.md:35` says. Layering is real and enforced: no SwiftUI or
AppKit under `Core/` or `Session/`, no `AppState` below `App/`, the package
split plus CI's `core` job make it mechanical; all four Metal struct pairs in
`MetalEngine.swift` match their shaders.

**The panels are not.** Source-confirmed, ordered by harm to a scientist:

1. **Staleness is tracked on one edge only.** `diskDetectionSettingsAreStale`
   (`AppState.swift:476-479`) feeds the one `TaskProductState` verdict; no
   `lastRunSettings` exists for the virtual detector, DPC, parallax or
   ptychography, and no calibration change (origin refit, rotation flip,
   Q/R edit), strain reference or ACOM model change marks a displayed map
   stale (`ProductWorkflow.swift:271-298`). Parameters are not disabled
   mid-run (all 38 `.disabled(isBusy)` sites are Buttons), so a map can land
   already stale against the controls on screen (`AppState.swift:4817`).
2. **Panel buttons bypass the gate the toolbar honours.** "Reconstruct
   Object" and "Prepare Parallax Preview" are `.disabled(isBusy)` only
   (`PhaseSettings.swift:217,245`) while the toolbar needs five calibrations
   (`ProductWorkflow.swift:325-350`); the panel run fails into the status
   strip. "Save to Results" is enabled and then refuses via a modal
   (`WorkspaceView.swift:703-711`, `ResultExport.swift:753`) while Info says
   saving is disabled (`WorkspaceInspector.swift:754`).
3. **Compute errors go to a two-line footer that the next status overwrites,
   with the log hidden by default** (`AppState.swift:2233-2239,2874`,
   `WorkspaceNavigation.swift:134`); policy refusals use the crash alert
   (`ResultExport.swift:753-755,1279-1281`). Four channels, one classifier.
4. **Silent failures:** the ROI-sum pattern's `catch { // Quiet during live
   drag }` with no settle pass (`AppState.swift:3348-3350`); `try?` on the
   sidecar inventory after a save, so "Saved" shows while the Results list
   stays stale (`ResultExport.swift:831,1312,1260`); a failed configurator
   pattern fetch spins forever (`PendingLoad.swift:173`,
   `LoadConfigurator.swift:175-190`); "No preview available" with the reason
   dropped (`AppState.swift:1525,2690`).
5. **Clicking the image rewrites the inspector.** Tapping a pane or scrubbing
   sets `activePane` (`ImagePanes.swift:62,374`, `AppState.swift:3289`),
   which in Imaging swaps the Settings tab between Detector and Region
   (`ImagingSettings.swift:39-83`) — a pane focus model the contract says
   does not exist (`architecture.md:221-225`).
6. **Parameter walls with no exposure rule.** Parallax ≤ 24 flat controls
   across four sections, single-slice ≤ 12 flat (`PhaseSettings.swift:148-397`);
   only 3 of 8 panels have an Advanced group; the whole Prepare readiness
   block is duplicated inside the Export sheet (`ExportSheet.swift:127-341`).
7. **Controls in the wrong column.** Contrast, gamma and four actions in the
   Info tab (`WorkspaceInspector.swift:295-378,706,817`); Change…/Ignore…/
   Apply in the navigation sidebar (`WorkspaceSidebar.swift:346-384`) —
   against contract rule 6 (`architecture.md:228-234`).
8. **No undo, no confirmation** on Remove saved result, Reset Alignment,
   Reset Recommended Settings (`WorkspaceSidebar.swift:431`,
   `PhaseSettings.swift:261`, `MapSettings.swift:316`); zero `UndoManager`.
9. Main-thread work with no progress: `fitParallaxAberrations` inline
   (`AppState.swift:3722-3744`); iDPC FFT integration on every Display
   change (`:4445-4490`); `contrastPixels` recomputed in the Info tab's body
   (`WorkspaceInspector.swift:369`).
10. Un-Mac details already in `open-items.md:255-276` and confirmed: values
    baked into labels ("Gamma, 1.00"), Unicode glyphs where SF Symbols
    exist, `TabView` as a bordered box in a 280 pt inspector, "Reconstruction
    Ready" as a disabled prominent button, ⌘↩ and ⌘R both run, arrow keys
    need a focus the user cannot see. Layout numbers outside `LayoutPolicy`
    (`HistogramView.swift:27`, `ImagePanes.swift:345,349`,
    `PaneOverlays.swift:162-163,951-952`) against contract rule 3; 14 bare
    `.fixedSize()` sites, not the 12 `open-items.md:580` counts, and the
    armed one moved to `ImagePanes.swift:587`.

**Architecture debt, source-confirmed.**

- `AppState.swift` is 5 593 lines, and `Support/ResultExport.swift` is a
  2 031-line `extension AppState` with `import AppKit` that holds the sidecar
  save/load/adopt/remove logic (`:749-1270`) — the real surface is 7 624
  lines. The first `// MARK:` is at line 1463; `activate` is 360 lines
  (`:2326-2686`); the "Calibration" MARK is 500 lines of Phase code
  (`:3568-4069`). Over the last 30 commits touching it: +962/−870, **net
  +92**; 6 of 30 net-negative; the four most recent removed nothing, as
  `status.md:28-29` admits. The rule is waived in the open, not met.
- Five extractions whose owners already exist, lowest risk first:
  fit-verification overlays (`:5478-5593`, a value over a snapshot);
  the cancellable-operation forwarders (`:1125-1231` → `OperationCenter`);
  manual pixel-size setters (`:3176-3268` → `CalibrationSession`);
  presentation caches (`:611-666,1036-1124,1232-1310` → the
  `ProductPresentation` `architecture.md:134` names); the Phase workspace
  (36 vars + `:3568-4069` → a `PhaseSession` on `ACOMSession`'s hook
  pattern). Then `ResultExport`'s sidecar functions into `Session/`.
- Unguarded parity: `ACOMParams` (`ACOMMatching.metal:4-9`) is mirrored in
  `OrientationMatcher.swift:329-334`, outside the file the rule names.
- Hygiene: the AGPL package sits in the app target's Sources build phase on
  `main` (`project.pbxproj:15,49,172,302`) — no shipped build carries it
  (v2.5.1 was built from `a9a0437`, before `eb3ad23`) and `NOTICE` does not
  list it. `ci.yml:45-50,98-110` still exports S17 sidebar attachments for tests
  deleted 2026-09-04. `tools/ui-drive/` drives an `NSSplitView` that no
  longer exists; `stage-tb1-ws2-fixture` and `ui-smoke-test` serve the
  retired Track B; 46 of 55 harness `run.sh` files do not source
  `tools/lib/sources.manifest`, the file created to end that drift class;
  54 `.swift` copies of Core files are tracked under
  `docs/archive/2026-08-31-review/…/source-copy/`; `.agents/skills/` is a
  hand-copy of `.claude/skills/` with no generator. `AGENTS.md` is in sync,
  but `sync-agents-md.sh --check` is invoked by no gate.

## 5. The docs — truth and weight

The doc set is doing real work: the repo's own morning self-correction on the
branch reached five of the six conclusions in §3 before this review did.
But it is heavy and it contradicts itself in places a new session reads
first. Source-confirmed:

- **Weight.** `CLAUDE.md:8` says the six read-first docs are "under 500
  lines"; they are 2 325 on `main` (status 137, v3-plan 639, open-items 680,
  process 141, architecture 303, decisions 425) and 2 558 on the branch. The
  repo's own inventory puts the cold-start set at 1 295 lines
  (`status.md:49`). §3a alone is ~540 lines on `main`, 711 on the branch —
  a planning transcript and an evidence log inside the feature plan, by
  owner instruction (`v3-plan.md:80-83`). `open-items.md` is 680 lines
  against its own "≤ 12 lines each" (`:11-12`), and its last 72 lines
  (`:609-680`, "Working methods that earned their keep") are process, not
  defects. `status.md`'s "one table" is three tables plus a 75-line handoff
  narrative whose rows run 10–20 dense lines.
- **Contradictions a reader hits on day one.**
  - The macOS floor: `architecture.md:247-250` says `26.0` / `.v26` and
    `open-items.md:382-384` says "26.0 in every build configuration", while
    the build, `Package.swift:15`, `README.md:91` and `decisions.md` say 14.
    The `.icns` item (`open-items.md:381-387`) calls its 256 px defect moot
    *because* the floor was 26 — with the floor at 14 the reasoning inverts
    and the item is live again.
  - `README.md:28-40,62-76` is v2.5.0: "New in v2.5.0", 457 unit tests,
    `run-tests.sh all` **exit 1**, "No aggregate exit 0 is claimed", the
    v2.5.0 DMG hash — while `status.md:14,51` says v2.5.1 shipped and `all`
    exited 0 (458/0/0) on 2026-09-04. One of them has to move.
  - `open-items.md:3` calls itself "the only maintained status doc";
    `CLAUDE.md` gives that role to `status.md`.
  - On the branch, `v3-plan.md:778-788` and `tools/disk-detector/README.md:125`
    say the detector is under the ceiling; `status.md:66-87` on the same
    commit says it is not. On `main`, `v3-plan.md:609-611` says the YOLO
    package "is never committed"; it is, in that commit's own tree.
  - `CLAUDE.md:73` lists four lanes; `run-tests.sh:188-200` has seven
    (`core`, `benchmark`, `campaign` undocumented); `architecture.md:256`
    lists five.
  - Eight `AppState` doc comments cite `App/<Seam>.swift` for files now in
    `Session/` (`AppState.swift:128,143,200-220`).
- **Evidence chain.** Every gate count in `status.md:46-51` cites a
  machine-local scratchpad path; nothing a reader can open. CI on `main`
  is the only reproducible record (`ci.yml:72-74`), and `ci.yml:45-50,98-110`
  still exports attachments for tests deleted on 2026-09-04.
- **Public claims that are false or stale today.** `README.md:50` "Bragg
  disks — GPU cross-correlation": no correlation kernel exists or has ever
  existed under `Shaders/`; `detectAll` is CPU `concurrentPerform` over the
  Bluestein FFT (`DiskDetection.swift:919-964`). `README.md:36-37` "14 minutes
  → under 15 seconds": no log in the repo (`tools/disk-correlation-parity/
  README.md:89-90` records 27 s → 5.7 s). `ROADMAP.md:9-16,88-93` still says
  v1.0.0 is the only shipped release, v2.5.0 parked, floor 26. The `v2.0.0`
  tag is claimed in six files (`CLAUDE.md:5`, `status.md:13`,
  `ROADMAP.md:11,88`, `CHANGELOG.md:187`, `releasing.md:11`, `decisions.md`).
  `CITATION.cff`, `CHANGELOG.md` and the project agree on 2.5.1; only
  `README.md` lags. No AI/ML capability is claimed publicly — correct.
- **The pin.** `fetch-py4dstem.sh:12` pins py4DSTEM 0.14.19; the parity
  environment that ran the fixture is 0.14.17 (`tools/disk-detector/README.md:13`,
  `v3-plan.md:626`, branch). The `DEVIATION` notes cite one version, the
  numbers were checked against another.
- **No gate has built `main`'s tree.** The last quoted `unit`/`scientific`
  runs are on `c7e2016` (`status.md:46-47`); `eb3ad23` and six later commits
  changed the project and the plan afterwards, so the CI badge is the only
  evidence for the tree a reader clones.
- **`decisions.md` is not append-only.** 22 lines deleted across five
  commits; three are substantive in-place rewrites — the floor entry
  (`a9a0437`, whose message says it amended rather than rewrote), the DM4
  axis-order entry (`8555803`), MLX → PyTorch (`c2fa3c1`). Either honour the
  header or change it to "amend by appending".
- **`open-items.md` in numbers:** 49 items; 14 over 12 lines; 12 undated;
  5 closed or moot but present (S17, the sidebar-drag fix that "no longer
  exists", the falsified width gate, `.icns`, cross-frame export "not a
  defect"); six stale line pins (`:302,313,322,355,392,443`); the "armed"
  `.fixedSize()` site names a `liveZoom` symbol with zero hits in the tree.
- **Dangling paths.** `py4dstem-pipelines.md`: 18 of 31 references, and
  §9.3 documents a retired workflow as current; `q-calibration-design.md:522,569`
  point at scratchpad pre-registrations; `decisions.md:41` at the pre-archive
  plan path; `v3-plan.md:257-260` on `main` names files that exist only on
  the branch. `status.md`'s handoff header says "rewritten 2026-09-05" over
  09-06 edits, and its tags `v2.5.0`/`v2.5.1` sit one commit past the build
  commits they name (`:14-15`).
- **Trend.** The inventory's live-markdown count went 3 332 (09-03) →
  5 036 (`main`) → 5 269 (branch); "every session nets negative markdown
  lines" (`CLAUDE.md:64`) has held once since 09-03. The "under 500 lines"
  sentence was already false when written on 2026-09-02 (816 then). Reading
  CLAUDE → status → v3-plan → open-items is 1 531 lines on `main`.

## 6. The consolidation plan — bounded, gated, then archived

Rules of the plan, taken from `development-process.md`: one bounded pass,
not a perpetual tidy; one Gate B campaign in flight at a time; the owner's
driving time is the scarce resource; every gate has an exit criterion a
reader can check; this file is archived when §7 holds. **No new model, no
new feature, no new UI room until C4 and C6 have exited.** Session counts
are anchored on the repo's measured cadence (`v3-plan.md:576-582`).

**How it is executed.** `/pickup` with no target takes the first gate whose
exit criterion fails; `status.md`'s handoff names it and each `/closeout`
moves it on. The owner pushes; agents commit when asked and never push. A
feature target is refused until this file is archived (`decisions.md`,
2026-09-07; `CLAUDE.md`; the pickup skill).

**C0 — owner only — CLOSED 2026-09-07** (`decisions.md`, the C0 entry).
(1) Every local branch pushed: `ml/disk-detector` at `18bb13b`. (2)
`free-space.sh --clear` run; the gates' own preflight is the measurement
from here on. (3) Decided: Core ML ships; precipitates, groups and
embeddings paused by consolidation-first; the 250-px ceiling of 2.81×
accepted with a 256-px retrain owed (C6); the AGPL package stays in
history, `main` is not rewritten; no `v2.0.0` tag — the claim is struck in
C1.

**C1 — docs truth, one session, docs only.** Fix every item in §5. Move
§3a's decision transcript, Core AI notes and evidence block to
`docs/archive/v3/learned-detector-2026-09-06.md` verbatim (nothing is lost;
the owner's "forget no info" holds in the archive) and leave a ≤ 60-line
pre-registration in `v3-plan.md`: inputs, target, gates, the bar in §3, the
verdict line "not passed". Move `open-items.md:609-680` into
`development-process.md`. Strike the branch's "Recommended verdict" and the
README ceiling sentence. `README.md` to v2.5.1 with one dated run per
claim, "GPU cross-correlation" gone, the 14-minute figure substantiated or
gone; `ROADMAP.md` to the world after 2026-09-04. `architecture.md` floor to
14; the `.icns` item reopened; the five closed items archived and the six
stale pins fixed; `py4dstem-pipelines.md` §9.3 marked retired;
`CLAUDE.md:73` lists the real lanes and its line claim states the real
number; the `v2.0.0` tag claim struck in all six files (never built,
superseded by v2.5.0); `decisions.md`'s header made
true ("amend by appending") and the three rewritten entries noted as such.
Decide the py4DSTEM reference version once — 0.14.19 as pinned or 0.14.17
as installed — and make `fetch-py4dstem.sh`, the env and the `DEVIATION`
notes agree. Add the eight `Session/` path corrections in `AppState`
comments (comments only). *Exit:* `run-tests.sh inventory` exit 0 with a
retained log; live markdown down ≥ 600 lines; no sentence in a live doc
contradicts another (the list in §5 is the checklist).

**C2 — hygiene, half a session, one build.** Land `e0e0dc8`'s removal of
the YOLO package and its four pbxproj lines on `main`; a `NOTICE` line for
the abTEM/YOLO licence table §3a owes; delete `s13-q-calibration`,
`tools/ui-drive/`, `stage-tb1-ws2-fixture`, `ui-smoke-test`, the
`docs/archive/…/source-copy/` Swift copies (54 files), and `ci.yml:98-110`;
point the 46 harness `run.sh` files at `sources.manifest` (harness-verified:
`scientific` exit 0 before and after); one `sync-agents-md.sh --check` line
in `inventory`; a `.gitignore` rule for `*.mlpackage`, `*.mlmodel`,
`*.aimodel`. Neither Gate D trigger applies. *Exit:* `unit`, `scientific`
and `inventory` exit 0 **on `main`'s current tree** — no quoted gate has
built anything after `c7e2016` — with logs; `git ls-files | grep -c yolov8n`
is 0.

**C3 — the owner's drive, one sitting, before any UI change.** The six
`status.md` rows marked unverified on screen, light appearance, every
divider, the Session context menu's Remove, a cropped save → quit → reopen.
Findings enter through `/diagnose`; nothing is fixed during the sitting.
*Exit:* no row in `status.md` says "unverified on screen"; each finding is
an `open-items.md` entry with a reproducing observation.

**C4 — UI coherence, two to three sessions, presentation only.** The three
simplifications in §4, in order: (a) `ProductWorkflow.readiness` plus
`gates.sidecarRewriteRefusal()` become the *only* enable logic — every
panel run/save button binds to it or is deleted; "Update Image" and
"Reconstruction Ready" go; parameters disable while their run is in flight.
(b) Staleness generalised: each product records the calibration and
parameter signature it was computed with and derives `TaskProductState.stale`
for all seven tasks through the wiring disks already have. (c) One exposure
rule — a py4DSTEM kwarg without a physical unit lives in a default-collapsed
`Advanced` section, in every panel, remembered across visits; contrast,
gamma and the four actions leave Info for Settings; the sidecar actions
leave the sidebar for the Dataset menu; the pane-tap side effect on the
Imaging inspector goes; the four silent failures in §4 (4) reach the status
strip; Remove and the two Resets confirm or undo. Tests broken first; the
owner drives at the end. *Exit:* the owner's drive of every panel with no
new finding of classes 1–8 in §4.

**C5 — a standing rule from C1 on: `AppState` never nets positive.** Replace
"a session that touches `AppState` moves one responsibility out" (waived
four times in a row) with a rule `inventory` can measure: the line count of
`AppState.swift` + `Support/ResultExport.swift` does not grow in any commit
on `main`. One extraction per month, in §4's order: overlays →
`OperationCenter` forwarders → `CalibrationSession` setters →
`ProductPresentation` → `PhaseSession` → the sidecar functions into
`Session/`. Each with a green boundary and a save/reopen test, as the
process doc asks.

**C6 — the detector made honest, on the branch; Python and labels only.**
What §2a leaves open: one truth rule across target, validation and
evaluation; the textured CLI default and an ingredients builder; a tolerance
and a non-zero exit in `check_export.py`; count scaling for float cubes; a
frozen hand-labelled real test set **with disk centres** (a centre mode in
the label tool, or a 50-line click tool in `tools/disk-detector/`), never
used for selection; the exported asset evaluated at the shipped 0.9 on it;
the record JSON and the "marks every visible disk" sentence corrected; the
py4DSTEM version made one; the 256-px retrain the owner accepted the 2.81×
ceiling against (`decisions.md`, C0 entry). The frozen test set is labelled with a 50-line
matplotlib click tool in `tools/disk-detector/`, not app work; the labels
are the owner's data (gitignored) and their SHA-256 and counts are in the
repo. Retrain once (~90 min). Report the *exported* asset at one
pre-declared threshold on the fixture, the validation set, and the real test
set: recall, precision, n — and the classical detector's numbers on the same
test set, so the comparison is against truth, not against each other. Merge
the Python tooling and the corrected §3a to `main` (no Swift). *Exit:* a
table in the archived evidence file with those numbers; `scientific` exit 0
with `disk-detector` gated; the verdict written in `decisions.md`, in the
owner's words, either way.

**C7 — step 4, only if C6's verdict is "adds disks the classical path misses
on the real test set".** Step 4 exists on the branch on Core AI
(`5ca9660`, off by default, macOS 27), so C7 is the Core ML swap sized in
§2a plus a completion, not a build: one Core ML inference class in `Core/`
replacing the Core AI one (decided 2026-09-07), `DetectorClass` in
the detection settings, the asset hash in provenance, replay refusing a
`detector_class` mismatch like `kernel_source`, `prerequisiteItems` and
`guidance` filled in for the new mode, the disagreement map matching
positions as well as counts, labels in the sidecar. Opt-in, off by default,
`heatmap` asset plus CPU peak-picking; no in-graph programme. Gate B
campaign; the drive; v3.0. Four to six sessions, per §3a's own estimate.

**C8 — the unpushed AI-room work, one triage session after C0.** Once
visible: whatever depends on the detector waits for C7; precipitates and
groups wait for the §1.5 design session (`v3-plan.md:35-41`) and re-enter
through it; nothing merges to `main` before. The earlier review's fixes —
density reads `sourceValidity` or refuses; `isStale` on every product;
edge objects counted consistently; discarded failure strings surfaced; the
four blocking operations detached with Cancel — are the acceptance checklist
for that branch, not work to do now.

## 7. Done when

- `main` carries C1, C2 and C4; every live doc sentence is true of the tree
  it sits in; `inventory` exit 0 with a retained log a reader can open (CI).
- The owner has driven the app once end to end and every finding is an open
  item with an observation.
- The learned detector has a verdict in `decisions.md` measured on a real
  hand-labelled test set with the exported asset — passed or not.
- `AppState` + `ResultExport` are smaller than on 2026-09-06 and `inventory`
  fails a commit that grows them.
- Nothing lives only on the owner's machine that a live doc claims.

Then this file moves to `docs/archive/`, and `v3-plan.md` §6's task records
take over — the "once at v3 kickoff" migration the process doc prescribes.

## 8. What this review could not check

No build, no run, no screen (Linux session); every log under
`References/training_runs/` and the owner's scratchpad; whether any number
in `status.md:46-51` is what its log says. The tree itself is no longer a
gap: `18bb13b` is on the remote and §2–§3 read it.
