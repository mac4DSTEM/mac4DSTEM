# Decisions

Append-only. One paragraph per decision: what, why, when. The evidence
behind each lives in `docs/archive/`; this file is the index a reader
checks before re-opening a settled question.

**2026-08-17 — The `AppState` seam rule.** Any stage touching `AppState`
extracts one seam first, at a green test boundary, the extracted type itself
`@Observable`. Splitting into `extension AppState { }` does not count.
Reason: the facade was growing faster than it was being decomposed.

**2026-08-18 — The v2 contract and the three gates.** All-in scope with the
promote run and reduced export; `.automatic` residency dropped, not tuned;
Gate A (review), Gate B (independent refuter for science), Gate D (written
diagnosis and experiment before a fix). Reason: three confident wrong
diagnoses had each passed every test written for them.

**2026-08-31 — W4a merged.** S14 and S15 merged by owner decision.

**2026-09-01 — v2 endgame scope.** All five remaining Group A review
findings ship fixed; the "hand a colleague" and "promote overnight" claims
are discarded; token conservation is a standing directive (lower-tier models
when safe, terse docs, heavy gates only for science). S22 (UX overhaul)
moved ahead of the fix queue on the owner's "not a good v2" verdict.

**2026-09-02 — Naming.** What exists ships as v2.0. The architecture
consolidation is codenamed v2.5 and releases as v2.x increments. v3 is
reserved for the owner's feature plan and bumps when its first feature lands
on the new legs. Process and architecture docs are version-free.

**2026-09-02 — Tag before ship.** v2.0.0 was tagged on the Gate D closeout
commit so the consolidation could start on `main` without waiting for the
DMG. Release fixes, if any, go on a `release/2.0` branch from the tag.
Major version on the §5 evidence: a v1.0.0 build silently misreads
reduced-view sidecars.

**2026-09-02 — Consolidation order and scale.** Package split first (Core
already imports no UI; one line to move), then `ScientificProduct`, then
owners, then the registry, then the Phase split. Scope is the 12–16 week
foundation, not the full 6–9 month proposal; the HDF5 writer is wrapped,
not decomposed. Full record: `docs/v2.5-plan.md` §4.

**2026-09-02 — Gate ceremony.** Gate D unchanged. Gate B only for changes
that alter a number in Core. Gate A fleets retired in favour of one
reviewer. Track B is a ten-row drive per user-visible slice and the full
checklist once per tag. Session records are commit messages plus one
paragraph here.

**2026-09-02 — The inventory is the review.** `tools/run-tests.sh inventory`
runs at every closeout and in CI. Three independent reviews converged on the
same findings; what drifted was the state, so the state is now checked by
script. No further whole-codebase review passes are commissioned.

**2026-09-02 — Step 2 lands as a build guard first.** `Package.swift`
compiles `Core/` as `DSTEMCore` from the shell while the app target keeps
compiling the same sources directly. Reason: the compiler found an upward
dependency (`Aperture`) that grep had missed, and the guard is worth having
before the `public` API pass that a real target dependency needs. The split
into a dependency (2b) and `DSTEMSession` follow.

**2026-09-03 — `package` access, not `public`, at the Core boundary.** The
app depends on `DSTEMCore` through Swift's `package` access level and the
`SWIFT_PACKAGE_NAME` setting rather than a designed public API. Reason:
Core is one module consumed by one app in one repository; a public surface
would be API design work with no second consumer, while `package` makes
the boundary real for the compiler at the cost of a mechanical pass
(1 645 modifiers, 96 generated initializers). If Core is ever published as
a library, that is the moment to design `public`.

**2026-09-02 — Live doc set.** `CLAUDE.md` (rules), `docs/status.md`,
`docs/v2.5-plan.md`, `docs/open-items.md`, `docs/development-process.md`,
`docs/architecture.md`, this file, plus the reference docs and Track B
checklist. Everything else moved to `docs/archive/v2/` unchanged. The
former `v2.5-contract.md` from the plan's §6 was dropped: the plan is the
contract.
