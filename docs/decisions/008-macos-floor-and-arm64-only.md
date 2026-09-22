# 008 — macOS 27 floor; arm64 only and the artefact proves it

Dates: 2026-09-04, 2026-09-11, 2026-09-22

Status: live

## Decision

`MACOSX_DEPLOYMENT_TARGET` and `Package.swift`'s `.macOS("27.0")` set the
floor at 27 (raised from 14, 2026-09-22 night, owner in chat: "don't care
about older macOS, want it good-looking, simple, future-proof"); the
published requirement states "macOS 27 or later". Every `#available` guard
below 27 was removed the same night (ContentView toolbar, WorkspaceInspector
tab capsule, WorkspaceView ResizePointer). v3.0.0's artefact (floor 14)
stays downloadable for older systems — the raise gates only releases after
it. The release artefact contains exactly one architecture, `arm64`, and the
release path measures that on the built Mach-O rather than trusting
`ARCHS`; `Core/ML/LearnedDiskDetector.swift`'s `#if !arch(arm64)` `#error`
is a build-time refusal, not a silent `#if`.

## Why

The 27 floor buys native toolbar/layout APIs and drops guards nobody
exercised; existing users are unaffected since v3.0.0 stays as it shipped.
On architecture: the embedded HDF5 stack is arm64-only and the ANE path
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
- 2026-09-22 night, owner in chat: floor raised 14 → 27 for native toolbar/layout APIs; v3.0.0 stays downloadable
