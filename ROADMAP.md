# mac4DSTEM stabilization roadmap

The feature plan is [`docs/v3-plan.md`](docs/v3-plan.md); live status is
[`docs/status.md`](docs/status.md); the v1 and v2 contracts are archived under
`docs/archive/v2/`. This roadmap is
intentionally short: completed implementation history belongs in Git, and a passing
workflow is not automatically a validated scientific claim.

## Phase status (2026-09-02)

**v2.0.0 is tagged** (`CHANGELOG.md`); the DMG is built from the tag. Live
status is [`docs/status.md`](docs/status.md); the consolidation train is
[`docs/archive/v2/v2.5-plan.md`](docs/archive/v2/v2.5-plan.md), done 2026-09-03. The three priorities below are
standing — they are how work is judged, not a task list.

## Version policy

Semver is about **compatibility**. v2.0.0 is a major because a v1.0.0 build
silently misreads a crop-carrying sidecar rather than refusing it. The
consolidation ships as v2.x increments; v3 is reserved for the feature plan
([`docs/decisions.md`](docs/decisions.md), 2026-09-02).

## Current baseline

- Native macOS workflow: Prepare / Imaging / Strain & ACOM / Phase / Results,
  with rehearse-on-a-view → promote-to-the-full-cube replay.
- Source-locked py4DSTEM 0.14.19 scientific/interoperability harnesses.
- Real-data operational acceptance for the current local manifest.
- Hardened, sandboxed, self-contained Release package audit.
- Explicit calibration provenance and task-specific readiness.
- Explicit ACOM material selection and physical versus Exploratory Q-scale semantics.

The aggregate repository claim is only the result of:

```sh
tools/run-tests.sh all
```

Earlier whole-codebase reviews are in `docs/archive/` (2026-07-19,
2026-08-31); the repo now reviews itself with `tools/run-tests.sh inventory`.

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
5. Direction after v2: propagate uncertainty, not just validity — a
   quantitative result should carry an error bar derived from the fit
   residuals that already exist, under the constraints recorded in
   [`docs/post-v1-ideas.md`](docs/archive/v2/post-v1-ideas.md) (#29 first; a wrongly
   modelled interval is a precise wrong claim).

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
   splitting the file into `extension AppState { }` does not count (rule in
   `CLAUDE.md`; the target ownership model is `docs/architecture.md`).
3. Continue splitting large UI sections into task-owned views and separate rendering,
   session persistence, and HDF5 binding code when those areas next change.
4. Retire frozen-v1 result adapters only after typed `DisplayedProduct` persistence has
   complete compatibility coverage.

## Release-owner actions

- Build, sign, notarize and staple the v2.0.0 DMG from the tag
  (`tools/release/`, `docs/releasing.md`). Signing and the clean-account
  launch were done for v1.0.0 (2026-08-14/15); the declared floor is macOS 26.
- Real acquisitions from at least two instruments before promoting MIB/EMPAD
  readers from Preview.

## Scope rule

**v1 (frozen):** a feature had to close a correctness, reliability,
interoperability, accessibility, or release gap in
[`docs/v1-scope.md`](docs/archive/v2/v1-scope.md), or it was post-v1.

**v2.5 (2026-09-02/03):** [`docs/archive/v2/v2.5-plan.md`](docs/archive/v2/v2.5-plan.md) — no new
science until the ownership seams land; every session nets negative markdown.

**v3:** [`docs/v3-plan.md`](docs/v3-plan.md) — a dependency-ordered feature sequence,
draft; the first feature to land bumps the version to v3.0.

**v2 (2026-08-18 → v2.0.0):** [`docs/v2-release.md`](docs/archive/v2/v2-release.md) was a
release contract again — a claim, five workstreams, a **cut line** naming in
advance which workstreams are severable (so a schedule problem can never argue
for thinning a review gate instead), and the standing **refusal rule**:
*nothing ships that can fabricate a scientific result, no gate is widened to
make something pass, and no claim stands that a reader cannot reproduce.*
