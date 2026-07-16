import Foundation

/// Origin of a phase definition. This describes the model, not the dataset;
/// no phase is inferred from a filename or diffraction-pattern appearance.
nonisolated enum CrystalModelSource: String, Sendable {
    case builtIn = "built_in"
    case custom = "custom"
    case imported = "imported"
}

nonisolated struct CrystalModelValidationIssue: Sendable, Equatable {
    let code: String
    let message: String
}

/// A complete phase model accepted by ACOM. `Crystal` supplies lattice,
/// atomic basis, and structure factors; `symmetry` supplies orientation
/// sampling, reduction, and IPF interpretation. Keeping them together avoids
/// silently applying cubic presentation to an arbitrary lattice.
nonisolated struct CrystalModel: Identifiable, Sendable {
    let id: String
    let displayName: String
    let crystal: Crystal
    let symmetry: ACOMCrystalSymmetry
    let source: CrystalModelSource

    var validationIssues: [CrystalModelValidationIssue] {
        var issues: [CrystalModelValidationIssue] = []
        func add(_ code: String, _ message: String) {
            issues.append(.init(code: code, message: message))
        }
        let lengths = [crystal.a, crystal.b, crystal.c]
        if lengths.contains(where: { !$0.isFinite || $0 <= 0 }) {
            add("invalid_cell_lengths", "Cell lengths must be finite and positive.")
        }
        let angles = [crystal.alphaDeg, crystal.betaDeg, crystal.gammaDeg]
        if angles.contains(where: { !$0.isFinite || $0 <= 0 || $0 >= 180 }) {
            add("invalid_cell_angles", "Cell angles must be finite and strictly between 0° and 180°.")
        }
        if !crystal.volume.isFinite || crystal.volume <= 0 {
            add("invalid_cell_volume", "The lattice vectors do not form a finite positive-volume cell.")
        }
        if crystal.sites.isEmpty {
            add("missing_atomic_basis", "At least one occupied atomic site is required.")
        }
        for site in crystal.sites {
            if site.z < 1 || !ScatteringFactors.isSupported(z: site.z) {
                add("unsupported_element", "No electron scattering factors are available for Z = \(site.z).")
            }
            if !site.occupancy.isFinite || site.occupancy <= 0 || site.occupancy > 1 {
                add("invalid_occupancy", "Atomic occupancies must be finite and in (0, 1].")
            }
            if !site.fractional.x.isFinite || !site.fractional.y.isFinite
                || !site.fractional.z.isFinite {
                add("invalid_fractional_coordinate", "Atomic fractional coordinates must be finite.")
            }
        }

        func approximately(_ lhs: Double, _ rhs: Double, relative: Double = 1e-6) -> Bool {
            abs(lhs - rhs) <= relative * max(1, max(abs(lhs), abs(rhs)))
        }
        switch symmetry {
        case .cubic:
            if !approximately(crystal.a, crystal.b)
                || !approximately(crystal.a, crystal.c)
                || !angles.allSatisfy({ approximately($0, 90) }) {
                add("cubic_symmetry_mismatch", "Cubic m-3m symmetry requires a = b = c and α = β = γ = 90°.")
            }
        case .hexagonal:
            if !approximately(crystal.a, crystal.b)
                || !approximately(crystal.alphaDeg, 90)
                || !approximately(crystal.betaDeg, 90)
                || !approximately(crystal.gammaDeg, 120) {
                add("hexagonal_symmetry_mismatch", "Hexagonal 6/mmm symmetry requires a = b, α = β = 90°, and γ = 120°.")
            }
        case .identity:
            break
        }
        return issues
    }

    var isUsable: Bool { validationIssues.isEmpty }

    /// In-memory identity used to reject a completion when editable model
    /// values changed while a plan was being generated.
    var revisionID: String {
        let sites = crystal.sites.map {
            "\($0.z):\($0.fractional.x),\($0.fractional.y),\($0.fractional.z):\($0.occupancy)"
        }.joined(separator: ";")
        return "\(id)|\(symmetry.rawValue)|\(crystal.a),\(crystal.b),\(crystal.c)|\(crystal.alphaDeg),\(crystal.betaDeg),\(crystal.gammaDeg)|\(sites)"
    }

    /// Immutable description attached to completed orientation products.
    var provenance: [String: String] {
        let atomicBasis = crystal.sites.map {
            "Z\($0.z)@(\($0.fractional.x),\($0.fractional.y),\($0.fractional.z));occ=\($0.occupancy)"
        }.joined(separator: "|")
        return [
            "crystal_model_id": id,
            "crystal_model_name": displayName,
            "crystal_model_source": source.rawValue,
            "crystal_symmetry": symmetry.rawValue,
            "cell_a_angstrom": String(crystal.a),
            "cell_b_angstrom": String(crystal.b),
            "cell_c_angstrom": String(crystal.c),
            "cell_alpha_degrees": String(crystal.alphaDeg),
            "cell_beta_degrees": String(crystal.betaDeg),
            "cell_gamma_degrees": String(crystal.gammaDeg),
            "cell_volume_angstrom_cubed": String(crystal.volume),
            "atomic_site_count": String(crystal.sites.count),
            "atomic_basis": atomicBasis,
        ]
    }
}

/// A scalable selection token: adding a library model does not require a new
/// UI enum case. Imported models can use the same stable identifier route once
/// a validated CIF importer and point-group resolver exist.
nonisolated enum CrystalModelSelection: Hashable, Sendable, Identifiable {
    case none
    case library(String)
    case customCubic

    var id: String {
        switch self {
        case .none: "none"
        case .library(let id): "library:\(id)"
        case .customCubic: "custom_cubic"
        }
    }
}

nonisolated enum CrystalModelLibrary {
    static let models: [CrystalModel] = [
        CrystalModel(id: "au_fcc", displayName: "Gold (FCC)",
                     crystal: .gold, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "al_fcc", displayName: "Aluminium (FCC)",
                     crystal: .aluminum, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "ni_fcc", displayName: "Nickel (FCC)",
                     crystal: .nickel, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "cu_fcc", displayName: "Copper (FCC)",
                     crystal: .copper, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "fe_bcc", displayName: "Iron (BCC)",
                     crystal: .iron, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "si_diamond", displayName: "Silicon (diamond)",
                     crystal: .silicon, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "mg_hcp", displayName: "Magnesium (HCP)",
                     crystal: .magnesium, symmetry: .hexagonal, source: .builtIn),
    ]

    static func model(id: String) -> CrystalModel? {
        models.first { $0.id == id }
    }

    static func customCubic(
        structure: Crystal.CubicStructure, latticeA: Double, atomicNumber: Int
    ) -> CrystalModel {
        let symbol = ScatteringFactors.symbols[atomicNumber] ?? "Z\(atomicNumber)"
        return CrystalModel(
            id: "custom_cubic_\(structure.provenanceID)_z\(atomicNumber)",
            displayName: "\(symbol) \(structure.rawValue), a = \(String(format: "%.4g", latticeA)) Å",
            crystal: Crystal.cubic(structure, a: latticeA, z: atomicNumber),
            symmetry: .cubic,
            source: .custom
        )
    }
}
