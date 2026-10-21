# mac4DSTEM

Native macOS 4D-STEM analysis (Swift / SwiftUI / Metal) on the macEM kits, checked against py4DSTEM `f050d207` (0.14.19,
fetched by `tools/lib/fetch-py4dstem.sh` into the gitignored `References/`). Rules: `../CLAUDE.md`. Start with
`docs/status.md` and the task; `ROADMAP.md`, `docs/open-items.md`, `docs/architecture.md` on demand.

## Build and test
```sh
xcodebuild -project mac4DSTEM.xcodeproj -scheme mac4DSTEM -destination 'platform=macOS' build   # Run config: Develop
tools/run-tests.sh unit        # the per-session gate; `core` holds the layering; `inventory` the repo checks
tools/run-tests.sh scientific | all   # nightly only
```
The Run configuration is `Develop`: Xcode maps that name to `-O` for packages; a Debug build runs the kits at `-Onone`,
20x slower (EDX fit 20 s instead of 1 s). Keep the name.

## Kits
Exact tags in `Package.swift` (the truth; the Xcode project and `Package.resolved` follow): SpectroKit + FormatoKit (bump
together; one HDF5 lock, `HDF5Serial`), DiffractoKit, CuboKit, ImagoKit. In development point at `../<Kit>` local paths;
restore exact tags at closeout. Stays in the app on purpose: the learned disk detector (ADR 071), lineage and marks,
selected-area Metal diffraction and the resident cube (until CuboKit has a weighted-pattern Metal kernel).

## Layering
Views describe UI only; loading, parsing and compute live in `Core/` (package `DSTEMCore`, no upward imports).
`AppState` is the composition root; new stored state names its owner first.

## Hazards
- Metal parameter structs in `MetalEngine.swift` stay byte-identical to the `.metal` structs (all 4-byte fields).
- `ResidencyAdmission.measuredWorkingSetFraction` stays nil (ADR 013).
- Don't add `CODE_SIGNING_ALLOWED=NO` to a build you will launch; `tools/run-tests.sh unit` is the unsigned path.
- A drive never writes or clears the clipboard.
- Port deviations from py4DSTEM carry an inline `DEVIATION` note.

## Closeout
Tests green; a `CHANGELOG.md` line if a user can see it; one commit on `main` whose last paragraph is the hand-off.
A change to what the app draws includes a screenshot. Paul pushes with `../macEM-suite/tools/ship.sh`.
