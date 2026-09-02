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
| 2 | Package split: `DSTEMCore`, `DSTEMSession`, app | next |
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

## Owed to the owner

- Build, sign and notarize the v2.0.0 DMG from the tag.
- Track B sittings 2–4 (multi-GB/NAS cube; clean account); the bounded
  promote run.
- Decisions listed in `docs/v2.5-plan.md` §8.
