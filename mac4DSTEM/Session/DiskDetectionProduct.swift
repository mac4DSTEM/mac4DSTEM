//
//  DiskDetectionProduct.swift
//  Role: seam 3 (docs/archive/v4/appstate-seams-plan.md) — the one owner of the
//        disk-detection run controls (`diskParams`). Held by AppState as
//        `let diskDetection = DiskDetectionProduct()`, no forwarding
//        properties; views read `diskDetection.…` (via `appState.diskDetection`).
//
//  Moved verbatim out of AppState.swift on 2026-09-18 (the seams plan, seam
//  3): `diskParams` keeps its pre-seam name, type, default value and its
//  `didSet` (the live-overlay refresh).
//
//  What stayed on AppState, and why (the seam rule against logic changes —
//  plan §"Rules for every seam" #2 — means a function that reads AppState-
//  only or another owner's state cannot become a pure method here without
//  changing what it reads):
//  - `diskDetectionContext`, `diskDetectionValidationIssues`,
//    `diskDetectionConfigurationIsValid`, `diskDetectionSettingsAreStale`:
//    all read `descriptor`, `probeKernel` or `calibrationSession`
//    (AppState's own state / another owner's), plus `diskDetection.diskParams`
//    for the two that need it — they are combiners, not forwarders, the same
//    judgement seam 2 used for `acomWorkPositionCount` and its dependents.
//    Left in place in `AppState.swift`, renamed only where they read
//    `diskParams` (now `diskDetection.diskParams`).
//  - `fittedProbeRadius` (private): reads `probeKernel` and
//    `calibrationSession.calibration.probeRadius`, neither of which lives
//    here. Stays a private AppState computed property.
//  - `resetDiskDetectionParams()` / `refreshDiskDefaultsForMeasuredProbe()`:
//    split the same way `ACOMSession.scanSelection(selectedX:selectedY:)`
//    was split in seam 2 — the AppState-only inputs (`descriptor.qy/qx`,
//    `fittedProbeRadius`) are resolved by a same-named AppState wrapper
//    (unchanged call sites elsewhere) that hands them to the pure
//    `reset(qy:qx:probeRadius:)` / `refreshForMeasuredProbe(qy:qx:probeRadius:)`
//    methods below, whose bodies are otherwise byte-identical to the
//    pre-seam functions.
//  - The 425-line probe-kernel/detection functions
//    (`generateProbeKernel`…`calibratedBraggVectors`) move to
//    `App/AppState+DiskDetection.swift` per rule 7 (placement, not an
//    owner): they read `probeKernel`, `currentPeaks`, `braggVectors` and
//    friends, all named to STAY on AppState by the plan.
//
//  `liveDetectionInFlight` / `liveDetectionPending`: the single-flight
//  coalescing flags for `detectCurrentPattern`/`performLiveDetection` (now in
//  `AppState+DiskDetection.swift`). Not named as moving OR staying by the
//  plan — an extension file cannot declare stored properties, so they must
//  live either back on AppState (with a `private` → `internal` widening) or
//  here. Housing them here avoids two of the widenings the other stop
//  condition caps at 5; they read no AppState-only state themselves, only
//  the two Booleans in the coalescing dance, so this is a placement choice
//  rather than a "moves verbatim" one.
//
//  The `diskParams` `didSet` used to call `Task { await
//  detectCurrentPattern() } directly — `detectCurrentPattern()` needs
//  `probeKernel`, `navigation.analysisMode`, `displayedPattern`, none of
//  which this owner holds. Rule 1 forbids deleting or rewriting the
//  observer, so it is relocated into an installable hook
//  (`onParamsChange`), the same seam `PhaseContrastProduct` and
//  `ACOMSession` use for effects that need the window; AppState wires it
//  once in `init()` to the same `Task { await detectCurrentPattern() }` body.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif
import Observation

@Observable
@MainActor
package final class DiskDetectionProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// Installed once by AppState; the live-overlay refresh needs
    /// `probeKernel`/`displayedPattern`/`navigation`, none of which this
    /// owner holds — see the header note above.
    @ObservationIgnored package var onParamsChange: (() -> Void)?

    package var diskParams = DiskDetectionParams() {
        didSet { onParamsChange?() }   // live overlay tracks params
    }

    // MARK: - Single-flight coalescing for the live overlay
    //
    // Moved with `detectCurrentPattern`/`performLiveDetection` conceptually;
    // housed here (not the AppState+DiskDetection.swift extension, which
    // cannot hold stored state) — see header note.
    @ObservationIgnored package var liveDetectionInFlight = false
    @ObservationIgnored package var liveDetectionPending = false

    /// Return every detector control to the same size-aware defaults used
    /// when this dataset was opened — now including the fitted probe radius if
    /// one has been measured since, which is what makes the minimum-spacing
    /// default physically meaningful. `qy`/`qx`/`probeRadius` are the caller's
    /// `descriptor`/`fittedProbeRadius` — the AppState-only inputs this pure
    /// construction needs (the parameterization judgement call `ACOMSession
    /// .scanSelection(selectedX:selectedY:)` made in seam 2).
    package func reset(qy: Int, qx: Int, probeRadius: Float?) {
        diskParams = .detectorAdapted(qy: qy, qx: qx, probeRadius: probeRadius)
    }

    /// Re-derive the disk-detection defaults once a probe radius is known.
    /// `diskParams` is seeded at dataset load, before any calibration has run,
    /// so its minimum spacing is the detector-scaled placeholder rather than a
    /// probe-scaled value. Measuring the probe is what makes the real default
    /// computable — see `DiskDetectionParams.detectorAdapted`, where the
    /// detector-scaled value is shown to suppress the shortest g-vectors on
    /// two of the four training datasets.
    /// Only replaces the spacing if the user has not chosen one: it is
    /// compared against the placeholder's spacing *alone*, not the whole
    /// parameter struct. Whole-struct equality looks safer and is worse — a
    /// user who raises Maximum peaks (a natural response to a doubled yield)
    /// or nudges any unrelated control would then be pinned to the
    /// detector-scaled spacing permanently, with nothing on screen saying why.
    package func refreshForMeasuredProbe(qy: Int, qx: Int, probeRadius: Float?) {
        guard let radius = probeRadius, radius.isFinite, radius > 0 else { return }
        let placeholder = DiskDetectionParams.detectorAdapted(
            qy: qy, qx: qx, probeRadius: nil
        )
        guard diskParams.minPeakSpacing == placeholder.minPeakSpacing else { return }
        diskParams.minPeakSpacing = DiskDetectionParams.detectorAdapted(
            qy: qy, qx: qx, probeRadius: radius
        ).minPeakSpacing
    }
}
