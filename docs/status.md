# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from retained, dated runs.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | **tagged 2026-09-02**, not yet built or notarized | `CHANGELOG.md`; build from the tag per `docs/releasing.md` |

## v2.5 consolidation train (`docs/v2.5-plan.md` §5)

| Step | Content | State |
|---|---|---|
| 0 | Gate D on the crystal-replay log; tag v2.0.0 | **done 2026-09-02** (`96065a2`, `1c00c98`) |
| 1 | Delete retired UI target; archive v2 chronology; live doc set; inventory in CI | **done 2026-09-02** (this commit) |
| 2 | Package split: `DSTEMCore`, `DSTEMSession`, app | **2a done 2026-09-02**: `Package.swift` builds `Core/` as `DSTEMCore`; the two upward refs moved into Core. **2b done 2026-09-03**: the app target depends on the package and no longer compiles `Core/` itself (synchronized-group exceptions); Core declarations are `package` access with generated `package init`s; `SWIFT_PACKAGE_NAME = mac4dstem` on app and test targets; harness compilers pass `-package-name`. **2c done 2026-09-03**: `mac4DSTEM/Session/` (14 files: replay plan/run/record, sidecar locator, gates, calibration frame policy, strain product, Q-calibration run, ACOM workflow, residency, loaded view, recovery, recents, system monitor) is the `DSTEMSession` target; `VirtualShapeMode` moved out of `AppState.swift`. Left in `App/`: `AppState`, `PendingLoad` (touches a UI view), `ProductWorkflow` + `WorkspaceNavigation` (need `AnalysisMode`, SwiftUI). **Step 2 complete.** |
| 3 | `ScientificProduct`, `ProductPresentation`, `ProductStore`; migrate virtual imaging | **3a done 2026-09-03**: negative controls 2 and 3 from plan §9e landed with their fixes — an unknown result kind reports *relative*, never quantitative (`AppState.quantitativeStatus`); a Q size without a unit draws a **px** scale bar, never "1/nm" (`Calibration.diffractionScaleBar`). Plan §3 item 8 partly: one subtitle per workspace, "Measure R–Q Rotation" everywhere, "Log y-axis", "Full cube (f32)" (Track B F1.54). **3b-1 2026-09-03**: `AppState.publishedProduct` — the virtual-detector run publishes one `DisplayedProduct` value at its success site (kind, name, units, status decided there); `displayedProduct` returns it ahead of the legacy field assembly; any write through `resultImage` drops it; control 1 (a stale restored badge cannot relabel a fresh result) is pinned. Assumption stated, reversible: the sidecar wire format (`ScalarResultMap`) is unchanged, so decision §8.1 is not yet forced. **3b-2 done 2026-09-03** (`dcd69fc`): DPC and strain publish through `publishProductFromLegacyFields` (metadata from the compute site's switch, strain with its quality fields); package imports guarded with `canImport` because the harnesses compile UI files single-module. **3b-3** (`d49310a`): export reads `displayedProduct` (adapter step 3). **3b-4** (ACOM every mode, Bragg map) and **3b-5** (parallax; ptychography routes through the strain/ACOM publishers): every live publish site now publishes a product. **3b-6** (`6037837`): the four restore sites publish from the sidecar map. **3b-7** (`8686ec5`): the kind/name/units chain and `currentResultPersistenceMetadata` read the product first. **3b-8** (`02d9317`): the sidecar map is built from the product; the task-switch relabel cache runs only when no product is published. **3b-9 attempted and reverted**: deleting the `navigationResult*` cache broke `ProductWorkflowTests.testNavigationDoesNotRelabelTheVisibleScientificResult` and `…testACOMRegionUsesScanReferenceWithoutReplacingBraggResult`, which write `resultImage` directly — the cache guards the legacy field, so both go together (deletion condition 1). **3c done 2026-09-03**: the product is the ONLY result storage — `resultImage`/`resultRGBA` are computed adapters whose setter publishes a product labelled from the current mode (so all 52 legacy writers and the tests keep working), the `restoredResult*` fields re-publish when set, and the `navigationResult*` cache is deleted. **3d done 2026-09-03**: `DisplayedProduct.origin` (`.computed` / `.restoredFromSidecar`, not persisted) replaces the `restoredResult*` triple, which is deleted with all 36 references; the two tests that set it by hand now publish a restored product. **3e-A/B/C done 2026-09-03** (`58809f9`, `7b4d27f`, `50bc97a`): every compute site publishes through `publishProduct(kind:displayName:valueUnits:payload:)` with its own label — parallax and ptychography in `showParallaxProduct`, the DPC modes in `applyDPCDisplay`, ACOM in `applyACOMDisplay`, strain in `applyStrainDisplay`, the Bragg map in `showBraggMap`; the restore sites publish only through `publishRestoredProduct`. **3f done 2026-09-03**: `resultImage`/`resultRGBA` are read-only views of the product's payload, every nil writer clears `publishedProduct`, the eight test writes publish explicit products. **Step 3 is done as scoped**: one immutable product value owns pixels, kind, units, domain, sampling, validity, quality, provenance and origin; presentation (colormap, window, gamma) stays in its own fields. Residuals: `currentScalarResultMetadata` survives only as the Results header's empty-state label (`ProductWorkspaceViews.currentResultSummary`); the read-only adapters still have readers in `StemImageView`, `DatasetInspector`, `ProductWorkspaceViews`; `ScalarResultMap` remains the wire format (plan §8.1 untouched) |
| 4 | `CalibrationSession` with task-aware readiness | **4a done 2026-09-03**: `Session/CalibrationSession.swift` (@Observable) owns the calibration values, provenance, fit settings, voltage and the readiness report; `AppState` forwards. **4b done 2026-09-03**: one state vocabulary (Not set / From file / Measured / Manual / From session / Mixed / Not quantitative) and one `CalibrationSession.Verdict` (all rows ready AND a usable voltage) rendered by both the dataset card and the readiness checklist; "Core calibrated", "Calibration incomplete", "Calibration is complete", "Missing", "Imported from file", "Measured in app" are gone (Track B F1.55; `calibration-readiness-test` green). Per-task phrasing ("Still needed: …") already exists in `ContentView` and stays. **Step 4 done as scoped.** Residual: `AppState` still forwards every calibration field; the readers move to `calibrationSession` when their views are recomposed (step 7) |
| 5 | `OperationCenter` + task registry; live and replay on one path | **Pre-registered 2026-09-03** in `docs/v2.5-plan.md` §10 (tasks, the eight prerequisite sites, controller-vs-AppState ownership, live-vs-replay differences, negative controls, four owner decisions). **5a done 2026-09-03**: `ProductWorkflow.readiness(for:)` is the one answer to "may this task run" — the header's primary action, the checklist and the replay executor (`AppState.replayRefusal(for:)`, before every replayed run) all ask it; the tools panel's private disk-settings gate joined the list (Track B F1.56). **5b done 2026-09-03**: `Session/OperationCenter.swift` (@Observable) owns `isBusy`, `progress` and the controller; every end of an operation (finish, cancel, dataset reset, the load's explicit `setBusy`) goes through it, so a bare reset can no longer leave the app busy (plan §10c); `AppState` forwards. **Step 5 done as scoped.** Residuals = plan §10g, owner decisions: parallax/ptychography joining the recipe vocabulary; `SessionGates`' quantitative-claim axis staying separate; replay keeping its recipe-voiced refusals for the scale/material checks that have no live equivalent |
| 6 | ACOM and Strain controllers out of `AppState`; reliability gating | **6b done 2026-09-03** (first, being the science-visible item): the IPF-Z map draws positions below a reliability threshold neutral grey — automatic at the 10th percentile of matched reliabilities, overridable through `acomReliabilityThreshold` — and the product's provenance carries `reliability_threshold` and `fraction_above_reliability_threshold` (`OrientationMap.ipfZImage(maskingReliabilityBelow:)`, `reliabilityThreshold(percentile:)`; Track B F1.57; plan §3 item 2). The chip slider is UI work for step 7. **6a done 2026-09-03**: `Session/ACOMSession.swift` (@Observable) owns the ACOM model choice, matching options, custom crystal, display, confidence gate and last-run facts; `AppState` forwards with the old `didSet` effects in its setters. Strain already lives in `Session/StrainProduct.swift`. **Step 6 done as scoped.** Residuals: the run functions (`runACOM`, `runStrainMapping`, `applyACOMDisplay`) and the orientation plan/map are still on `AppState`; they follow the views in step 7 |
| 7 | Phase split; `ContentView` recomposition; inspector follows focus | **7d done 2026-09-03** (first, being independent of the design): the IPF pane's colorbar chip carries a **Confidence gate** slider with the kept fraction and an Automatic reset (Track B F1.57 updated). **Pre-registered** in plan §11. **7a done 2026-09-03**: Phase is three tasks — DPC & iDPC, Parallax, Single-slice ptychography (`AnalysisMode.singleslicePtychography`, own section, own primary action "Reconstruct Object", own dispatch, shared calibration prerequisites); a completed parallax stage keeps its controls; two tests pin the split and that switching tasks clears nothing (Track B F1.58). **7b done 2026-09-03**: the inspector shows the aperture rows and the diffraction histogram only for tasks that show a diffraction pane (`inspectorShowsAperture` / `inspectorShowsDiffractionHistogram`; plan §3 item 7; Track B F1.59). **7c not started — the `ContentView` recomposition** (15 sections into per-workspace views, 23 calibration and 16 ACOM UI reads onto the session types, then the forwarder blocks deleted; plan §11d) — a design slice that needs the owner's decisions in §11g (naming, a Results inspector, `ActivePane`) and eyes on screen after each split. Step 7 is at its checkpoint boundary |
| 8 | Week-eight checkpoint | |

## Last gates

| Gate | Result | Date, tree |
|---|---|---|
| `run-tests.sh unit` | 442 passed / 0 failed / 3 skipped, exit 0 (the skips: unmounted-volume probe, S17 quarantine, `TB1StallProbeTests` with its staged WS₂ fixture absent). The S17 sidebar intermittent showed 2 of 5 runs on the step 2c tree and 0 of 13 since (`open-items.md`) | 2026-09-03, step 3c tree (retained log) |
| `run-tests.sh scientific` | 42 started / 42 completed, zero FAIL, exit 0 (retained log) | 2026-09-03, tree at `dcd69fc`…`d49310a` (Core/, Session/ and the harness-compiled UI file unchanged since) |
| `run-tests.sh all` | green end to end, 44 harnesses | 2026-09-01, DPC-closeout tree; not re-run since |
| `run-tests.sh inventory` | exit 0 | 2026-09-02 |
| Track B (human) | 31 passed / 9 partly / 19 unverified / 1 blocked | owner's final playthrough row F1.53 open |

## Handoff (for the next agent, written 2026-09-02 night)

- **Step 2 is complete.** Traps learned, still binding for anything that
  moves into a package: Xcode compiles a local package with `-package-name` = the package
  directory name lowercased (`mac4dstem`), not the manifest name; a
  `package` struct's memberwise and default inits are internal, so every
  struct constructed outside the module needs an explicit `package init`;
  the harnesses compile Core sources standalone and need `-package-name` too.
- New Core/Session types must be declared `package` or the app cannot see
  them; a `struct` or class constructed from App needs an explicit
  `package init`; `private(set)` members need `package private(set)`.
- **Step 3 is mid-flight** (row above; plan §9 is the pre-registration).
  `AppState.publishedProduct` (a `DisplayedProduct` with an `origin`) is
  the only result storage. `resultImage`/`resultRGBA` are computed
  adapters: a non-nil write publishes a product labelled from the
  per-mode switch `currentScalarResultMetadata` (`publishLegacy`); a nil
  write clears when the product holds that payload kind. `restoredResult*`
  and `navigationResult*` no longer exist. Remaining, in order: convert
  each non-nil writer to `publishProduct(kind:displayName:valueUnits:payload:)`
  with the site's own labels (parallax done via `showParallaxProduct`;
  DPC, ACOM, strain, Bragg map, the four restore sites and 8 test writes
  remain), then delete the switch (condition 2) and the adapters' setters;
  the nil writers become `publishedProduct = nil`. The sidecar wire format
  is unchanged throughout, so plan decision §8.1 is not forced by any of it.
- Scratch builds go to the session scratchpad, never the project; the
  unit gate needs ~8 GB free (`tools/free-space.sh`). The harnesses
  compile Core/Session/UI sources into one module, so package imports in
  those files stay inside `#if canImport(DSTEMCore)`.
- **Not re-run after the `Aperture` move** (their local `Aperture` mirrors
  were removed, compile unverified): the diagnostic runners
  `performance-baseline`, `residency-sweep`, `origin-fit-diagnostics`. Run
  each `tools/<name>/run.sh` when its data is at hand; a red there is a
  leftover stub or a missing `Equatable`, not science.

## Owed to the owner

- Build, sign and notarize the v2.0.0 DMG from the tag.
- Track B sittings 2–4 (multi-GB/NAS cube; clean account); the bounded
  promote run.
- Decisions listed in `docs/v2.5-plan.md` §8.
