import Foundation

/// Origin of a phase definition. This describes the model, not the dataset;
/// no phase is inferred from a filename or diffraction-pattern appearance.
package nonisolated enum CrystalModelSource: String, Sendable, CaseIterable {
    case builtIn = "built_in"
    case custom = "custom"
    case imported = "imported"
    case materialsProject = "materials_project"
}

package nonisolated struct CrystalModelValidationIssue: Sendable, Equatable {
    package let code: String
    package let message: String

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// A complete phase model accepted by ACOM. `Crystal` supplies lattice,
/// atomic basis, and structure factors; `symmetry` supplies orientation
/// sampling, reduction, and IPF interpretation. Keeping them together avoids
/// silently applying cubic presentation to an arbitrary lattice.
package nonisolated struct CrystalModel: Identifiable, Sendable {
    package let id: String
    package let displayName: String
    package let crystal: Crystal
    package let symmetry: ACOMCrystalSymmetry
    package let source: CrystalModelSource
    /// IT (International Tables) space-group number, when known — set by
    /// `MaterialsProjectImport` from `symmetry.number`, or by `CIFImport` when
    /// the CIF itself carries `_symmetry_int_tables_number` /
    /// `_space_group_it_number`. `nil` means "not recorded", not "P1"; most
    /// built-in and custom models never set it.
    package let spaceGroupNumber: Int?
    /// Source-specific provenance facts that don't fit the fixed keys
    /// `provenance` always writes (a Materials Project id, fetch date,
    /// reported symbol, …). Merged into `provenance` verbatim; empty for
    /// every model that doesn't need it.
    package let extraProvenance: [String: String]

    package var validationIssues: [CrystalModelValidationIssue] {
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
            // Structurally fine. What it cannot do is stated by
            // `supportsOrientationMapping` below, NOT here: a validation issue
            // would make `CIFImport.crystalModel` throw `.invalidModel` and the
            // structure would never load at all.
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
    package static let closeContactLimit = 0.5

    package var shortestCloseContact: Double? {
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

    package var isUsable: Bool { validationIssues.isEmpty }

    /// Whether this model may drive ACOM orientation mapping.
    ///
    /// Separate from `isUsable` on purpose, and the distinction is the whole
    /// point: an `.identity` model is a perfectly good CRYSTAL — cell, basis and
    /// structure factors all valid, and that is everything phase
    /// IDENTIFICATION needs — but the app implements orientation reduction for
    /// cubic and hexagonal only. Mapping one anyway would publish an unreduced
    /// orientation and call `ACOMCrystalSymmetry.identity.ipfColor`, which
    /// returns |x|,|y|,|z| as RGB: not a wrong IPF key, but no key at all
    /// wearing the look of one.
    ///
    /// It is NOT a validation issue, because `CIFImport.crystalModel` throws
    /// `.invalidModel` on any validation issue — so recording it there would
    /// refuse the structure at import and defeat the purpose.
    package var supportsOrientationMapping: Bool { symmetry != .identity }

    /// Why orientation mapping is unavailable, or nil when it is available.
    /// `ACOMSession.modelSelectionIssue` surfaces this so ACOM refuses with a
    /// reason rather than silently offering nothing.
    package var orientationMappingIssue: String? {
        supportsOrientationMapping ? nil
            : "This phase is \(symmetry.displayName.lowercased()): its cell is neither "
              + "cubic nor hexagonal, and orientation reduction is implemented for those "
              + "two families only. The structure can still be used to identify the phase, "
              + "but it cannot produce an orientation map or an IPF colour."
    }

    /// In-memory identity used to reject a completion when editable model
    /// values changed while a plan was being generated.
    package var revisionID: String {
        let sites = crystal.sites.map {
            "\($0.z):\($0.fractional.x),\($0.fractional.y),\($0.fractional.z):\($0.occupancy)"
        }.joined(separator: ";")
        return "\(id)|\(symmetry.rawValue)|\(crystal.a),\(crystal.b),\(crystal.c)|\(crystal.alphaDeg),\(crystal.betaDeg),\(crystal.gammaDeg)|\(sites)"
    }

    /// Immutable description attached to completed orientation products.
    package var provenance: [String: String] {
        let atomicBasis = crystal.sites.map {
            "Z\($0.z)@(\($0.fractional.x),\($0.fractional.y),\($0.fractional.z));occ=\($0.occupancy)"
        }.joined(separator: "|")
        var result: [String: String] = [
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
        if let spaceGroupNumber {
            result["space_group_number"] = String(spaceGroupNumber)
        }
        for (key, value) in extraProvenance {
            result[key] = value
        }
        return result
    }

    /// A stable digest of what the model IS — cell, symmetry and atomic basis
    /// — independent of its id and display name. An imported model's id is
    /// `imported_<file stem>`, so two different CIFs with the same filename
    /// share an id; a recipe that resolved its material by id alone would
    /// replay against the wrong crystal (open item, closed 2026-09-05). FNV-1a
    /// over the provenance strings, not `Hasher`, because `Hasher` is seeded
    /// per process and this value is written into session files.
    package var contentFingerprint: String {
        let keys = ["crystal_symmetry", "cell_a_angstrom", "cell_b_angstrom", "cell_c_angstrom",
                    "cell_alpha_degrees", "cell_beta_degrees", "cell_gamma_degrees", "atomic_basis"]
        let provenance = self.provenance
        let canonical = keys.map { "\($0)=\(provenance[$0] ?? "")" }.joined(separator: "\n")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(
        id: String, displayName: String, crystal: Crystal, symmetry: ACOMCrystalSymmetry,
        source: CrystalModelSource, spaceGroupNumber: Int? = nil,
        extraProvenance: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.crystal = crystal
        self.symmetry = symmetry
        self.source = source
        self.spaceGroupNumber = spaceGroupNumber
        self.extraProvenance = extraProvenance
    }
}

/// A scalable selection token: adding a library model does not require a new
/// UI enum case. Imported models use the same stable identifier route as
/// library models — `.imported(id)` resolves against `AppState`'s
/// session-local imported-model list rather than `CrystalModelLibrary`.
package nonisolated enum CrystalModelSelection: Hashable, Sendable, Identifiable {
    case none
    case library(String)
    case customCubic
    case imported(String)

    package var id: String {
        switch self {
        case .none: "none"
        case .library(let id): "library:\(id)"
        case .customCubic: "custom_cubic"
        case .imported(let id): "imported:\(id)"
        }
    }
}

package nonisolated enum CrystalModelLibrary {
    /// Session S5 (owner's product decision): Materials Project is the
    /// default phase source and the user's own CIFs are the other one — this
    /// library is no longer offered as a UI choice (`UI/MapSettings.swift`'s
    /// ACOM picker, `UI/PhaseMappingSettings.swift`'s "Add Phase" menu now
    /// list only "Materials Project…", "Import CIF…" and already-imported
    /// models). It stays here as a **resolver**: `CrystalModelSelection.library(id)`
    /// still exists and must still resolve, because a recipe recorded before
    /// this session (`Session/ReplayPlan.swift`) and every test that names a
    /// built-in model by id (`ws2_2h`, `au_fcc`, …) depend on it.
    package static let models: [CrystalModel] = [
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

    package static func model(id: String) -> CrystalModel? {
        models.first { $0.id == id }
    }

    package static func customCubic(
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
