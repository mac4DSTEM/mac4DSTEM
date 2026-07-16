import Foundation

/// The product-level information architecture. Scientific algorithms remain
/// represented by `AnalysisMode`; these areas describe the outcome a user is
/// trying to reach and keep implementation details out of primary navigation.
enum WorkspaceArea: String, CaseIterable, Identifiable, Sendable {
    case prepare
    case image
    case map
    case reconstruct
    case results

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prepare: "Prepare"
        case .image: "Image"
        case .map: "Map"
        case .reconstruct: "Reconstruct"
        case .results: "Results"
        }
    }

    var subtitle: String {
        switch self {
        case .prepare: "Inspect and calibrate the dataset"
        case .image: "Create virtual and phase-contrast images"
        case .map: "Measure disks, strain, and orientation"
        case .reconstruct: "Recover phase and depth"
        case .results: "Review, save, and export products"
        }
    }

    var systemImage: String {
        switch self {
        case .prepare: "scope"
        case .image: "camera.filters"
        case .map: "map"
        case .reconstruct: "waveform.path.ecg.rectangle"
        case .results: "square.grid.2x2"
        }
    }

    var analysisModes: [AnalysisMode] {
        switch self {
        case .prepare, .results: []
        case .image: [.virtualDetector, .dpc]
        case .map: [.disks, .strain, .acom]
        case .reconstruct: [.ptychography]
        }
    }

    var defaultAnalysisMode: AnalysisMode? { analysisModes.first }
    var isAdvanced: Bool { self == .reconstruct }
}

extension AnalysisMode {
    var workspaceArea: WorkspaceArea {
        switch self {
        case .virtualDetector, .dpc: .image
        case .disks, .strain, .acom: .map
        case .ptychography: .reconstruct
        }
    }

    var productTitle: String {
        switch self {
        case .virtualDetector: "Virtual imaging"
        case .dpc: "DPC & iDPC"
        case .disks: "Bragg disks"
        case .strain: "Strain"
        case .ptychography: "Parallax & ptychography"
        case .acom: "Orientation"
        }
    }

    var productSubtitle: String {
        switch self {
        case .virtualDetector: "Form BF, ADF, HAADF, or custom detector images"
        case .dpc: "Map beam deflection and integrate projected phase"
        case .disks: "Detect reciprocal-lattice peaks across the scan"
        case .strain: "Measure lattice distortion from indexed Bragg peaks"
        case .ptychography: "Reconstruct phase, amplitude, aberrations, and depth"
        case .acom: "Match crystal orientation and reliability"
        }
    }

    var systemImage: String {
        switch self {
        case .virtualDetector: "circle.dotted"
        case .dpc: "arrow.up.and.down.and.arrow.left.and.right"
        case .disks: "circle.grid.cross"
        case .strain: "arrow.up.left.and.arrow.down.right"
        case .ptychography: "waveform.path.ecg"
        case .acom: "cube.transparent"
        }
    }
}

/// Pure, testable guidance used by the sidebar and empty/result states.
struct ProductWorkflowReadiness: Equatable, Sendable {
    var hasOriginProbe = false
    var hasRotation = false
    var hasQScale = false
    var hasRScale = false
    var hasVoltage = false
    var hasBraggVectors = false
    var hasACOMMaterial = false
    var hasSupportedACOMMaterial = false
    var hasPhysicalACOMScale = false
}

enum ProductWorkflow {
    static func prerequisites(
        for mode: AnalysisMode,
        readiness: ProductWorkflowReadiness
    ) -> [String] {
        var missing: [String] = []
        switch mode {
        case .virtualDetector, .dpc, .disks:
            break
        case .ptychography:
            if !readiness.hasOriginProbe { missing.append("Calibrate the diffraction origin") }
            if !readiness.hasRotation { missing.append("Calibrate the R–Q rotation") }
            if !readiness.hasQScale { missing.append("Set the Q pixel scale") }
            if !readiness.hasRScale { missing.append("Set the R pixel scale") }
            if !readiness.hasVoltage { missing.append("Set the accelerating voltage") }
        case .strain:
            if !readiness.hasBraggVectors { missing.append("Detect Bragg disks first") }
        case .acom:
            if !readiness.hasBraggVectors { missing.append("Detect Bragg disks first") }
            if !readiness.hasACOMMaterial {
                missing.append("Choose an ACOM material model")
            } else if !readiness.hasSupportedACOMMaterial {
                missing.append("The selected ACOM material is not supported")
            }
        }
        return missing
    }

    /// Non-blocking scientific context. These messages explain the units or
    /// correction level of an operation that is valid to run now; they must
    /// never be presented as a contradictory disabled-state prerequisite.
    static func guidance(
        for mode: AnalysisMode,
        readiness: ProductWorkflowReadiness
    ) -> [String] {
        switch mode {
        case .virtualDetector, .disks, .ptychography:
            return []
        case .dpc:
            var missing: [String] = []
            if !readiness.hasOriginProbe { missing.append("origin") }
            if !readiness.hasRotation { missing.append("R–Q rotation") }
            if !readiness.hasQScale { missing.append("Q scale") }
            if !readiness.hasRScale { missing.append("R scale") }
            if !readiness.hasVoltage { missing.append("voltage") }
            guard !missing.isEmpty else { return [] }
            return ["Runs in qualitative units; add \(missing.joined(separator: ", ")) for quantitative DPC/iDPC."]
        case .strain:
            return readiness.hasOriginProbe
                ? []
                : ["Uses the current detector origin; calibrate it for corrected Bragg vectors."]
        case .acom:
            return readiness.hasPhysicalACOMScale
                ? []
                : ["Exploratory matching only: set physical Q sampling for quantitative orientation output."]
        }
    }

    static func recommendedNextArea(
        calibrationReady: Bool,
        hasResult: Bool
    ) -> WorkspaceArea {
        if !calibrationReady { return .prepare }
        if !hasResult { return .image }
        return .results
    }
}
