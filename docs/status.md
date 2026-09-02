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
| 7 Phase split (DPC & iDPC / Parallax / Single-slice ptychography), revisitable stages, inspector follows the task, chip slider | 7a, 7b, 7d done 2026-09-03; 7c slices 1–2 done 2026-09-02 | **7c slices 3–6 next** (plan §11h, one commit each). Landed: `ResultsSidebar` (the saved-product chooser, out of the detail pane), `ProductInspector`, `PrepareSidebar`; `FocusedPane` on `WorkspaceNavigation` — Results and Prepare panes claim it, the inspector's Live group renders from it, `nil` (Imaging, Strain & ACOM, Phase) still means the 7b per-task conditions, an adapter that expires at slice 5; no UI file reads a calibration forwarder any more |
| 8 Checkpoint | reached 2026-09-03 | the product is simpler across all five surfaces; `AppState.swift` is not smaller yet (5 700 lines) because ownership moved through forwarders — 7c removes them |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | 459 passed / 0 failed / 3 skipped, exit 0 — 2026-09-02, 7c slice 2 tree (skips: unmounted-volume probe, S17 quarantine, `TB1StallProbeTests` fixture absent) |
| `run-tests.sh scientific` | 42 started / 42 completed, zero FAIL, exit 0 — `b91f5bb`, 2026-09-03; App/UI-only slices since |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-02, 7c slice 1 tree (re-run at closeout) |
| Xcode scratch build | 0 warnings — 2026-09-02, 7c slice 1 tree |
| `run-tests.sh all` | not re-run since 2026-09-01 (the aggregate adds `real-data-acceptance` and `package-test`) |
| Track B (human) | 31 passed / 9 partly / 19 unverified / 1 blocked; **F1.54–F1.60 queued, not driven**; F1.53 open |

## Handoff (rewritten at the 2026-09-03 closeout)

- **Start here — 7c slice 3 (Imaging):** `docs/v2.5-plan.md` §11h lists the
  slices; 1–2 landed. `ImageSidebar` takes the virtual-detector sections out
  of `ContentView`, its panes claim `FocusedPane` (`livePane` gains the
  `.image` case). Then Strain & ACOM (run functions into their sessions, ACOM
  forwarders deleted), Phase (the calibration forwarder block deleted once
  `AppState`'s own reads go through `calibrationSession`), `ContentView` as
  composition only. `/pickup` takes it from this row.
- **Binding traps:** new Core/Session types must be `package` and, if
  constructed from App, carry an explicit `package nonisolated init`; plain
  data structs are `nonisolated`; `private(set)` members need `package
  private(set)`; package imports in App/UI/Session files stay inside
  `#if canImport(DSTEMCore)` because the `tools/` harnesses compile those
  files single-module; the harnesses pass `-package-name mac4DSTEM`.
- **The S17 sidebar intermittent** (`open-items.md`): 810.5pt against 786pt,
  the rows wrapping at the 250pt minimum; not the autosave leak; fires in
  bursts on some trees. Re-run the class; do not widen the test.
- **Owed science, in `open-items.md`:** the origin-fit guard returning 1 px
  unflagged (Gate B fix), the imported-CIF id collision, bullseye disk
  detection (Gate D), the origin-fit gate statistic.
- Scratch builds go to the session scratchpad; the unit gate needs ~8 GB
  free; do not drive the app during it.

## Owed to the owner

- Build, sign and notarize the v2.0.0 DMG from the tag.
- Drive Track B F1.54–F1.59 (this week's visible changes) and F1.53.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format) — neither blocks 7c.
