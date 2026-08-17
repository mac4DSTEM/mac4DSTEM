# mac4DSTEM stabilization roadmap

The current contract is [`docs/v2-scope.md`](docs/v2-scope.md); the frozen v1
contract is [`docs/v1-scope.md`](docs/v1-scope.md). This roadmap is
intentionally short: completed implementation history belongs in Git, and a passing
workflow is not automatically a validated scientific claim.

## Phase status (2026-08-17)

**v1.0.0 is tagged, signed, notarized and public.** What it is:
[`CHANGELOG.md`](CHANGELOG.md). What is still live:
**[`docs/open-items.md`](docs/open-items.md)**.

**Phase 2 was planned 2026-08-17** — priority order, refusal rule and the eight
decisions are in **[`docs/v2-scope.md`](docs/v2-scope.md)**. The active plan is
**[`docs/load-pipeline-plan.md`](docs/load-pipeline-plan.md)**.
The three priorities below are standing and outlive v1.0 — they are how work is
judged, not a task list.

## Version policy (decided 2026-08-17)

Phase name and version number are independent axes: "phase 2" is how much work
it is, semver is about **compatibility**.

- **`v1.1.0`** — the load pipeline L2–L5 (resident cube, crop/bin on open).
  Features, backward compatible.
- **`v2.0.0`** — only if L6's crop/bin provenance changes the session sidecar or
  export format such that `v1.0.0` cannot read them. **Decided at L6, on the
  evidence — not in advance.**
- **`v1.0.x`** — bug fixes, and corrections to claims that have gone stale.

## Current baseline

- Native macOS workflow: Prepare → Image / Map / Reconstruct → Results.
- Source-locked py4DSTEM 0.14.19 scientific/interoperability harnesses.
- Real-data operational acceptance for the current local manifest.
- Hardened, sandboxed, self-contained Release package audit.
- Explicit calibration provenance and task-specific readiness.
- Explicit ACOM material selection and physical versus Exploratory Q-scale semantics.

The aggregate repository claim is only the result of:

```sh
tools/run-tests.sh all
```

A full-codebase review with a sequenced fix/polish plan is recorded in
[`docs/archive/code-review-2026-07-19.md`](docs/archive/code-review-2026-07-19.md). Its four
milestones were executed the same day (correctness fixes, responsiveness and
forgiveness, first-run/polish, result storytelling + tiled I/O overlap); the
doc's execution record lists what remains: the scoped GPU disk-correlation
project (B4), the display-verified visual pass and screenshot set (D3/D7),
and ride-along AppState extractions (C1–C3).

## Priority 1 — scientific interpretation

1. Keep every result's material model, scale, units, interpretation status, quality,
   and validity attached through display, comparison, export, save, and reopen.
2. Add material-specific ground-truth fixtures before claiming validation on a new
   material or point group.
3. Admit any new phase—including WS₂—only through the generic model contract with an
   explicit lattice, atomic basis, symmetry reduction, structure factors,
   expected-orientation fixture, and fit-overlay acceptance. Until then the UI must
   reject that model as unsupported rather than infer it from the dataset.
4. Treat py4DSTEM parity, numerical self-consistency, operational real-data execution,
   and independent experimental validation as separate levels of evidence.

## Priority 2 — product clarity

1. Show only the requirements and controls relevant to the selected task.
2. Keep normal controls compact and place numerical tuning in native disclosure panels.
3. Use persistent result labels—Quantitative, Relative, Exploratory, or Categorical—
   instead of relying on units or transient guidance text.
4. Prefer visible quality diagnostics and fit overlays over success-only status text.

## Priority 3 — incremental architecture

1. Keep `AppState` as the window-level coordinator while extracting cohesive domain
   models, views, persistence components, and controllers behind narrow APIs.
2. Extract only at a green test boundary; do not widen scientific-state mutation access
   merely to reduce line counts. **From 2026-08-17 this is a binding per-stage
   rule, not an aspiration:** every L-stage that touches `AppState` extracts one
   seam before it lands, the extracted type is itself `@Observable`, and
   splitting the file into `extension AppState { }` does not count. Order and
   rationale: `docs/development-process.md` §7.
3. Continue splitting large UI sections into task-owned views and separate rendering,
   session persistence, and HDF5 binding code when those areas next change.
4. Retire frozen-v1 result adapters only after typed `DisplayedProduct` persistence has
   complete compatibility coverage.

## Release-owner actions

- ~~Developer ID signing, notarization, and stapling.~~ **Done 2026-08-14/15** —
  pipeline now in `tools/release/`.
- ~~Clean-account launch~~ **done 2026-08-14**, but **on macOS 27 only**. The
  app has never run on the macOS 14 floor it declares.
- Real acquisitions from at least two instruments before promoting MIB/EMPAD readers
  from Preview.

## Scope rule

**v1 (frozen):** a feature had to close a correctness, reliability,
interoperability, accessibility, or release gap in
[`docs/v1-scope.md`](docs/v1-scope.md), or it was post-v1.

**v2 (from 2026-08-17):** [`docs/v2-scope.md`](docs/v2-scope.md) replaces the
freeze with a **priority order plus a refusal rule** — there is no date to
defend, so a freeze would manufacture a constraint that does not exist. The
order decides what a session picks up. The refusal rule is what actually says
no: *nothing ships that can fabricate a scientific result, no gate is widened to
make something pass, and no claim stands that a reader cannot reproduce.*
