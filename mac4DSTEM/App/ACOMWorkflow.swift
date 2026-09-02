import Foundation
import DSTEMCore

/// Which ACOM result map to display.
enum ACOMDisplayMode: String, CaseIterable, Identifiable {
    case ipfZ = "IPF · Z"
    case reliability = "Reliability"
    case disorientation = "Symmetry FZ angle"
    case inPlane = "In-plane angle"
    case phi1 = "Euler φ₁"
    case Phi = "Euler Φ"
    case phi2 = "Euler φ₂"
    case score = "Score"
    var id: String { rawValue }
}

enum ACOMQualityPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case best = "Best"

    var id: String { rawValue }

    var templateCount: Int {
        switch self {
        case .fast: 96
        case .balanced: 200
        case .best: 400
        }
    }

    var detail: String {
        switch self {
        case .fast: "96 templates · rapid screening"
        case .balanced: "200 templates · recommended"
        case .best: "400 templates · finest angular sampling"
        }
    }
}

enum ACOMRunScope: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case selectedRegion = "Region"
    case fullScan = "Full scan"

    var id: String { rawValue }

    var resultQualifier: String {
        switch self {
        case .preview: "preview"
        case .selectedRegion: "region"
        case .fullScan: "full"
        }
    }
}

/// Provenance of the reciprocal scale actually used for one ACOM run.
/// `exploratory` is a tunable alignment aid, not physical calibration.
enum ACOMQScaleProvenance: String, Sendable {
    case exploratory = "exploratory"
    case importedFile = "imported_file"
    case sessionSidecar = "session_sidecar"
    case measuredInApp = "measured_in_app"
    case manual = "manual"
    case mixed = "mixed_sources"

    var isPhysical: Bool { self != .exploratory }

    var displayName: String {
        switch self {
        case .exploratory: "Exploratory"
        case .importedFile: "Physical · imported file"
        case .sessionSidecar: "Physical · session"
        case .measuredInApp: "Physical · measured in app"
        case .manual: "Physical · manual"
        case .mixed: "Physical · mixed sources"
        }
    }

    init(_ provenance: CalibrationValueProvenance?) {
        switch provenance {
        case .importedFile: self = .importedFile
        case .sessionSidecar: self = .sessionSidecar
        case .measuredInApp: self = .measuredInApp
        case .manual, nil: self = .manual
        case .mixed: self = .mixed
        }
    }
}

struct ACOMScaleSemantics: Sendable, Equatable {
    let invAngstromPerPixel: Double
    let provenance: ACOMQScaleProvenance

    var interpretation: String {
        provenance.isPhysical ? "physical" : "exploratory"
    }
}

/// Immutable scientific contract captured when a map finishes. Export and
/// session persistence use this snapshot, never whichever controls happen to
/// be visible later.
struct ACOMRunSemantics: Sendable, Equatable {
    let materialModelID: String
    let materialDescription: String
    let scale: ACOMScaleSemantics
    let materialProvenance: [String: String]

    init(
        materialModelID: String, materialDescription: String,
        scale: ACOMScaleSemantics,
        materialProvenance: [String: String] = [:]
    ) {
        self.materialModelID = materialModelID
        self.materialDescription = materialDescription
        self.scale = scale
        self.materialProvenance = materialProvenance
    }

    func productStatus(for kind: String) -> ProductQuantitativeStatus {
        guard scale.provenance.isPhysical else { return .exploratory }
        if kind.contains("ipf") { return .categorical }
        if kind.contains("reliability") || kind.contains("score") {
            return .relative
        }
        return .quantitative
    }

    var provenance: [String: String] {
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
