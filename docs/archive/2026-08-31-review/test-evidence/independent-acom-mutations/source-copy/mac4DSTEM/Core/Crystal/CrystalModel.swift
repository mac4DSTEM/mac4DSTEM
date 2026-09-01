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

        // An over-populated cell is the one modelling error that produces no
        // visible symptom: site multiplicity multiplies straight into the
        // kinematic structure factors, so the templates are wrong but nothing
        // fails. It arises when symmetry-equivalent positions are expanded into
        // near-coincident duplicates (backlog #14). Rejecting on physical
        // grounds catches it whatever the cause: `closeContactLimit` is well
        // under the shortest interatomic contact in any crystal, so a pair this
        // close, at full occupancy, is never chemistry.
        //
        // The message states what was measured and stops there. It must not
        // blame symmetry expansion — most models reaching here never ran any
        // (a P1 site list bypasses it entirely), and telling a crystallographer
        // that an expansion they did not ask for broke their file sends them
        // looking in the wrong place.
        if let closest = shortestCloseContact {
            add(
                "atomic_sites_too_close",
                String(
                    format: "Two fully-occupied atomic sites are %.4f Å apart — closer than "
                    + "any real interatomic distance, so the cell holds more atoms than the "
                    + "structure has.",
                    closest
                )
            )
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

    /// Shortest centre-to-centre distance (Å) between two atomic sites that
    /// **cannot both be occupied by a whole atom**, when that distance is under
    /// `closeContactLimit`. This is a close-contact detector, not a general
    /// bond-length query. `nil` means "no such pair" (or: fewer than two sites,
    /// degenerate lattice).
    ///
    /// Pairs whose occupancies sum to ≤ 1 are skipped. A split site — two
    /// part-occupied images straddling a special position, never simultaneously
    /// occupied — is ordinary refinement practice and is routinely written
    /// 0.2–0.5 Å apart; flagging those would reject correct disorder models
    /// (fluorite anion displacement, atoms split about a mirror). The exemption
    /// costs one narrow case: duplicates of an already part-occupied site are
    /// invisible to this check, and only `expand`'s merge protects those.
    ///
    /// It is O(n²) and reachable from view state, so the 27-image minimum-image
    /// search is gated behind a per-axis fractional prefilter that rejects
    /// almost every pair in three comparisons.
    /// Below the shortest interatomic contact known in any crystal (H–H in
    /// solid hydrogen, 0.74 Å), so no real structure trips it.
    static let closeContactLimit = 0.5

    var shortestCloseContact: Double? {
        let sites = crystal.sites
        guard sites.count > 1 else { return nil }
        let lattice = crystal.latReal
        guard lattice.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              crystal.volume.isFinite, crystal.volume > 0
        else { return nil }

        // Per-axis prefilter. A fractional offset Δ along axis i displaces the
        // atom by at least |Δ|·hᵢ, where hᵢ = V / |a_j × a_k| is the spacing of
        // the planes spanned by the other two axes — the one component the
        // other axes cannot cancel. So |Δᵢ| > limit / hᵢ rules the pair out.
        func cross(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
        }
        let faceAreas = [
            cross(lattice[1], lattice[2]), cross(lattice[2], lattice[0]),
            cross(lattice[0], lattice[1]),
        ].map { ($0 * $0).sum().squareRoot() }
        let limit = CrystalModel.closeContactLimit
        let maxAxisDelta = faceAreas.map { area -> Double in
            let height = area > 0 ? crystal.volume / area : 0
            return height > 0 ? min(0.5, limit / height) : 0.5
        }

        func axisDelta(_ x: Double, _ y: Double) -> Double {
            var d = abs(x - y).truncatingRemainder(dividingBy: 1)
            if d > 0.5 { d = 1 - d }
            return d
        }

        var best = Double.infinity
        for i in 0..<sites.count {
            for j in (i + 1)..<sites.count {
                // 0.02 matches the occupancy slack the CIF importer's symmetry
                // matching already allows for refinement noise, so a 0.5/0.5
                // split refined to 0.51/0.50 is still read as a split.
                guard sites[i].occupancy + sites[j].occupancy > 1 + 0.02 else { continue }
                let a = sites[i].fractional, b = sites[j].fractional
                guard axisDelta(a.x, b.x) <= maxAxisDelta[0],
                      axisDelta(a.y, b.y) <= maxAxisDelta[1],
                      axisDelta(a.z, b.z) <= maxAxisDelta[2]
                else { continue }
                let base = a - b
                for dx in -1...1 {
                    for dy in -1...1 {
                        for dz in -1...1 {
                            let f = base + SIMD3<Double>(Double(dx), Double(dy), Double(dz))
                            let cartesian = f.x * lattice[0] + f.y * lattice[1] + f.z * lattice[2]
                            best = min(best, (cartesian * cartesian).sum())
                        }
                    }
                }
            }
        }
        let closest = best.squareRoot()
        return closest < limit ? closest : nil
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
/// UI enum case. Imported models use the same stable identifier route as
/// library models — `.imported(id)` resolves against `AppState`'s
/// session-local imported-model list rather than `CrystalModelLibrary`.
nonisolated enum CrystalModelSelection: Hashable, Sendable, Identifiable {
    case none
    case library(String)
    case customCubic
    case imported(String)

    var id: String {
        switch self {
        case .none: "none"
        case .library(let id): "library:\(id)"
        case .customCubic: "custom_cubic"
        case .imported(let id): "imported:\(id)"
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
        // W4a (2026-08-31). Built-in rather than import-only on purpose: the
        // replay record stores only a materialModelID, and an .imported model
        // does not survive into a new session — so an ACOM step recorded
        // against an imported CIF cannot replay. The library entry is what
        // makes a WS₂ recipe replayable at all. Lattice citation on the
        // Crystal definition.
        CrystalModel(id: "ws2_2h", displayName: "Tungsten disulfide (2H-WS₂)",
                     crystal: .tungstenDisulfide, symmetry: .hexagonal, source: .builtIn),
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
