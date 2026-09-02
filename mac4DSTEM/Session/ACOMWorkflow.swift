import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// Which ACOM result map to display.
package enum ACOMDisplayMode: String, CaseIterable, Identifiable {
    case ipfZ = "IPF · Z"
    case reliability = "Reliability"
    case disorientation = "Symmetry FZ angle"
    case inPlane = "In-plane angle"
    case phi1 = "Euler φ₁"
    case Phi = "Euler Φ"
    case phi2 = "Euler φ₂"
    case score = "Score"
    package var id: String { rawValue }
}

package enum ACOMQualityPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case best = "Best"

    package var id: String { rawValue }

    package var templateCount: Int {
        switch self {
        case .fast: 96
        case .balanced: 200
        case .best: 400
        }
    }

    package var detail: String {
        switch self {
        case .fast: "96 templates · rapid screening"
        case .balanced: "200 templates · recommended"
        case .best: "400 templates · finest angular sampling"
        }
    }
}

package enum ACOMRunScope: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case selectedRegion = "Region"
    case fullScan = "Full scan"

    package var id: String { rawValue }

    package var resultQualifier: String {
        switch self {
        case .preview: "preview"
        case .selectedRegion: "region"
        case .fullScan: "full"
        }
    }
}

/// Provenance of the reciprocal scale actually used for one ACOM run.
/// `exploratory` is a tunable alignment aid, not physical calibration.
package enum ACOMQScaleProvenance: String, Sendable {
    case exploratory = "exploratory"
    case importedFile = "imported_file"
    case sessionSidecar = "session_sidecar"
    case measuredInApp = "measured_in_app"
    case manual = "manual"
    case mixed = "mixed_sources"

    package var isPhysical: Bool { self != .exploratory }

    package var displayName: String {
        switch self {
        case .exploratory: "Exploratory"
        case .importedFile: "Physical · imported file"
        case .sessionSidecar: "Physical · session"
        case .measuredInApp: "Physical · measured in app"
        case .manual: "Physical · manual"
        case .mixed: "Physical · mixed sources"
        }
    }

    package init(_ provenance: CalibrationValueProvenance?) {
        switch provenance {
        case .importedFile: self = .importedFile
        case .sessionSidecar: self = .sessionSidecar
        case .measuredInApp: self = .measuredInApp
        case .manual, nil: self = .manual
        case .mixed: self = .mixed
        }
    }
}

package struct ACOMScaleSemantics: Sendable, Equatable {
    package let invAngstromPerPixel: Double
    package let provenance: ACOMQScaleProvenance

    package var interpretation: String {
        provenance.isPhysical ? "physical" : "exploratory"
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(invAngstromPerPixel: Double, provenance: ACOMQScaleProvenance) {
        self.invAngstromPerPixel = invAngstromPerPixel
        self.provenance = provenance
    }
}

/// Immutable scientific contract captured when a map finishes. Export and
/// session persistence use this snapshot, never whichever controls happen to
/// be visible later.
package struct ACOMRunSemantics: Sendable, Equatable {
    package let materialModelID: String
    package let materialDescription: String
    package let scale: ACOMScaleSemantics
    package let materialProvenance: [String: String]

    package init(
        materialModelID: String, materialDescription: String,
        scale: ACOMScaleSemantics,
        materialProvenance: [String: String] = [:]
    ) {
        self.materialModelID = materialModelID
        self.materialDescription = materialDescription
        self.scale = scale
        self.materialProvenance = materialProvenance
    }

    package func productStatus(for kind: String) -> ProductQuantitativeStatus {
        guard scale.provenance.isPhysical else { return .exploratory }
        if kind.contains("ipf") { return .categorical }
        if kind.contains("reliability") || kind.contains("score") {
            return .relative
        }
        return .quantitative
    }

    package var provenance: [String: String] {
        var result = materialProvenance
        result.merge([
            "material_model_id": materialModelID,
            "material_model": materialDescription,
            "q_inv_angstrom_per_pixel": String(scale.invAngstromPerPixel),
            "q_scale_provenance": scale.provenance.rawValue,
            "interpretation": scale.interpretation,
            "dataset_validation": "not_independently_validated",
        ]) { _, current in current }
        return result
    }
}
