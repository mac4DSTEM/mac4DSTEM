# 067 — SpectroKit builds optimised in the owner's Run: a "Develop" configuration, and `-O` on the unit gate's command line

**Date:** 2026-10-13 · **Status:** decided in S4 (the owner's brief: "decide and record"; overrule on sight) · **Follows:** 064 (S4)

## Context
SpectroKit is a versioned dependency, so its manifest cannot carry `unsafeFlags` and dropped the Debug `-O` that
mac4DSTEM's own packages keep. Xcode builds a package in Debug at `-Onone`, and the EDX hot loops are then about 20×
slower. Measured on the owner's 936 MB Velox file (`SI HAADF 1653 33000 x 20260423.emd`, 500 × 1900 × 4096), through
the app's open path (`SpectrumImageOpener.open(path:kind:)`) in an app-hosted XCTest, three reads each, median:

| How SpectroCore was compiled | read |
|---|---|
| `-configuration Debug` (`-Onone`) | 20.3 s |
| Debug + `SWIFT_OPTIMIZATION_LEVEL=-O` on the xcodebuild command line (`-O`) | 1.02 s |
| a Debug copy named **Develop** (the package in its Release mode, `-O` WMO) | 1.03 s |
| Release (`-O` WMO) | 1.02 s |

Every run loaded `libhdf5.dylib` from the app bundle's `Contents/Frameworks`.

What reaches a package target, measured from the compiler invocation Xcode logs for `SpectroCore`:
- a **project-level** `SWIFT_OPTIMIZATION_LEVEL` does not (still `-Onone`); per-target settings cannot name a package;
- a **command-line** build setting does (`-O`, testability kept);
- the configuration's **name** picks the package's Debug or Release mode, and the rule is undocumented:
  "Debug", "DebugFast" and "Development" gave `-Onone`; "Develop", "Profile" and "Release" gave `-O` WMO.

## Decisions
1. **A `Develop` configuration** (a copy of Debug for the project and both targets: `DEBUG`, the demo fixtures, previews,
   the app target's own `-O`) is the scheme's **Run** configuration, so ⌘R and `xcodebuild … build` build SpectroKit
   and DSTEMCore optimised. Not Release: Release drops the `DEBUG`-only demo spectrum fixture and turns on the hardened
   runtime. Cost: DSTEMCore is whole-module in Develop, so an incremental build after a `Core/` edit is slower.
2. **The unit gate passes `SWIFT_OPTIMIZATION_LEVEL=-O`** (`tools/run-tests.sh unit`), Test action still Debug (tests
   need testability). It also makes the test target `-O`; the app and DSTEMCore already were. ⌘U in Xcode still builds
   SpectroKit `-Onone` (slower EDX tests there).
3. **The pre-push hook refuses a push** when the Run configuration built SpectroCore at `-Onone`, so the day an Xcode
   maps "Develop" differently the hook says so instead of the app quietly getting 20× slower.
4. `@_optimize(speed)` was not retried (SpectroKit S3: no effect at `-Onone`).

## Consequences
- Staying tests that construct SpectroKit values through `package` API use `@testable import SpectroCore` (SE-0386:
  a testable import reaches `package` declarations; 18 files). That works only while the gate builds SpectroKit with
  testing enabled (Debug); a Release test run would not compile them.
- `RegistrationTests`' P5 reads the GMS cube through `SpectrumImageOpener.openGMSEDS(path:)` instead of decoding the
  object's bytes by hand (the byte layout is `package` in 0.1.0); its truth is still the generator's.
