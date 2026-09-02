# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from retained, dated runs. The per-increment log of
2026-09-02/03 is `docs/archive/v2/v2.5-log-2026-09-03.md`.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | **tagged 2026-09-02**, not yet built or notarized | `CHANGELOG.md`; build from the tag per `docs/releasing.md` |

## v2.5 consolidation train (`docs/v2.5-plan.md` §5)

| Step | State | What it left behind |
|---|---|---|
| 0 Gate D + tag | done 2026-09-02 | — |
| 1 Retired target, archive, live docs, inventory in CI | done 2026-09-02 | — |
| 2 Packages `DSTEMCore` (Core/), `DSTEMSession` (Session/), app depends on both, `package` access | done 2026-09-03 | `PendingLoad`, `ProductWorkflow`, `WorkspaceNavigation` stay in App/ (UI or `AnalysisMode`); Xcode compiles a local package as `-package-name` = lowercased directory name |
| 3 One product value (`DisplayedProduct`, `AppState.publishedProduct`) owns pixels, labels, domain, sampling, validity, quality, provenance, origin; every compute and restore site publishes it | done 2026-09-03 as scoped | `resultImage`/`resultRGBA` are read-only views with readers in three UI files; `currentScalarResultMetadata` survives as the Results header's empty-state label; `ScalarResultMap` stays the wire format (plan §8.1 never forced) |
| 4 `CalibrationSession`; one vocabulary (Not set / From file / Measured / … / Not quantitative) and one `Verdict` on every surface | done 2026-09-03 | `AppState` forwards every calibration field until the views read the session (7c) |
| 5 `ProductWorkflow.readiness(for:)` — one answer for the primary action, the checklist and replay; `OperationCenter` owns busy/progress/lifecycle | done 2026-09-03 as scoped | plan §10g owner decisions: parallax/ptychography in the recipe vocabulary; `SessionGates` axis; replay's own refusal wording |
| 6 `ACOMSession`; the IPF map confidence-gated (10th-percentile default, slider on the chip) | done 2026-09-03 | `runACOM`, `runStrainMapping`, `applyACOMDisplay`, the orientation plan/map still on `AppState` |
| 7 Phase split (DPC & iDPC / Parallax / Single-slice ptychography), revisitable stages, inspector follows the task, chip slider | 7a, 7b, 7d done 2026-09-03; 7c done 2026-09-02 except 4b | **7c 4b owed** (owner note below). Landed: the five workspace sidebars (`ResultsSidebar` with the saved-product chooser out of the detail pane, `PrepareSidebar`, `ImageSidebar`, `MapSidebar`, `PhaseSidebar`), `ProductInspector`, `FocusedPane` on `WorkspaceNavigation` claimed by every pane — the inspector renders from it alone; the calibration forwarder block is gone, every reader goes through `calibrationSession`; `ContentView` composes (672 lines), `PreprocessingExportSheet` and the IPF legends in their own files |
| 8 Checkpoint | reached 2026-09-03; re-check owed after 7c | the product is simpler across all five surfaces; `AppState.swift` 5 660 lines after 5b (was 5 708) — the ACOM forwarders (4b) are the next block to go; `ContentView.swift` 672 (was 1 872) |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | 461 passed / 0 failed / 3 skipped, exit 0 — 2026-09-02, 7c slice 6 tree (skips: unmounted-volume probe, S17 quarantine, `TB1StallProbeTests` fixture absent) |
| `run-tests.sh scientific` | 42 started / 42 completed, zero FAIL, exit 0 — `b91f5bb`, 2026-09-03; App/UI-only slices since |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-02, 7c slice 6 tree (live markdown 3 972, cold-start set 944; both below the 2026-09-03 closeout) |
| Xcode scratch build | 0 Swift warnings — 2026-09-02, every 7c slice |
| `run-tests.sh all` | not re-run since 2026-09-01 (the aggregate adds `real-data-acceptance` and `package-test`) |
| Track B (human) | 31 passed / 9 partly / 19 unverified / 1 blocked; **F1.54–F1.60 queued, not driven**; F1.53 open |

## Handoff (rewritten at the 2026-09-03 closeout)

- **Start here — 7c 4b, then step 8's re-check:** plan §11h is done except
  4b, which waits on the owner note below. With that choice made, 4b moves
  `runACOM`/`applyACOMDisplay`/`runStrainMapping` and the orientation
  plan/map, deletes the ACOM forwarder block (`AppState.swift` from `let
  acomSession`), and re-records the §2 metrics (plan §7). `/pickup` takes it.
- **Owed science, in `open-items.md`:** the origin-fit guard returning 1 px
  unflagged (Gate B fix), the imported-CIF id collision, bullseye disk
  detection (Gate D), the origin-fit gate statistic.
- Scratch builds go to the session scratchpad; the unit gate needs ~8 GB
  free; do not drive the app during it.

## Owed to the owner

- **7c 4b, a design call before the move (§11g decision 4):** `runACOM`,
  `applyACOMDisplay` and `runStrainMapping` each reach ~20 `AppState` members
  outside their own state (operation center, `braggVectors` and calibration,
  `resolvedACOMModel`/`generateOrientationPlan`, `datasetEpoch`,
  `recordReplayStep`, `publishProduct`, `presentComputeFailure`, `statusText`):
  inject a host protocol of that size, or keep the runs on `AppState` and
  delete only the side-effect-free forwarders. 4a landed the sidebar half.

- Build, sign and notarize the v2.0.0 DMG from the tag.
- Drive Track B F1.54–F1.59 (this week's visible changes) and F1.53.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format) — neither blocks 7c.
