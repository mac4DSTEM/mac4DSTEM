# 001 — Layering: DSTEMCore/DSTEMSession packages, `package` access, Core never reaches up

Dates: 2026-09-02, 2026-09-03

Status: live

## Decision

`Core/` compiles as the `DSTEMCore` SwiftPM target, `Session/` as `DSTEMSession`,
both consumed by the app target through Swift's `package` access level and the
`SWIFT_PACKAGE_NAME` setting rather than a designed `public` API. The split
lands as a build guard first — the app target keeps compiling the same
sources directly while `Package.swift` also compiles them as `DSTEMCore` from
the shell — so the compiler catches an upward dependency before the access
pass. Package split first, then `ScientificProduct`, then owners, then the
registry, then the Phase split (`docs/archive/v2/v2.5-plan.md` §4).

## Why

`package` makes the boundary real for the compiler at the cost of a
mechanical pass (1 645 modifiers, 96 generated initializers), without the API
design work a `public` surface would need for a second consumer that does not
exist — Core is one module consumed by one app in one repository. The build
guard step earned its place immediately: the compiler found an upward
dependency (`Aperture`) that grep had missed.

## Governs

`Package.swift`, the `DSTEMCore`/`DSTEMSession` target split, `tools/run-tests.sh core`.

## Sources

- 2026-09-02 "Step 2 lands as a build guard first", log line 59
- 2026-09-02 "Consolidation order and scale", log line 42
- 2026-09-03 "`package` access, not `public`, at the Core boundary", log line 66

Evidence: `Package.swift` (verified: defines `DSTEMCore`/`DSTEMSession`
targets); `docs/archive/v2/v2.5-plan.md` (verified present).
