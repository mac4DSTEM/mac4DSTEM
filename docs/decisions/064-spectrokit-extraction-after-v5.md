# 064 — Standalone EDX (later EELS) moves to SpectroKit, extracted from the v5.0 tag

**Date:** 2026-10-12 · **Status:** accepted (owner; macTEM ADR 003 "SpectroKit", in the macTEM repo) · **Amends:** 052 (where the EDX suite lives after v5.0)

## Context
macTEM, the suite's second app, needs the same standalone EDX machinery mac4DSTEM built for v5.0. Copying it would fork the
science; the owner chose one shared library instead.

## Decisions
1. **SpectroKit** (`github.com/mac4DSTEM/SpectroKit`), a Swift port of exSpy, holds standalone spectroscopy. Modules:
   `SpectroCore` (shared spectrum machinery), `SpectroEDX`, `SpectroEELS` (later). mac4DSTEM and macTEM import it by tagged version.
2. **After the move** mac4DSTEM keeps 4D-STEM and 4D-STEM × spectroscopy correlation, built on SpectroKit; macTEM owns standalone
   EDX/EELS.
3. **Until the v5.0 cut: no freeze.** v5.0 finishes as planned (E1–E6, the Results rows, validation); EDX fixes in-tree are welcome
   and carry into SpectroKit. **No new 4D coupling** in the standalone core — `Core/Spectroscopy/` except `Registration/`,
   `Core/Data/VeloxEMDReader.swift`, `Core/Data/HDF5Types.swift`; a new 4D hook goes behind a seam in the 4D layer.
4. **At the v5.0 cut** those paths freeze to extraction work only, and SpectroKit is extracted from the v5.0 tag with its history.
5. **Naming** for the suite: apps are mac + technique, libraries are domain + Kit, modules carry the library's prefix.

## Consequences
- `CLAUDE.md` carries rule 3 so every session sees it before touching those paths.
- SpectroKit's first backlog item: `VeloxEMDReader` reads a plain Velox `Data/Image` dataset (macTEM ADR 004 D1) — in
  `open-items.md` until SpectroKit has its own tracker.
- The extraction itself is a slot of its own after the v5.0 cut, planned with the repo clean-up (`ROADMAP.md`).
