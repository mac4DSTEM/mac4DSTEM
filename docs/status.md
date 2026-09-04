# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from retained, dated runs. The per-increment log of
2026-09-02/03 is `docs/archive/v2/v2.5-log-2026-09-03.md`.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | tagged 2026-09-02, never built; superseded, the tag stays as the pre-consolidation anchor | `CHANGELOG.md` |
| v2.5.0 | parked (owner, 2026-09-03 late): no release or tag thinking until the UI rework is complete and right. The `df80e8e` build (notarized, `build/release/mac4DSTEM-2.5.dmg`) is superseded, not released | `CHANGELOG.md` |

## v2.5 consolidation train (`docs/archive/v2/v2.5-plan.md` §5) — done

| Step | State | What it left behind |
|---|---|---|
| 0 Gate D + tag | done 2026-09-02 | — |
| 1 Retired target, archive, live docs, inventory in CI | done 2026-09-02 | — |
| 2 Packages `DSTEMCore` (Core/), `DSTEMSession` (Session/), app depends on both, `package` access | done 2026-09-03 | `PendingLoad`, `ProductWorkflow`, `WorkspaceNavigation` stay in App/ (UI or `AnalysisMode`); Xcode compiles a local package as `-package-name` = lowercased directory name |
| 3 One product value (`DisplayedProduct`, `AppState.publishedProduct`) owns pixels, labels, domain, sampling, validity, quality, provenance, origin; every compute and restore site publishes it | done 2026-09-03 as scoped | `resultImage`/`resultRGBA` are read-only views with readers in three UI files; `currentScalarResultMetadata` survives as the Results header's empty-state label; `ScalarResultMap` stays the wire format (plan §8.1 never forced) |
| 4 `CalibrationSession`; one vocabulary (Not set / From file / Measured / … / Not quantitative) and one `Verdict` on every surface | done 2026-09-03 | `AppState` forwards every calibration field until the views read the session (7c) |
| 5 `ProductWorkflow.readiness(for:)` — one answer for the primary action, the checklist and replay; `OperationCenter` owns busy/progress/lifecycle | done 2026-09-03 as scoped | plan §10g owner decisions: parallax/ptychography in the recipe vocabulary; `SessionGates` axis; replay's own refusal wording |
| 6 `ACOMSession`; the IPF map confidence-gated (10th-percentile default, slider on the chip) | done 2026-09-03 | `runACOM`, `runStrainMapping`, `applyACOMDisplay`, the orientation plan/map still on `AppState` |
| 7 Phase split (DPC & iDPC / Parallax / Single-slice ptychography), revisitable stages, inspector follows the task, chip slider | 7a, 7b, 7d done 2026-09-03; 7c done 2026-09-03 | Five workspace sidebars (`ResultsSidebar` with the saved-product chooser out of the detail pane, `PrepareSidebar`, `ImageSidebar`, `MapSidebar`, `PhaseSidebar`), `ProductInspector`, `FocusedPane` on `WorkspaceNavigation` claimed by every pane; the calibration and ACOM forwarder blocks are gone — `ACOMSession` owns the ACOM state, plan, map and their invalidation, with hooks to `AppState` for the window effects; the run functions stay on `AppState` (owner decision 2026-09-03, `decisions.md`) |
| 8 Checkpoint | reached 2026-09-03; re-checked 2026-09-03 after 7c | the product is simpler across all five surfaces. §2 metrics: `AppState.swift` 5 528 → 5 544 lines (ownership left it, the run functions did not — a run layer with an injected host is the next consolidation item, not scheduled), `ContentView.swift` 1 859 → 672, live markdown 9.4 k → 4.0 k lines, cold-start set 944 |

## The UI rework (presentation contract, `architecture.md`) — in progress

| Step | State | What it left behind |
|---|---|---|
| 1 The chrome on the window's ground; dividers grab over 9 pt | done 2026-09-03 (`9493242`), owner-drove it | — |
| 2a Prepare sidebar, dataset card and workspace list as one grouped `Form`; Liquid Glass diagnosed (Gate D, refuted independently); workspace holds least | done 2026-09-03, unverified on screen | `FormPolicy`/`NumericField` (`FormControls.swift`) hold the two numbers; the "sidebar fits without scrolling" gate retired for rule 5's width-range gate (`testEverySidebarSurvivesItsWholeColumnRange`, 250/292/600 pt — deleted with the AppKit shell in `d5786e2`, along with `ColumnMaterialTests`; nothing gates a column's width range today); rule 3 and the `MAC4DSTEM_HOLD_SECONDS` shell capture went with it; the columns stay flat by the OS's design (`open-items.md` (d)) |
| 2b Imaging sidebar | done 2026-09-03 in the same commit (its four-segment picker was the width gate's only failure) | shape and region pickers are menus; presets a pull-down |
| 2c Strain & ACOM (`MapSidebar`, `DiskDetectionControls`, `ACOMControlsView`) | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | `AdvancedDiskDetectionSection` is its own collapsible section; ACOM's engine/Q-scale and result blocks are sections |
| 2d Phase (`PhaseSidebar`) | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | one section per parallax stage, the stage header row carries the stage identifier |
| 2e Results (`ResultsSidebar`); `SidebarTextWidth.swift` deleted | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | Remove is its own row: beside A/B it truncated at 250 pt |
| 3 Both inspectors as grouped Forms, one section per block, thumbnails through `thumbnailCapped()` | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | `testEveryInspectorSurvivesItsWholeColumnRange` (260/320/600 pt, both inspectors) — also gone in `d5786e2`; the sidecar's Ignore/Change buttons are two rows |
| 4 The rest of the window: pane badges are words in their colour (the owner's wrapped "Relative" capsule), the welcome workspace on `GroupBox`es with no gradient or wash, the configurator's choices and the export sheet as grouped Forms with sheet bands, the colorbar chip popover as a Form; `WindowPolicy` holds the window's numbers; the rule-4 grep joins `inventory` | done 2026-09-03, unverified on screen (the welcome and the loaded window reviewed from captures of the real app) | alerts were already system alerts; `TaskPrerequisiteChecklist` untouched (its line limits are the #16 fix) |
| 4b Hardening on the running app (the assistant built, launched and captured each change) | done 2026-09-03, **seen on screen by the assistant, not by the owner** | Five defects the gates could not see, below; captions shortened across the configurator, export sheet and ACOM; the duplicate "Detect All Disks" sidebar button deleted (the workspace action already owns it) |
| UI rebuilt in SwiftUI, and the old one retired | done 2026-09-04 | `UI/` IS the SwiftUI rebuild: the AppKit-hosted window's 32 files are deleted, the `UI2/` folder and the `UI2` type prefix are both gone, and no flag selects a UI. Contract in `architecture.md` "The UI contract", three of its rules pinned by an `inventory` grep (`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`/`import AppKit`, mutation-tested both ways). Shape, drive calls and the retirement in `decisions.md` (2026-09-04). The launch crash is fixed (`PaneSplit`) and gated; its mechanism was refuted here and then DEMONSTRATED later the same day by the status-bar revert below, which made the two probes named at the time moot (`open-items.md`). Cost of the retirement: 27 tests deleted, every one pinning the AppKit column shell; six repointed. Five renames were not bare strips (`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`, `PatternFitOverlay`) — reasons in `architecture.md`. The status bar's elapsed/throughput/ETA was added and REVERTED the same day: its per-second `.fixedSize()` text crashed the app on a real dataset and, in doing so, demonstrated the constraint-loop mechanism that had been refuted-but-unestablished (`open-items.md`) |
| Status bar: elapsed / throughput / ETA, rebuilt in a reserved slot | done 2026-09-04, **unverified on screen** | `LayoutPolicy.operationMetricsWidth` (190 pt, constant) is the slot; the text truncates inside it and never resizes it. `OperationMetricsFormat.line` composes the line for both surfaces. `StatusBarMetricsTests` (4 tests, each broken first) measures the widest line the formatter can produce — an hour elapsed, an hour of ETA, 999.9 units/s — against that constant in the same font. The sibling `status.footer.facts` lost its `.fixedSize()`: it was breaking the same rule already, on every progress update, before the metrics line existed (predicted, not observed). Only a real dataset exercises the one-second tick |
| 5 The owner's full drive | owner | — |

### What 4b changed, and why the gates were green through all of it

| Defect (measured on screen) | Cause | Fix |
|---|---|---|
| Inspector column invisible; its values clipped away | the split view was a passenger in a SwiftUI `VStack` beside the footer and laid out **1730 pt wide in a 1470 pt window** — the inspector's own 260 pt hung off the right edge | the split view is the window's whole content; the status bar moved INSIDE the workspace column (supersedes D2's "stacked under every column") |
| No selection in the tools column | contract rule 2 made it a grouped `Form`, and `Form` has no `selection:` parameter at all | `List(selection:)` + `.listStyle(.sidebar)`, one `SidebarSelection` tag per row; `workspaceButton`/`taskButton` deleted |
| Calibration rows crushed onto one line | `LabeledContent` stacks a multi-element label vertically **only inside a Form**; in a List row it lays out horizontally | `readinessRow` stacks explicitly; `SidebarTextWidth.swift` restored (2e deleted it — the `.sidebar` List still gives rows no width) |
| The column changed colour at the top | two materials: AppKit's `NSGlassEffectView` (full height, behind the titlebar strip) plus the List's own inside the scroll view | `.scrollContentBackground(.hidden)` on the List; `ColumnMaterialTests` now excludes the row-scoped `.selection` capsule and was mutation-tested both ways |
| Previews frozen at 160 pt; "Voltage 200 k" | `thumbnailCapped()`'s height cap won over the column width for square images; `numericFieldWidth` 90 + a unit overran a 250 pt row | cap 160 → 320 (a ceiling, not a size); field 90 → 72, unit `.fixedSize()` |

Also 4b: the output log is toggled from the status bar and its top edge
drags (Xcode's debug-area model), and the Imaging presets are three buttons
drawing the geometry they apply, from `DetectorPreset.radii` itself.

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | **455 passed / 0 failed / 1 skipped, exit 0 — 2026-09-04, status-bar-metrics tree (full log retained; exit code read directly, never through a `tail` pipe): 451 + the four new `StatusBarMetricsTests`.** 452 tests either way: 476/0/3 before the UI retirement, which deleted 27 AppKit-shell tests and gained the WS2 stall probe once its data appeared. Two exit-69 preflight refusals during the session, each cleared by deleting `ModuleCache.noindex` and stale `DerivedData` — debris `free-space.sh`'s roots still cannot see |
| `run-tests.sh scientific` | inside `all` above, 2026-09-03 |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-04, status-bar-metrics tree; the UI contract grep is new and was mutation-tested both ways. Previously: exit 0 — 2026-09-03, UI scaffold tree |
| Xcode scratch build | 0 Swift warnings — UI scheme-argument tree, 2026-09-03. `launch_mac_app --ui2 --demo-fixture` was attempted after `get_mac_app_path`, but the helper returned a stale/missing app path |
| `run-tests.sh all` | 2026-09-03, e2284f1 tree: unit 467/0/3 and 43 harnesses green including `real-data-acceptance`; exit 1 at `package-test`, whose literal `2.0` / `1` version assertion the 2.5 / 3 bump turned red — the audit now derives both from the project and passed on the same tree (log retained). Trap: the background task's exit code was 0; the gate's own EXIT line said 1 |

## Handoff (rewritten 2026-09-04, status-bar-metrics session)

The UI is rebuilt in SwiftUI, the AppKit window is deleted, the `UI2` names are
gone, and the app runs a full disk detection on the 1 GB WS2 cube. Push state
is not recorded here — it went stale twice in two commits; ask git.

**Next, in this order.** `/pickup` takes the first.

1. **Your drive.** Nothing beyond Prepare, Imaging and Strain & ACOM has been
   looked at since the retirement, and the last three sessions have all found
   defects by driving that every gate was green through. Bugs enter via
   `/diagnose`. Worth going at first: Phase's stages, the load configurator's
   crop drags, the Results comparison row, the colorbar popover, and every
   divider — the pane split is hand-built now. **Carry the status bar with
   you**: its elapsed / throughput / ETA is back, in a slot that cannot resize
   (above), and only a real dataset ticks it. Watch that the numbers appear,
   that nothing beside them jumps as they change, and that the app survives
   the whole run — that is the one thing the gates cannot see.
2. **Manual Q and R pixel scale cannot be corrected once entered**
   (`open-items.md`). Small, owner-hit, and a wrong R scale silently rescales
   every real-space axis, scale bar and export.
3. **The four open UI-review findings** (`open-items.md`, "UI review"): the
   pattern min/max rows are not the current position's pattern in
   Mean/Max/ROI mode; the A/B/A−B comparison has no scale; the cursor prints a
   raw Float; staleness has two verdicts across three surfaces.
4. **`PaneSplit` residuals**: the pane header is ~420 pt of `.fixedSize()`
   controls and a pane can be narrower — it clips rather than overprints, but
   the header still needs to compress; and the image floor lapses below 2×
   itself.
5. **Then the science lane, one item at a time, as it always was** — the
   **origin-fit guard leads** (Gate B; `open-items.md` "Origin-fit gate" (a)),
   then the ACOM bundle's origin-provenance snapshot, the selected-area mask
   fixture, bullseye disk detection (Gate D), the CIF id collision,
   Q-calibration scale, ACOM coverage. A landed number change cuts v2.6.0.

**The rule the last session bought the hard way** (`open-items.md`, the
constraint-loop entry): nothing inside a split column may repeatedly change
its own minimum size. `.fixedSize()` on text whose string changes is the
easiest way to do it by accident, and it only shows on a dataset big enough
for an operation to tick. Two sites in the status bar broke it; both are
fixed. **The 12 remaining bare `.fixedSize()` calls in `UI/` are unaudited**
against it — 9 of them in `ImagePanes.swift`, which is the pane-header
residual above.

**Driving, and its two limits.** `open -n <Debug app> --args --demo-fixture`
(no flag selects a UI any more), `screencapture -x -o -l <window id>`
(per-window needs no consent). The app's defaults live in its sandbox
container and TCC blocks writing them, so a remembered tab cannot be preset;
and synthetic keystrokes only land while the window is frontmost. Fastest loop
found: the owner drives, and pastes the crash report — that is how the
constraint-loop mechanism was finally established.

## Owed to the owner

- **Drive the rebuilt app** (above).
- **`FocusedPane` and `InspectorContent` are dead** (`App/WorkspaceNavigation.swift`)
  with a live test: the retired inspector was their only reader. Removing them
  takes a real responsibility off `AppState`'s seam.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format).
