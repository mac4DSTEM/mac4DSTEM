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

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | 472 passed / 0 failed / 3 skipped, exit 0 — 2026-09-03 03:29, presentation-pass step 1 tree, second run (the first run's one failure was `testEveryNonQuarantinedWorkspaceSidebarFitsItsColumn`, green alone and on the rerun, with a live Debug instance open: the recorded burst); skips: unmounted-volume probe, S17 quarantine, `TB1StallProbeTests` fixture absent |
| `run-tests.sh scientific` | inside `all` above, 2026-09-03 |
| `run-tests.sh core` (both packages) | exit 0 — `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | exit 0 — 2026-09-03, presentation-pass step 1 tree (live markdown 3 446, cold-start set 687; both below the previous closeout); now also holds presentation contract rule 3 as a grep |
| Xcode scratch build | 0 Swift warnings — every 7c slice, 2026-09-02/03 |
| `run-tests.sh all` | 2026-09-03, e2284f1 tree: unit 467/0/3 and 43 harnesses green including `real-data-acceptance`; exit 1 at `package-test`, whose literal `2.0` / `1` version assertion the 2.5 / 3 bump turned red — the audit now derives both from the project and passed on the same tree (log retained). Trap: the background task's exit code was 0; the gate's own EXIT line said 1 |

## Handoff (rewritten at the 2026-09-03 closeout)

- **Next: the UI rework, step 2 — the Prepare sidebar to `Form`.** The
  owner's direction (2026-09-03, after driving step 1): this is a complete
  rework of every surface to Apple's standards — the app should look and
  behave as if it shipped with macOS — and nothing about releases or tags
  is considered until it is right. Contract in `architecture.md`
  "Presentation contract"; findings in `open-items.md` "The UI rework".
  Step 1 (the chrome) landed 2026-09-03 (`9493242`) and the owner drove
  it: the dividers work. Order from here, one commit each, the owner
  drives every one: **2a** Prepare sidebar + the shared dataset card and
  workspace list as grouped Forms, with the missing Liquid Glass on the
  columns diagnosed first (`/diagnose`, never guessed) and the divider
  holding priorities fixed (content column holds least, as Xcode's
  editor does); **2b–2e** Imaging, Strain & ACOM, Phase, Results; **3**
  both inspectors as Forms, thumbnails capped by rule; **4** the rest of
  the window — pane chips and badges, the welcome workspace cards, the
  configurator and export sheets, alerts — against the same contract;
  **5** the owner's full drive; only then is a release discussed. Each
  step: hosted layout tests at 250 / 292 / 600 pt. `/pickup the UI
  rework` from a fresh session.
- **After the rework.** Four lanes (`open-items.md` header): patches for
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


- Drive each UI-rework step as it lands. Release and tag are parked until
  the rework is complete; nothing else is owed on them.
- The §10g decisions (step 5 residuals) and plan §8 (sidecar wire format) — neither blocks 7c.
