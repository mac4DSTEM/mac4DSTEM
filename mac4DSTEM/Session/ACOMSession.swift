//
//  ACOMSession.swift
//  v2.5 step 6a (2026-09-03): the ACOM analysis's own state — model choice,
//  matching options, custom crystal, display, confidence gate, the plan and
//  map, and the facts of the last run — owned in one observable place (plan
//  §4 "ACOMController"). 7c 4b (2026-09-03, owner): the run functions stay
//  on AppState; this type owns the state and its invalidation, and hands the
//  effects that need the window (scope selection, display refresh, the
//  published product) to AppState through the hooks below — the same seam
//  `StrainProduct.onPresentationChange` uses.
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class ACOMSession {
    /// A different crystal needs a new template plan. Same-value writes are
    /// silent, as the AppState setters they replace were.
    package var modelSelection: CrystalModelSelection = .none {
        didSet { if modelSelection != oldValue { invalidatePlan() } }
    }
    /// CIF files imported this run. Session-local, never persisted.
    package var importedCrystalModels: [CrystalModel] = []
    /// A different scale changes the match, not the plan.
    package var exploratoryScale: Double = 0.01 {
        didSet { if exploratoryScale != oldValue { invalidateResult() } }
    }
    package var backend: ACOMMatchingBackend = .automatic
    package var quality: ACOMQualityPreset = .balanced {
        didSet { if quality != oldValue { invalidatePlan() } }
    }
    /// The scope drives the region selection on the real-space pane, which
    /// is AppState's — every write reaches the hook, as the setter did.
    package var scope: ACOMRunScope = .preview {
        didSet { onScopeChange?(scope) }
    }
    package var regionRadius = 24 {
        didSet { onRegionRadiusChange?(regionRadius) }
    }
    package var regionSelectionActive = false

    // Custom (user-defined) cubic crystal.
    package var customZ: Int = 79 {
        didSet { if customZ != oldValue { invalidatePlan() } }
    }
    package var customStructure: Crystal.CubicStructure = .fcc {
        didSet { if customStructure != oldValue { invalidatePlan() } }
    }
    package var customLatticeA: Double = 4.08 {
        didSet { if customLatticeA != oldValue { invalidatePlan() } }
    }

    /// Every write re-publishes the displayed map, as the setter did.
    package var display: ACOMDisplayMode = .reliability {
        didSet { onDisplayChange?() }
    }
    package var displayIsUserChosen = false
    /// Nil = automatic (10th percentile of matched reliabilities).
    package var reliabilityThreshold: Float? {
        didSet { if reliabilityThreshold != oldValue { onDisplayChange?() } }
    }

    // The plan and the map: heavy, read by the run and display code on the
    // main actor; observation goes through the two flags, as it did on
    // AppState, so a template library never sits inside the observation
    // graph.
    @ObservationIgnored package var orientationPlan: OrientationPlan?
    @ObservationIgnored package var orientationMap: OrientationMap?
    package var hasOrientationPlan = false
    package var hasOrientationMap = false

    // Facts of the last run, read by the footer and the estimates.
    package var lastRunScope: ACOMRunScope?
    package var lastRunQuality: ACOMQualityPreset?
    package var lastRunSemantics: ACOMRunSemantics?
    package var lastMatchedPositionCount: Int?
    package var lastPositionsPerSecond: Double?
    package var lastEndToEndDuration: TimeInterval?

    // Effects that need the window, owned by AppState and wired at its init.
    @ObservationIgnored package var onScopeChange: ((ACOMRunScope) -> Void)?
    @ObservationIgnored package var onRegionRadiusChange: ((Int) -> Void)?
    @ObservationIgnored package var onDisplayChange: (() -> Void)?
    /// The displayed product is AppState's; it clears it when the map goes.
    @ObservationIgnored package var onResultInvalidated: (() -> Void)?

    package init() {}

    package func invalidatePlan() {
        orientationPlan = nil
        hasOrientationPlan = false
        invalidateResult()
    }

    package func invalidateResult() {
        orientationMap = nil
        hasOrientationMap = false
        lastRunScope = nil
        lastRunQuality = nil
        lastRunSemantics = nil
        lastMatchedPositionCount = nil
        onResultInvalidated?()
    }
}
