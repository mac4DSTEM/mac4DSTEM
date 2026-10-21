# 070 — The exact-length 2D FFT is ImagoKit's `ImagoCore.FFT2D`, pinned at 0.1.1

> Updated (2026-10-21): the pin is now ImagoKit 0.4.0 (`Package.swift`), not 0.1.0/0.1.1 as written below; `FFT1D` is `ImagoFFT.FFT1D`, and `ParallaxAlignment` keeps its own Float path, marked for deletion at CuboKit 0.7.

**Date:** 2026-10-15 · **Status:** decided 2026-10-15 (prepared by ImagoKit's session; applied here with the unit and scientific suites through the kit and one review) · **Follows:** 064 (the kit pattern)

## Context
`FFT2D` (exact N-point 2D DFT for every size: radix-2, 3, 5 and a general path on vDSP, with an exact Bluestein transform for
the rest) was written in this repository and is the origin of ImagoKit's `ImagoCore.FFT2D`. The kit's copy is the same
arithmetic with `public` where this repository had `package`, and one added protocol conformance (`FFT2DTransform`) with its
`Scalar` typealias; a comparison of the two files' code, ignoring access modifiers and comments, shows no other difference.
The kit's registration (docs/registration-slice-1.md in ImagoKit, section 6) compares it with the apps' code bit for bit on
every planted case. Thirteen analysis files (DPC, disk detection, Friedel origin, origin calibration, the parallax family,
probe kernels, ptychography preparation, single-slice ptychography, rotation calibration, the matrix-DFT correlation) call it.

## Decisions
1. The app's FFT2D source (Core/Compute) is deleted; the thirteen files `import ImagoCore`.
2. ImagoKit is pinned at the exact tag 0.1.0 (commit a4f488b; 0.0.2 had the same FFT2D) in `Package.swift`, the Xcode project and both
   `Package.resolved`; the `ImagoCore` and `ImagoFFT` products are linked (DSTEMCore and the app target). ImagoFilters and
   ImagoAlignment are not used here. A new tag is a deliberate bump, gated like any other change.
3. `tools/lib/sources.manifest` links ImagoCore (`kit_module`) to every group that compiled `FFT2D.swift`, and to `core`.
4. Since 0.1.1 `FFT1D` is `ImagoFFT.FFT1D` (same API, same vDSP radix-2 calls; the app's Core/Compute/FFT1D.swift is deleted; `OrientationPlan`/`OrientationMatcher` import ImagoFFT; `ImagoFFT` is linked beside `ImagoCore`). `ParallaxAlignment`'s own logic is untouched (ImagoKit's alignment slice is unreleased).
5. `FFT2DArbitraryLengthTests` (and the two other tests that build an `FFT2D`) stay as consumer tests of the kit: they use
   only the public API (`init?(nx:ny:)`, `transform`, `fftfreq`, `nextPow2`).

## Consequences
- Numbers: none move (same arithmetic). Registered expectation for the switch: every FFT2D-exercising harness and test
  reproduces to its registered tolerance.
- A first call of a vDSP 1D FFT/DFT size in a process can differ by one Float32 ulp (up to 7.9e-8 of the maximum,
  intermittent; ImagoKit registration-slice-1 amendment 8, Gate D open there). The origin code behaves the same. A harness that
  compares two runs bit for bit may need a warm-up call first.
- ImagoKit is GPL-3.0 from 0.1.1 (BSD-3-Clause before); this application stays GPL-3.0 (NOTICE).
- macTEM's own copy of `FFT2D` (its `copies.manifest` line) goes in macTEM's switch, a separate patch.
