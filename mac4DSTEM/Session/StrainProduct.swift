//
//  StrainProduct.swift
//  Role: S8's seam (docs/development-process.md §7) — the one owner of the
//        strain analysis product and its run controls. Held by AppState with
//        no forwarding properties; views read `strain.…`.
//
//  What lives here: the retained whole-scan map (#28 — it survives task
//  navigation), the displayed component, the last failure cause (#8), and the
//  reference/basis run controls. What deliberately does NOT live here: the
//  displayed image derivation — `resultImage`/`resultColormap` are shared
//  display state across every analysis mode, so the seam signals presentation
//  changes through `onPresentationChange` and AppState re-derives.
//

import Foundation
import DSTEMCore
import Observation

package enum StrainReferenceMode: String, CaseIterable, Identifiable {
    case wholeScan = "Whole-scan mean"
    case selectedRegion = "Current real-space ROI"
    package var id: String { rawValue }
}

/// Why the last strain run produced nothing.
///
/// Backlog #8: one message used to name two unrelated remedies ("adjust the
/// thresholds in the Bragg panel **or** the reference/basis selection"), which
/// left the user guessing which of two different tasks to go back to. These are
/// genuinely different failures with different fixes, so they are distinguished
/// and each names exactly one control.
package enum StrainFailureCause: Equatable {
    /// Too few peaks per position for any lattice to exist. Detection problem.
    case starvedInput(medianPeaks: Double, emptyPercent: Int)
    /// A healthy peak population that no single lattice explains. Reference or
    /// basis problem.
    case illConditionedBasis

    /// A 2D basis needs the direct beam plus two non-collinear g-vectors, so a
    /// position with fewer than three peaks cannot be indexed at all. A median
    /// below four means at least half the scan is at or under that floor, which
    /// is a detection failure however the reference is chosen. Positions with
    /// no peaks at all are the same problem stated more starkly.
    package static func classify(medianPeaks: Double, emptyPercent: Int) -> StrainFailureCause {
        (medianPeaks < 4 || emptyPercent > 25)
            ? .starvedInput(medianPeaks: medianPeaks, emptyPercent: emptyPercent)
            : .illConditionedBasis
    }
}

package enum StrainBasisMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case manual = "Manual g₁ / g₂"
    package var id: String { rawValue }
}

@Observable
@MainActor
package final class StrainProduct {

    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2c
    package init() {}

    /// The retained whole-scan product. Only `publish`/`clear` may replace it,
    /// so a map can never appear without its failure state being reconciled.
    package private(set) var map: StrainMap?

    /// The displayed component. Selecting one must re-derive the displayed
    /// image, which is AppState's shared display state — hence the callback,
    /// not a direct write into the facade.
    package var component: StrainComponent = .exx {
        didSet { onPresentationChange?() }
    }

    /// Why the last strain run failed, so the Strain panel can offer the one
    /// control that fixes it. Cleared on success and on dataset activation.
    package private(set) var failureCause: StrainFailureCause?

    /// The origin provenance **as it was when this map was computed**, not as
    /// it is when someone presses Save.
    ///
    /// Gate B, 2026-08-28: v2 S13 wrote `origin_reference`,
    /// `origin_fit_residual_px` and the excluded fraction into exports by
    /// reading the LIVE calibration at export time. Compute a strain map
    /// against fitted maps, drag the aperture — which nulls
    /// `calibration.origin` while leaving `strain.map` alone — then export, and
    /// the bundle claimed a residual and an excluded fraction for an origin the
    /// map never used. The reverse was worse: a product computed with no origin
    /// at all, exported after a later Calibrate Origin, carried a full set of
    /// origin-fit keys. Snapshotting at publish is what makes the keys a
    /// statement about the map rather than about the moment of saving.
    package private(set) var originProvenance: [String: String] = [:]

    // Run controls. Deliberately NOT cleared on dataset activation — the
    // pre-seam facade preserved them across activations, and a replayed
    // recipe overwrites them explicitly before running.
    package var referenceMode: StrainReferenceMode = .wholeScan
    package var basisMode: StrainBasisMode = .automatic
    package var g1X: Float = 10
    package var g1Y: Float = 0
    package var g2X: Float = 0
    package var g2Y: Float = 10

    /// Installed once by AppState; both sides hold weakly-captured state
    /// (the `DatasetResidency` callback shape).
    @ObservationIgnored package var onPresentationChange: (() -> Void)?

    /// The manual basis exactly as `StrainMapping.compute` takes it, or nil
    /// when the automatic (consensus) basis should re-derive.
    package var manualInitialBasis: (g1: (x: Float, y: Float), g2: (x: Float, y: Float))? {
        basisMode == .manual ? (g1: (x: g1X, y: g1Y), g2: (x: g2X, y: g2Y)) : nil
    }

    /// Publish a computed map. An automatic run adopts its resolved basis into
    /// the manual fields so switching the basis picker to Manual starts from
    /// the lattice that actually fit.
    package func publish(_ newMap: StrainMap, originProvenance: [String: String] = [:]) {
        failureCause = nil
        map = newMap
        self.originProvenance = originProvenance
        if basisMode == .automatic {
            g1X = newMap.refG1.x; g1Y = newMap.refG1.y
            g2X = newMap.refG2.x; g2Y = newMap.refG2.y
        }
    }

    /// Record why the run published nothing. The previous map is retained —
    /// a failed re-run must not destroy the product on screen.
    package func recordFailure(_ cause: StrainFailureCause) {
        failureCause = cause
    }

    /// Dataset activation: the product and the failure state die with the
    /// dataset; the run controls survive (see above).
    package func clear() {
        map = nil
        failureCause = nil
    }
}
