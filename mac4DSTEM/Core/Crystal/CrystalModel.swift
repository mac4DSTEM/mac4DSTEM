import Foundation
import DiffractoCore
import DiffractoScattering

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

/// A complete phase model accepted by ACOM. `structure` (DiffractoKit's `CrystalStructure`) supplies lattice,
/// atomic basis, and structure factors; `symmetry` supplies orientation
/// sampling, reduction, and IPF interpretation. Keeping them together avoids
/// silently applying cubic presentation to an arbitrary lattice.
package nonisolated struct CrystalModel: Identifiable, Sendable {
    package let id: String
    package let displayName: String
    package let structure: CrystalStructure
    package let symmetry: ACOMCrystalSymmetry
    package let source: CrystalModelSource
    /// IT (International Tables) space-group number, when known — set by
    /// `MaterialsProjectImport` from `symmetry.number`, or by `CIFModelImport` when
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
        // The structure's own checks are the kit's: cell lengths, angles and volume, a non-empty basis, occupancy,
        // finite coordinates, and the close contact (same codes and texts as the app's own checks before 2026-10-15,
        // except: a cell flatter than V = 1e-6 abc is also `invalid_cell_volume`, and Z outside 1 to 118 is the kit's
        // `invalid_atomic_number`, which the app's own `unsupported_element` below replaces for Z outside the
        // scattering table, 1 to 103). An over-populated cell is the one modelling error that produces no visible
        // symptom: site multiplicity multiplies straight into the kinematic structure factors, so the templates are
        // wrong but nothing fails (backlog #14). The close-contact message states what was measured and stops there.
        for issue in structure.validationIssues where issue.code != "invalid_atomic_number" {
            add(issue.code, issue.message)
        }
        for site in structure.sites where site.z < 1 || !ElectronScatteringFactors.isSupported(z: site.z) {
            add("unsupported_element", "No electron scattering factors are available for Z = \(site.z).")
        }

        let cell = structure.cell
        let angles = [cell.alphaDeg, cell.betaDeg, cell.gammaDeg]
        func approximately(_ lhs: Double, _ rhs: Double, relative: Double = 1e-6) -> Bool {
            abs(lhs - rhs) <= relative * max(1, max(abs(lhs), abs(rhs)))
        }
        switch symmetry {
        case .cubic:
            if !approximately(cell.a, cell.b)
                || !approximately(cell.a, cell.c)
                || !angles.allSatisfy({ approximately($0, 90) }) {
                add("cubic_symmetry_mismatch", "Cubic m-3m symmetry requires a = b = c and α = β = γ = 90°.")
            }
        case .hexagonal:
            if !approximately(cell.a, cell.b)
                || !approximately(cell.alphaDeg, 90)
                || !approximately(cell.betaDeg, 90)
                || !approximately(cell.gammaDeg, 120) {
                add("hexagonal_symmetry_mismatch", "Hexagonal 6/mmm symmetry requires a = b, α = β = 90°, and γ = 120°.")
            }
        case .monoclinic:
            // b is the unique axis (+y in the py4DSTEM frame) only when alpha = gamma = 90, and the
            // cell is monoclinic only when beta is not 90 (beta = 90 is orthorhombic: no 2/m key).
            // Tolerance 0.05 degrees (the app's old importer tolerance), looser than the kit's metric test (1e-9),
            // so a cell the kit maps to `.monoclinic` is never refused here, as it could be at 1e-6.
            if abs(cell.alphaDeg - 90) > 0.05
                || abs(cell.gammaDeg - 90) > 0.05
                || abs(cell.betaDeg - 90) <= 0.05 {
                add("monoclinic_symmetry_mismatch", "Monoclinic 2/m symmetry (b unique) requires α = γ = 90° and β ≠ 90°.")
            }
        case .identity:
            // Structurally fine. What it cannot do is stated by
            // `supportsOrientationMapping` below, NOT here: a validation issue
            // would make `CIFModelImport.crystalModel` throw `.invalidModel` and the
            // structure would never load at all.
            break
        }
        return issues
    }

    /// Shortest centre-to-centre distance (Å) between two atomic sites that cannot both be occupied by a whole atom,
    /// when under `closeContactLimit` (0.5 Å, below the shortest interatomic contact known in any crystal): the kit's
    /// `CrystalStructure.shortestCloseContact`, the app's algorithm moved out unchanged. Split sites (occupancies
    /// summing to at most 1.02) are skipped.
    package static let closeContactLimit = CrystalStructure.closeContactLimit

    package var shortestCloseContact: Double? { structure.shortestCloseContact }

    package var isUsable: Bool { validationIssues.isEmpty }

    /// Whether this model may drive ACOM orientation mapping.
    ///
    /// Separate from `isUsable` on purpose, and the distinction is the whole
    /// point: an `.identity` model is a perfectly good CRYSTAL — cell, basis and
    /// structure factors all valid, and that is everything phase
    /// IDENTIFICATION needs — but the app implements orientation reduction for
    /// cubic, hexagonal and monoclinic only. Mapping one anyway would publish an unreduced
    /// orientation and call `ACOMCrystalSymmetry.identity.ipfColor`, which
    /// returns |x|,|y|,|z| as RGB: not a wrong IPF key, but no key at all
    /// wearing the look of one.
    ///
    /// It is NOT a validation issue, because `CIFModelImport.crystalModel` throws
    /// `.invalidModel` on any validation issue — so recording it there would
    /// refuse the structure at import and defeat the purpose.
    package var supportsOrientationMapping: Bool { symmetry != .identity }

    /// A monoclinic orientation map has no beta'' truth set behind it (suite ROADMAP item 5): it
    /// self-reports `validation: "none"`, which the inspector note, the exported caption and the
    /// provenance already read (owner, 2026-09-18: unvalidated stays labelled).
    package static let monoclinicValidationNote = "monoclinic orientation — no β″ truth set"

    /// Why orientation mapping is unavailable, or nil when it is available.
    /// `ACOMSession.modelSelectionIssue` surfaces this so ACOM refuses with a
    /// reason rather than silently offering nothing.
    package var orientationMappingIssue: String? {
        supportsOrientationMapping ? nil
            : "This phase is \(symmetry.displayName.lowercased()): its cell is neither "
              + "cubic nor hexagonal, nor monoclinic with b unique and a 2-fold or mirror along it, and "
              + "orientation reduction is implemented for those families only. The structure can still be used to identify the phase, "
              + "but it cannot produce an orientation map or an IPF colour."
    }

    /// In-memory identity used to reject a completion when editable model
    /// values changed while a plan was being generated.
    package var revisionID: String {
        let cell = structure.cell
        let sites = structure.sites.map {
            "\($0.z):\($0.fractional.x),\($0.fractional.y),\($0.fractional.z):\($0.occupancy)"
        }.joined(separator: ";")
        return "\(id)|\(symmetry.rawValue)|\(cell.a),\(cell.b),\(cell.c)|\(cell.alphaDeg),\(cell.betaDeg),\(cell.gammaDeg)|\(sites)"
    }

    /// Immutable description attached to completed orientation products.
    package var provenance: [String: String] {
        let cell = structure.cell
        let atomicBasis = structure.sites.map {
            "Z\($0.z)@(\($0.fractional.x),\($0.fractional.y),\($0.fractional.z));occ=\($0.occupancy)"
        }.joined(separator: "|")
        var result: [String: String] = [
            "crystal_model_id": id,
            "crystal_model_name": displayName,
            "crystal_model_source": source.rawValue,
            "crystal_symmetry": symmetry.rawValue,
            "cell_a_angstrom": String(cell.a),
            "cell_b_angstrom": String(cell.b),
            "cell_c_angstrom": String(cell.c),
            "cell_alpha_degrees": String(cell.alphaDeg),
            "cell_beta_degrees": String(cell.betaDeg),
            "cell_gamma_degrees": String(cell.gammaDeg),
            "cell_volume_angstrom_cubed": String(cell.volume),
            "atomic_site_count": String(structure.sites.count),
            "atomic_basis": atomicBasis,
        ]
        if let spaceGroupNumber {
            result["space_group_number"] = String(spaceGroupNumber)
        }
        if symmetry == .monoclinic {
            result["validation"] = "none"
            result["validation_note"] = Self.monoclinicValidationNote
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
        id: String, displayName: String, structure: CrystalStructure, symmetry: ACOMCrystalSymmetry,
        source: CrystalModelSource, spaceGroupNumber: Int? = nil,
        extraProvenance: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.structure = structure
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
                     structure: Crystal.gold, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "al_fcc", displayName: "Aluminium (FCC)",
                     structure: Crystal.aluminum, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "ni_fcc", displayName: "Nickel (FCC)",
                     structure: Crystal.nickel, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "cu_fcc", displayName: "Copper (FCC)",
                     structure: Crystal.copper, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "fe_bcc", displayName: "Iron (BCC)",
                     structure: Crystal.iron, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "si_diamond", displayName: "Silicon (diamond)",
                     structure: Crystal.silicon, symmetry: .cubic, source: .builtIn),
        CrystalModel(id: "mg_hcp", displayName: "Magnesium (HCP)",
                     structure: Crystal.magnesium, symmetry: .hexagonal, source: .builtIn),
        // W4a (2026-08-31). Built-in rather than import-only on purpose: the
        // replay record stores only a materialModelID, and an .imported model
        // does not survive into a new session — so an ACOM step recorded
        // against an imported CIF cannot replay. The library entry is what
        // makes a WS₂ recipe replayable at all. Lattice citation on the
        // Crystal definition.
        CrystalModel(id: "ws2_2h", displayName: "Tungsten disulfide (2H-WS₂)",
                     structure: Crystal.tungstenDisulfide, symmetry: .hexagonal, source: .builtIn),
    ]

    package static func model(id: String) -> CrystalModel? {
        models.first { $0.id == id }
    }

    package static func customCubic(
        structure: Crystal.CubicStructure, latticeA: Double, atomicNumber: Int
    ) -> CrystalModel {
        let symbol = Element.symbol(forAtomicNumber: atomicNumber) ?? "Z\(atomicNumber)"
        return CrystalModel(
            id: "custom_cubic_\(structure.provenanceID)_z\(atomicNumber)",
            displayName: "\(symbol) \(structure.rawValue), a = \(String(format: "%.4g", latticeA)) Å",
            structure: Crystal.cubic(structure, a: latticeA, z: atomicNumber),
            symmetry: .cubic,
            source: .custom
        )
    }
}

extension ACOMCrystalSymmetry {
    /// The orientation reduction ACOM implements for `structure`, from the kit's Laue class of its operations AND the
    /// cell it is written in: m-3m in a cubic cell is `.cubic`, 6/mmm in a hexagonal cell (a = b, γ = 120°) is
    /// `.hexagonal`, and 2/m with b the unique axis is `.monoclinic` (the kit's 2/m is any unique axis, ACOM's
    /// `.monoclinic` is b unique only). Everything else, and a structure whose operations form no Laue group, is
    /// `.identity` ("Unreduced"): the structure still identifies a phase, but it gets no fundamental zone and no IPF
    /// key (`CrystalModel.orientationMappingIssue`).
    ///
    /// The cell test is not redundant. The orientation reduction works in the crystal's Cartesian frame (a along +x),
    /// which is the cubic frame only for a cubic cell: a face-centred structure written in its primitive rhombohedral
    /// cell (α = β = γ = 60°) has Laue class m-3m, but its frame is not the cubic axes, and `.cubic` would draw a wrong
    /// fundamental zone and IPF key. It imports as `.identity`, as it did before the kit (registration P4, the MgO
    /// primitive-cell plant). Used by the CIF and Materials Project importers; the one place a class becomes a family.
    package nonisolated static func reduction(for structure: CrystalStructure) -> ACOMCrystalSymmetry {
        let metric = structure.cell.metricFamily()
        switch structure.laueClass {
        case .mThreeBarM?:
            return metric == .cubic ? .cubic : .identity
        case .sixOverMmm?:
            return metric == .hexagonal ? .hexagonal : .identity
        case .twoOverM?:
            return metric == .monoclinic(uniqueAxis: .b) ? .monoclinic : .identity
        default:
            return .identity
        }
    }
}
