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

    // MARK: - Seam 2 additions (docs/appstate-seams-plan.md)
    //
    // Moved verbatim out of `App/AppState.swift`'s ACOM section (seam 2):
    // the run-throughput measurement, the effective backend, the model-
    // selection refusal text and the effective reliability gate were pure
    // functions of this session's own state and move in unchanged. The scan
    // selection needed `selectedScan.x/y`, which only `AppState` holds — it
    // becomes a method taking those as parameters instead of a computed
    // property, the same parameterization judgement call as
    // `PhaseContrastProduct`'s deviation note. `acomWorkPositionCount` and
    // its dependents (work summary, duration text, the full-scan suggestion)
    // stay AppState computed properties: they also need `descriptor` (rx/ry),
    // which lives on AppState, so moving them here would need AppState to
    // pass in the descriptor on every read for no reduction in AppState's
    // own line count — they are not forwarders, they combine two owners'
    // state, so the "no forwarding properties" rule does not require moving
    // them. Same reasoning keeps `acomScaleSemantics`/`acomScale`/
    // `acomInterpretationLabel` on AppState: they combine `calibrationSession`
    // and this session's `exploratoryScale`.

    /// Facts of the last MEASURED run, used to scale the throughput estimate
    /// below to today's template count. Not part of "facts of the last run"
    /// above because those are about what ran; these are about how fast it
    /// ran, kept private to the estimator.
    @ObservationIgnored package var lastMeasuredTemplateCount: Int?
    @ObservationIgnored package var lastMeasuredBackend: ACOMMatchingBackend?

    /// Automatic is an explicit, inspectable policy rather than a claim that
    /// the GPU is active. Real-data benchmarking may revise this policy, but
    /// the UI always names the backend that will actually execute.
    package var effectiveBackend: ACOMMatchingBackend {
        backend == .automatic ? .cpu : backend
    }

    /// `selectedX`/`selectedY` are the real-space selection AppState owns
    /// (`selectedScan.x/y`) — the one piece `.selectedRegion` needs that this
    /// session does not hold itself.
    package func scanSelection(selectedX: Int, selectedY: Int) -> ACOMScanSelection {
        switch scope {
        case .preview:
            return .preview(maxDimension: 32)
        case .selectedRegion:
            return .square(
                centerX: selectedX, centerY: selectedY,
                radius: regionRadius
            )
        case .fullScan:
            return .full
        }
    }

    /// A full scan this cheap is offered as one click instead of leaving the
    /// user on a 32×32 preview. Measured motivation: sim_Au's full 84×100 scan
    /// against 200 templates ran in 0.7 s while the panel estimated ~2 s.
    /// 5 s is the ceiling because the run is already cancellable and reports
    /// progress, so the cost of accepting is bounded and visible; and the
    /// estimate is only offered at all once it is grounded (a measured
    /// throughput, or the CPU baseline), never on an unmeasured GPU guess.
    package func estimatedDuration(forPositions positions: Int) -> TimeInterval? {
        let templates = Double(quality.templateCount)
        let throughput: Double
        if let measured = lastPositionsPerSecond,
           let measuredTemplates = lastMeasuredTemplateCount,
           lastMeasuredBackend == effectiveBackend {
            throughput = measured * Double(measuredTemplates) / templates
        } else if effectiveBackend == .cpu {
            // Hands-on M3 Release baseline: 1,150 positions/s at 400 templates.
            throughput = 1_150 * 400 / templates
        } else {
            return nil
        }
        return Double(positions) / max(throughput, 1)
    }

    package var primaryActionTitle: String {
        switch scope {
        case .preview: "Preview Orientation"
        case .selectedRegion: "Map Selected Region"
        case .fullScan: "Run Full Orientation Map"
        }
    }

    package var modelSelectionIssue: String? {
        switch modelSelection {
        case .none:
            return "Choose the phase model used to generate orientation templates."
        case .library(let id):
            guard let model = CrystalModelLibrary.model(id: id) else {
                return "The selected phase model is no longer available."
            }
            return model.validationIssues.first?.message
        case .customCubic:
            let model = CrystalModelLibrary.customCubic(
                structure: customStructure,
                latticeA: customLatticeA,
                atomicNumber: customZ
            )
            return model.validationIssues.first?.message
        case .imported(let id):
            guard let model = importedCrystalModels.first(where: { $0.id == id }) else {
                // Reached only if a selection ever outlives its model within
                // one run (e.g. a future "clear imports" action) — reopening
                // the app never hits this, since `modelSelection` itself
                // resets to `.none` on every dataset (re)activation.
                return "The imported phase model is no longer available in this session — import the CIF again."
            }
            return model.validationIssues.first?.message ?? model.orientationMappingIssue
        }
    }

    /// v2.5 step 6: the IPF map's confidence gate. Nil = automatic, the 10th
    /// percentile of matched reliabilities; a number overrides it (the
    /// colorbar chip's slider, when it lands). Positions below it draw grey.
    package var effectiveReliabilityThreshold: Float? {
        reliabilityThreshold ?? orientationMap?.reliabilityThreshold(percentile: 0.1)
    }

    package init() {}

    package func invalidatePlan() {
        orientationPlan = nil
        hasOrientationPlan = false
        invalidateResult()
    }

    /// Dataset activation's ACOM reset (moved out of `AppState.activate`,
    /// C7 session 2, to hold the line budget in `AppState.swift`/
    /// `ResultExport.swift`): every plan/result/run fact plus the region
    /// controls, back to their just-opened defaults. `scope` and
    /// `regionRadius` fire their AppState-owned hooks like any other write,
    /// unchanged from when these assignments lived in `AppState`. Order
    /// preserved exactly from the original block.
    package func resetForDataset(rx: Int, ry: Int) {
        orientationPlan = nil
        orientationMap = nil
        hasOrientationPlan = false
        hasOrientationMap = false
        modelSelection = .none
        lastRunScope = nil
        lastRunQuality = nil
        lastRunSemantics = nil
        lastMatchedPositionCount = nil
        lastPositionsPerSecond = nil
        lastEndToEndDuration = nil
        regionSelectionActive = false
        scope = .preview
        displayIsUserChosen = false
        regionRadius = max(8, min(rx, ry) / 12)
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
