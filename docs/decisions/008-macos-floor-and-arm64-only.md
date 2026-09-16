# 008 — macOS 14 floor; arm64 only and the artefact proves it

Dates: 2026-09-04, 2026-09-11

Status: live

## Decision

`MACOSX_DEPLOYMENT_TARGET` and `Package.swift`'s `.macOS(.v14)` set the floor
at 14; the published requirement states "macOS 14 or later" (not "26 or
later" as first drafted), because 14–25 is compile-verified even though only
26 is exercised on the dev machine. The release artefact contains exactly one
architecture, `arm64`, and the release path measures that on the built
Mach-O rather than trusting `ARCHS`; `Core/ML/LearnedDiskDetector.swift`'s
`#if !arch(arm64)` `#error` is a build-time refusal, not a silent `#if`.

## Why

Exactly two symbols stood above a 26-only floor, both cosmetic and now
behind `#available`; macOS 13 is not reachable because `@Observable` needs
14. On architecture: the embedded HDF5 stack is arm64-only and the ANE path
uses `Float16`, which does not exist on x86_64 macOS — an Intel slice
compiles but then fails every dataset open, converting a loud build failure
into a silent shipping defect, which is what the universal v2.5.1 build
already was. Project-level `ARCHS`/`EXCLUDED_ARCHS` do not reach the SwiftPM
package targets; a command-line `ARCHS=arm64` does, measured rather than
assumed.

## Governs

`mac4DSTEM.xcodeproj` build settings, `Package.swift`,
`mac4DSTEM/Core/ML/LearnedDiskDetector.swift`'s arch guard, `tools/package-test`.

## Sources

- 2026-09-04 "The macOS floor comes down to 14, and the claim stays at 26", log line 285
- 2026-09-11 "mac4DSTEM ships arm64 only, and the artefact proves it", log line 861
