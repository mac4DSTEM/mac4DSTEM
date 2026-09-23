//
//  DiskDetectionProduct.swift
//  Role: the one owner of the disk-detection run controls (`diskParams`).
//        Held by AppState as `let diskDetection = DiskDetectionProduct()`,
//        no forwarding properties; views read `diskDetection.…` (via
//        `appState.diskDetection`). Seam 3 of
//        `docs/archive/v4/appstate-seams-plan.md`.
//
//  A function that reads AppState-only or another owner's state stays on
//  AppState rather than moving here — a combiner across owners is not a
//  forwarder. That covers `diskDetectionContext`, `diskDetectionValidationIssues`,
//  `diskDetectionConfigurationIsValid`, `diskDetectionSettingsAreStale` (read
//  `descriptor`/`probeKernel`/`calibrationSession` plus `diskParams`) and
//  `fittedProbeRadius` (reads `probeKernel` and
//  `calibrationSession.calibration.probeRadius`). `resetDiskDetectionParams()`
//  / `refreshDiskDefaultsForMeasuredProbe()` split instead: an AppState
//  wrapper resolves the AppState-only inputs (unchanged call sites) and hands
//  them to the pure `reset(qy:qx:probeRadius:)` /
//  `refreshForMeasuredProbe(qy:qx:probeRadius:)` below. The probe-kernel/
//  detection functions (`generateProbeKernel`…`calibratedBraggVectors`) live
//  in `App/AppState+DiskDetection.swift` instead, since they read
//  `probeKernel`, `currentPeaks`, `braggVectors` and friends — state the plan
//  keeps on AppState.
//
//  `liveDetectionInFlight` / `liveDetectionPending`: single-flight coalescing
//  flags for `detectCurrentPattern`/`performLiveDetection`
//  (`AppState+DiskDetection.swift`). Housed here, not there, because an
//  extension file cannot declare stored properties.
//
//  `diskParams`'s `didSet` cannot call `detectCurrentPattern()` directly — it
//  needs `probeKernel`, `navigation.analysisMode`, `displayedPattern`, none
//  of which this owner holds — so the observer lives behind an installable
//  hook (`onParamsChange`), the same pattern `PhaseContrastProduct` and
//  `ACOMSession` use for effects that need the window; AppState wires it
//  once in `init()`.
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
    // Paired with `detectCurrentPattern`/`performLiveDetection` in
    // AppState+DiskDetection.swift — see header note.
    @ObservationIgnored package var liveDetectionInFlight = false
    @ObservationIgnored package var liveDetectionPending = false

    /// Return every detector control to the same size-aware defaults used
    /// when this dataset was opened — including the fitted probe radius if
    /// one has been measured since, which is what makes the minimum-spacing
    /// default physically meaningful. `qy`/`qx`/`probeRadius` are the
    /// caller's `descriptor`/`fittedProbeRadius`, the AppState-only inputs
    /// this pure construction needs.
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
