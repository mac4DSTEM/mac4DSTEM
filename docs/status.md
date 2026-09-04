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
| 2a Prepare sidebar, dataset card and workspace list as one grouped `Form`; Liquid Glass diagnosed (Gate D, refuted independently); workspace holds least | done 2026-09-03, unverified on screen | `FormPolicy`/`NumericField` (`FormControls.swift`) hold the two numbers; the "sidebar fits without scrolling" gate retired for rule 5's width-range gate (`testEverySidebarSurvivesItsWholeColumnRange`, 250/292/600 pt, every workspace and task, attaches review PNGs under `MAC4DSTEM_CAPTURE`); `ColumnMaterialTests` holds rule 3 for the columns and can hold the window for a shell capture (`MAC4DSTEM_HOLD_SECONDS`); the columns stay flat by the OS's design (`open-items.md` (d)) |
| 2b Imaging sidebar | done 2026-09-03 in the same commit (its four-segment picker was the width gate's only failure) | shape and region pickers are menus; presets a pull-down |
| 2c Strain & ACOM (`MapSidebar`, `DiskDetectionControls`, `ACOMControlsView`) | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | `AdvancedDiskDetectionSection` is its own collapsible section; ACOM's engine/Q-scale and result blocks are sections |
| 2d Phase (`PhaseSidebar`) | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | one section per parallax stage, the stage header row carries the stage identifier |
| 2e Results (`ResultsSidebar`); `SidebarTextWidth.swift` deleted | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | Remove is its own row: beside A/B it truncated at 250 pt |
| 3 Both inspectors as grouped Forms, one section per block, thumbnails through `thumbnailCapped()` | done 2026-09-03 (Sonnet agent, gated in the main tree), unverified on screen | `testEveryInspectorSurvivesItsWholeColumnRange` (260/320/600 pt, both inspectors) in `ColumnMaterialTests`; the sidecar's Ignore/Change buttons are two rows |
| 4 The rest of the window: pane badges are words in their colour (the owner's wrapped "Relative" capsule), the welcome workspace on `GroupBox`es with no gradient or wash, the configurator's choices and the export sheet as grouped Forms with sheet bands, the colorbar chip popover as a Form; `WindowPolicy` holds the window's numbers; the rule-4 grep joins `inventory` | done 2026-09-03, unverified on screen (the welcome and the loaded window reviewed from captures of the real app) | alerts were already system alerts; `TaskPrerequisiteChecklist` untouched (its line limits are the #16 fix) |
| 4b Hardening on the running app (the assistant built, launched and captured each change) | done 2026-09-03, **seen on screen by the assistant, not by the owner** | Five defects the gates could not see, below; captions shortened across the configurator, export sheet and ACOM; the duplicate "Detect All Disks" sidebar button deleted (the workspace action already owns it) |
| UI2 — every surface migrated | done 2026-09-04; **owner-driven once, and its findings fixed** | `UI2/` is the whole app in SwiftUI: 20 files, zero references to any view under `UI/`. Contract in `architecture.md` "The UI2 contract"; the shape and the two drive decisions in `decisions.md` (2026-09-04). Launch crash found by driving it and fixed under Gate D (`open-items.md`): `HSplitView` is gone, `UI2PaneSplit` replaces it. The owner's drive then produced eight findings, all fixed in the same session: run action moved to the toolbar's trailing edge with a Cancel-only busy state (the centred one truncated "Cancel" and doubled the status bar's progress); segmented pictogram pickers for direction and both shapes; an accent outline on the pane Imaging's Direction drives; Results' pane no longer offers a scan marker it cannot drive; "Save to Results" offered where the result is produced; the bare folder toolbar icon became the dataset menu the migration dropped; Dataset + Session sections fill the sidebar's foot, promoting the three sidecar-vs-data warnings out of Info. `UI/` is untouched and still the default; `--ui2` selects the rebuild |
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
| `run-tests.sh unit` | **476 passed / 0 failed / 3 skipped, exit 0 — 2026-09-04, UI2 migration tree (full log retained, exit code read directly and not through a `tail` pipe — two earlier runs this session reported `tail`'s status and were withdrawn). Re-run green on the drive-fix tree, after an exit-69 preflight refusal cleared by deleting `ModuleCache.noindex` and 23 stale `DerivedData` husks — 415 MB, the debris `free-space.sh`'s roots still cannot see.** Previously: 476 / 0 / 3, exit 0 — 2026-09-03, step 4b tree (log retained); skips: unmounted-volume probe, S17 quarantine, `TB1StallProbeTests` fixture absent. `ColumnMaterialTests.testTheSideColumnsLeaveTheirMaterialVisible` went red on the source list and is the one gate 4b amended. Two runs before it exited 69 on the 8 GB floor with `free-space.sh` reporting nothing to clear — the debris was this session's own `Logs/Test` and `ModuleCache.noindex`, both outside the script's roots (`open-items.md`) |
| `run-tests.sh scientific` | inside `all` above, 2026-09-03 |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-03, UI2 scaffold tree (live markdown 3 511, cold-start set 716; `UI2ContentView.swift` compiled beside current UI) |
| Xcode scratch build | 0 Swift warnings — UI2 scheme-argument tree, 2026-09-03. `launch_mac_app --ui2 --demo-fixture` was attempted after `get_mac_app_path`, but the helper returned a stale/missing app path |
| `run-tests.sh all` | 2026-09-03, e2284f1 tree: unit 467/0/3 and 43 harnesses green including `real-data-acceptance`; exit 1 at `package-test`, whose literal `2.0` / `1` version assertion the 2.5 / 3 bump turned red — the audit now derives both from the project and passed on the same tree (log retained). Trap: the background task's exit code was 0; the gate's own EXIT line said 1 |

## Handoff (rewritten 2026-09-03, unattended session)

- **Next: the owner's drive of UI2** (table above), which is now the whole
  app and not a slice. Nothing in it has been seen on screen by anyone —
  the assistant built it and gated it, and did not drive it. Every surface
  since step 1 is likewise unseen by the owner. Bugs found in the drive enter through `/diagnose`. The owner's direction
  (2026-09-03): a complete rework of every surface to Apple's standards —
  the app should look and behave as if it shipped with macOS — and nothing
  about releases or tags is considered until it is right. Contract in
  `architecture.md` "Presentation contract"; findings in `open-items.md`
  "The UI rework". The pattern: **navigation is a `List(selection:)` with
  `.listStyle(.sidebar)`; a grouped `Form` is for controls only** (4b —
  rule 2 as written produced zero `List`s in the whole app and no way to
  draw a selection), `LabeledContent`, `NumericField`, labelled `Slider`
  rows, no frames outside `FormPolicy`/`WindowPolicy`.
- **Build, launch, capture, look** — the loop 4b used and the one the
  earlier steps lacked: `open -n <Debug app> --args --demo-fixture`,
  `screencapture -x -o -l <window id>` (per-window needs no consent;
  full-screen raises the picker), `tools/ui-drive/` for synthetic clicks
  and drags. Every 4b defect was found this way with the suite green, and
  none of them was visible to a hosted-layout test: those walk `NSControl`
  subviews, and SwiftUI `Text`, images and custom views are not controls.
  A gate that cannot see text cannot hold a rule about truncation.
- **After the rework.** Four lanes (`open-items.md` header): patches for
  bugs the owner reports (through `/diagnose`) and the known, scoped items;
  the science lane one item at a time — **the origin-fit guard leads**
  (1 px unflagged, radius provenance; Gate B; `open-items.md` "Origin-fit
  gate" (a)), then the ACOM bundle's origin-provenance snapshot, the
  selected-area mask fixture, bullseye disk detection (Gate D), CIF id
  collision, Q-calibration scale, ACOM coverage; a landed number change
  cuts v2.6.0. Features come from `docs/v3-plan.md`, pre-registered first.

## Owed to the owner

- Drive the UI rework when it is complete (step 5). Release and tag are
  parked until then.
- Amend `architecture.md`'s presentation contract: rules 2 and 5 are wrong
  as written (`open-items.md`). No further pass should run against them.
- Decide where the workspace's controls live. 4b left navigation and
  controls sharing the left column, which is the source of both the 250 pt
  wall and the 600 pt sprawl; Xcode, Pages and Keynote put controls right.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format) — neither blocks 7c.
