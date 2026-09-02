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
| v2.5.0 | **built 2026-09-03 from `b026cd7`**, notarized and stapled (`build/release/mac4DSTEM-2.5.dmg`, SHA-256 `a2db8145…a2dd7`, notary ids in `CHANGELOG.md`); tag and the clean-account launch test owed to the owner | `CHANGELOG.md`, retained pipeline log |

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

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | 467 passed / 0 failed / 3 skipped, exit 0 — 2026-09-03, 7c 4b tree (skips: unmounted-volume probe, S17 quarantine, `TB1StallProbeTests` fixture absent) |
| `run-tests.sh scientific` | inside `all` above, 2026-09-03 |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-03, 7c 4b tree (live markdown 3 970, cold-start set 932; both below the previous closeout) |
| Xcode scratch build | 0 Swift warnings — every 7c slice, 2026-09-02/03 |
| `run-tests.sh all` | 2026-09-03, e2284f1 tree: unit 467/0/3 and 43 harnesses green including `real-data-acceptance`; exit 1 at `package-test`, whose literal `2.0` / `1` version assertion the 2.5 / 3 bump turned red — the audit now derives both from the project and passed on the same tree (log retained). Trap: the background task's exit code was 0; the gate's own EXIT line said 1 |

## Handoff (rewritten at the 2026-09-03 closeout)

- **Start here.** Four lanes (`open-items.md` header): patches v2.5.x for
  bugs the owner reports (through `/diagnose`) and the known, scoped items;
  the science lane one item at a time — **the origin-fit guard leads**
  (1 px unflagged, radius provenance; Gate B; `open-items.md` "Origin-fit
  gate" (a)), then the ACOM bundle's origin-provenance snapshot, the
  selected-area mask fixture, bullseye disk detection (Gate D), CIF id
  collision, Q-calibration scale, ACOM coverage; a landed number change
  cuts v2.6.0. Features come from `docs/v3-plan.md`, pre-registered first.
  `/pickup` with a named target. Nothing since 7c slice 1 has been seen on
  screen.

## Owed to the owner


- Tag `v2.5.0` on `b026cd7` and push it; test the DMG on a clean macOS 26
  account before publishing; drive Results and the inspector, never seen on
  screen since 7c.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format) — neither blocks 7c.
