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
| 3 | `ScientificProduct`, `ProductPresentation`, `ProductStore`; migrate virtual imaging | |
| 4 | `CalibrationSession` with task-aware readiness | |
| 5 | `OperationCenter` + task registry; live and replay on one path | |
| 6 | ACOM and Strain controllers out of `AppState`; reliability gating | |
| 7 | Phase split; `ContentView` recomposition; inspector follows focus | |
| 8 | Week-eight checkpoint | |

## Last gates

| Gate | Result | Date, tree |
|---|---|---|
| `run-tests.sh unit` | 437 passed / 1 failed / 3 skipped — the failure is the S17 sidebar intermittent (2 of 5 runs on this tree, see `open-items.md`); the extra skip is `TB1StallProbeTests` whose staged WS₂ fixture was absent | 2026-09-03, step 2c tree (retained log) |
| `run-tests.sh scientific` | 42 of 42 harnesses, exit 0 | 2026-09-02, FFT tree `21f3990` |
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
- **Step 3.** Pre-registered in `docs/v2.5-plan.md` §9 (the virtual-imaging
  product path, invariants, negative-control tests to write first). Needs
  the owner's decision on sidecar read/write compatibility (plan §8.1).
- Scratch builds go to the session scratchpad, never the project; the
  unit gate needs ~8 GB free (`tools/free-space.sh`). This Mac had 1–3 GB
  free all night, so `run-tests.sh scientific` refused (exit 69) and the
  harnesses touched by the `Aperture` move were run one by one instead.
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
