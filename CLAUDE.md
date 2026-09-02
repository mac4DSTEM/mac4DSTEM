# CLAUDE.md — start here

mac4DSTEM: native macOS (Swift / SwiftUI / Metal) 4D-STEM analysis on Apple
Silicon, validated against py4DSTEM at one pinned upstream commit
(`tools/lib/fetch-py4dstem.sh` fetches it into the gitignored `References/`). **v2.0.0 is tagged (2026-09-02)**; `main` is on the v2.5
consolidation train. Rules only here; status and history live elsewhere.

## Read, in this order (the whole set is under 500 lines)

1. `docs/status.md` — what is live now, one table. Every session starts here.
2. `docs/v2.5-plan.md` — the consolidation plan: sequence, rules, decisions owed.
3. `docs/open-items.md` — live defects and debts only, ≤ 12 lines each.
4. `docs/development-process.md` — how work is done, gated and recorded.
5. `docs/architecture.md` — layering, ownership, where files go.
6. `docs/decisions.md` — append-only; why things are the way they are.

History is `docs/archive/` (the v2 chronology under `docs/archive/v2/`).
Consult it for *why*, never for what to do next. Reference docs that are
neither status nor history: `docs/releasing.md`, `docs/dm4-format.md`,
`docs/q-calibration-design.md`, `docs/py4dstem-pipelines.md`.

Skills: `/pickup` takes the next step from `docs/status.md`; `/diagnose` is
Gate D; `/adversarial-review` is Gate B; `/closeout`.

## Hard rules

- Views describe UI only; loading, parsing and compute live in `Core/`.
  `AppState` is the single source of truth until the plan's stores replace it.
- No new stored state in `AppState`: a feature names its owner first. A
  session that touches `AppState` moves one responsibility out of it.
- Anything that changes a scientific number: Gate D (diagnosis, refuting
  observation, predicted outcome, then the experiment) before the fix; an
  independent refuter after; a fixture. The model that wrote the change never
  approves it alone. Review the diagnosis, not the diff.
- Break every new test before trusting it. Do not drive the app during the
  unit gate. Quote test numbers only from a retained log, dated;
  `tools/run-tests.sh` is the only thing that knows the harness count.
- No claim a reader cannot reproduce. The repo is public.
- Do NOT set `ResidencyAdmission.measuredWorkingSetFraction` — nil by
  decision; `.automatic` residency was dropped, not tuned.
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the
  matching `.metal` structs (all 4-byte fields).
- Port deviations from py4DSTEM get an inline `DEVIATION` note.
- Don't add `CODE_SIGNING_ALLOWED=NO` to a build you intend to launch; use
  `tools/run-tests.sh unit` for unsigned XCTest work.
- On-screen verification is the owner driving the app (Track B retired
  2026-09-03). A drawing change is stated as unverified on screen until the
  owner has seen it; a bug report enters through `/diagnose`, never as an
  app change made to satisfy a checklist.
- Docs are part of done. Update `docs/status.md` and `docs/open-items.md` in
  the same commit as the code. Every session nets negative markdown lines or
  says why. No new file without saying why an existing home would not do.
  `AGENTS.md` is generated: run `tools/sync-agents-md.sh` after editing this.
- Commit and push only when asked. Linear `main`.

## Build / test

```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build
tools/run-tests.sh unit | scientific | all | inventory   # inventory = the repo's own review
tools/free-space.sh                                     # exit-69 remedy
```
