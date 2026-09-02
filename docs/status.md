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
| 2 | Package split: `DSTEMCore`, `DSTEMSession`, app | **2a done 2026-09-02**: `Package.swift` builds `Core/` as `DSTEMCore` (`run-tests.sh core`, CI job); the two upward refs (`AppState.count`, `Aperture`) moved into Core. **2b next**: `DSTEMSession` target from `App/` session types; app target depends on the packages (needs `public` API pass — see handoff below) |
| 3 | `ScientificProduct`, `ProductPresentation`, `ProductStore`; migrate virtual imaging | |
| 4 | `CalibrationSession` with task-aware readiness | |
| 5 | `OperationCenter` + task registry; live and replay on one path | |
| 6 | ACOM and Strain controllers out of `AppState`; reliability gating | |
| 7 | Phase split; `ContentView` recomposition; inspector follows focus | |
| 8 | Week-eight checkpoint | |

## Last gates

| Gate | Result | Date, tree |
|---|---|---|
| `run-tests.sh unit` | 439 passed / 0 failed / 2 skipped, exit 0 | 2026-09-02, `96065a2` (retained log) |
| `run-tests.sh scientific` | 42 of 42 harnesses, exit 0 | 2026-09-02, FFT tree `21f3990` |
| `run-tests.sh all` | green end to end, 44 harnesses | 2026-09-01, DPC-closeout tree; not re-run since |
| `run-tests.sh inventory` | exit 0 | 2026-09-02 |
| Track B (human) | 31 passed / 9 partly / 19 unverified / 1 blocked | owner's final playthrough row F1.53 open |

## Handoff (for the next agent, written 2026-09-02 night)

- **Step 2b.** The app target still compiles `Core/` sources directly; the
  package is a build guard, not yet a dependency. Making the app depend on
  `DSTEMCore` requires a `public` pass over every Core declaration App/UI
  use — mechanical but large; do it with a compile-error loop on a cheap
  model, one directory at a time, `swift build` and `run-tests.sh unit`
  green after each. `DSTEMSession` (calibration, products, recipes, replay,
  operation lifecycle) comes after, from `App/` types that do not import
  SwiftUI.
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
