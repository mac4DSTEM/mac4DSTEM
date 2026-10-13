# 064 — Standalone EDX (later EELS) moves to SpectroKit; v5.0 ships on it

**Date:** 2026-10-12 · **Status:** accepted (owner; macTEM ADR 003 "SpectroKit", in the macTEM repo); order amended the same day (macTEM ADR 003 "Order — v5.0 ships on SpectroKit", macTEM commit 862fc21) · **Amends:** 052 (where the EDX suite lives after v5.0)

## Context
macTEM, the suite's second app, needs the same standalone EDX machinery mac4DSTEM built for v5.0. Copying it would fork the
science; the owner chose one shared library instead.

## Decisions
1. **SpectroKit** (`github.com/mac4DSTEM/SpectroKit`), a Swift port of exSpy, holds standalone spectroscopy. Modules:
   `SpectroCore` (shared spectrum machinery), `SpectroEDX`, `SpectroEELS` (later). mac4DSTEM and macTEM import it by tagged version.
2. **After the move** mac4DSTEM keeps 4D-STEM and 4D-STEM × spectroscopy correlation, built on SpectroKit; macTEM owns standalone
   EDX/EELS.
3. **Order (amended 2026-10-12): v5.0 ships on SpectroKit.**
   1. v5.0's features are finished in-tree: cards E1–E6 answered, E1 pooling, the 4D Quantify rows in Results, B*'s
      prerequisites. Until the freeze, **no new 4D coupling** in the standalone core — `Core/Spectroscopy/` except
      `Registration/`, `Core/Data/VeloxEMDReader.swift`, `Core/Data/HDF5Types.swift`; a new 4D hook goes behind a seam in the
      4D layer. EDX fixes there are welcome and carry into SpectroKit.
   2. **Feature-complete freeze** (not the release): those paths take extraction commits only — the remaining 4D seams
      split, the API made `public`. A SpectroKit session extracts from the freeze commit with history, bootstraps the
      library, tags 0.1.0; the owner makes it public.
   3. mac4DSTEM switches to the SpectroKit tag: its 560 EDX tests pass in SpectroKit; mac4DSTEM's unit count drops by
      exactly those test names (the delta stated); the app build and the pre-push hook pass on the tagged import; then the
      in-tree copy is deleted.
   4. The owner's microscope validation (pure-Al thin foil, the alloy composition, the joint GMS run) runs against the app
      built on SpectroKit, so it belongs to SpectroKit and counts for both apps.
   5. Then v5.0 is released.
4. **Why this order.** Not now: the remaining features are the 4D-coupled ones, and building them across two repos while
   cards E1–E6 still decide the seam would make every change a two-repo change. Not after the release: the validation
   would then belong to code that moves afterwards. (The first version of this ADR extracted from the v5.0 tag.)
5. **Naming** for the suite: apps are mac + technique, libraries are domain + Kit, modules carry the library's prefix.

## Consequences
- `CLAUDE.md` carries rule 3 so every session sees it before touching those paths.
- SpectroKit's first backlog item: `VeloxEMDReader` reads a plain Velox `Data/Image` dataset (macTEM ADR 004 D1) — in
  `open-items.md` until SpectroKit has its own tracker.
- The extraction is its own slot after the features and before validation and the release (`ROADMAP.md`).

## Amendment 2026-10-13 — the owner's decisions for SpectroKit's first tag (macTEM ADR 009)
Recorded from macTEM's consumer contract (`spectrokit-consumer-contract-2026-10-12.md` in the macTEM repo's archive); no code now.
- **a. 0.1.0 waits until a room can import and use it:** no `unsafeFlags` in SpectroKit's `Package.swift` (SwiftPM refuses them in a
  versioned dependency; `FitLinearAlgebra` needs them today); the HDF5 lock held per block, not for a whole Velox read; cancel and
  progress on every long call.
- **b. macTEM v1 reads Velox AND GMS DM4 EDS spectrum images.** GMS's beam energy (not read) and absorption (refused) are v1 gaps for
  SpectroKit. Cliff–Lorimer only in v1; ζ stays internal, gated, not public in 0.1.0.
- **c. The staged compute pipeline and its cache stay in each app**; SpectroKit owning them is noted for later.
- **d. Open for the extraction slot to settle** (macTEM's recommendation, not decided): Velox, HDF5 and metadata in SpectroCore; public
  types that collide with macTEM's copies (`DM4Experiment`, `DM4Error`, `displayFileName`); which EDX tests actually move — macTEM
  counts about 140–150 Core-only of ~560, against §3.3's 560, so §3.3's delta is re-measured by test name at the switch, not assumed;
  `Bundle.main` tables; the rsciio `049e7d70` pin, missing from SpectroKit's CLAUDE.md.

