//
//  MaterialsProjectImport.swift
//  Role: Core plumbing for the Materials Project (MP) importer — session S4a
//        of docs/v3-precipitates-and-materials-project-plan.md. Decodes a
//        `GET /materials/summary/` response, turns one `SummaryDoc` into a
//        validated `CrystalModel`, and checks a fetched document against the
//        phase the user expected before it is trusted.
//
//  Wire shape verified live against the Materials Project openapi.json,
//  2026-09-21 (docs/v3-materials-project-preregistration.md): the response is
//  `{"data":[SummaryDoc…],"errors":[{"code":int,"message":str}],"meta":{…}}`.
//  Unknown JSON keys are ignored — `Decodable` does this for free by simply
//  not declaring them, matching what `CIFImport` does for CIF tags it does
//  not model.
//
//  Symmetry classification is NOT re-implemented here. `classifyFamily`
//  (widened `private` → `package` on `CIFImport`, this session) is called
//  verbatim, per the pre-registration's Gate D reasoning: the one
//  symmetry-relevant step in this importer reuses the CIF importer's
//  already-tested classifier rather than writing new science. MP's own
//  `symmetry.crystal_system` and `symmetry.symbol` are recorded in
//  provenance only — never used to choose `ACOMCrystalSymmetry` — for the
//  same reason `CIFImport` never trusts a file's stated symmetry either
//  (`CIFImport.swift`, `verifyFamily`).
//
//  Element lookup reuses `CIFImport.elementSymbolToZ` / `.elementSymbol(from:)`
//  (both widened `private` → `package` this session) rather than a second
//  symbol table.
//
//  Occupancy rule for a site with several species: the same one `CIFImport`
//  effectively applies. `CIFImport` has no special-cased "disordered site"
//  handling — each `_atom_site_*` loop row becomes its own `AtomSite` with
//  its own element and occupancy, and it is `CrystalModel.validationIssues`
//  (invalid occupancy, too-close sites) that catches a chemically impossible
//  combination after the fact. This importer does the same: one `AtomSite`
//  per `species[]` entry, sharing the site's fractional position.
//
//  Every type here is `nonisolated`, matching every other file in
//  `Core/Crystal/`: this is pure data plus pure functions, callable from
//  whatever background task ends up doing the actual network fetch.
//

import Foundation
import simd

// MARK: - Wire types

/// `GET /materials/summary/` response envelope.
package nonisolated struct MaterialsProjectSummaryResponse: Decodable, Sendable {
    package let data: [MaterialsProjectDocument]
    package let errors: [MaterialsProjectError]

    // Explicit so the memberwise initializer is `package` (synthesized ones
    // are internal) — needed by tests that build a fixture without a JSON
    // round-trip (e.g. a non-finite number, which JSON cannot encode at all).
    package init(data: [MaterialsProjectDocument], errors: [MaterialsProjectError]) {
        self.data = data
        self.errors = errors
    }
}

/// One `SummaryDoc`. Only the fields this importer uses are modeled; every
/// unknown key (`builder_meta`, `nsites`, `theoretical`, …) is ignored by
/// `Decodable` simply by not being declared here.
package nonisolated struct MaterialsProjectDocument: Decodable, Sendable {
    package let materialID: String
    package let formulaPretty: String?
    package let deprecated: Bool?
    package let lastUpdated: String?
    package let structure: MaterialsProjectStructure?
    package let symmetry: MaterialsProjectSymmetry?

    private enum CodingKeys: String, CodingKey {
        case materialID = "material_id"
        case formulaPretty = "formula_pretty"
        case deprecated
        case lastUpdated = "last_updated"
        case structure
        case symmetry
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(
        materialID: String, formulaPretty: String? = nil, deprecated: Bool? = nil,
        lastUpdated: String? = nil, structure: MaterialsProjectStructure? = nil,
        symmetry: MaterialsProjectSymmetry? = nil
    ) {
        self.materialID = materialID
        self.formulaPretty = formulaPretty
        self.deprecated = deprecated
        self.lastUpdated = lastUpdated
        self.structure = structure
        self.symmetry = symmetry
    }
}

package nonisolated struct MaterialsProjectStructure: Decodable, Sendable {
    package let lattice: MaterialsProjectLattice?
    package let sites: [MaterialsProjectSite]?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(lattice: MaterialsProjectLattice? = nil, sites: [MaterialsProjectSite]? = nil) {
        self.lattice = lattice
        self.sites = sites
    }
}

package nonisolated struct MaterialsProjectLattice: Decodable, Sendable {
    package let a: Double
    package let b: Double
    package let c: Double
    package let alpha: Double
    package let beta: Double
    package let gamma: Double
    /// The served Cartesian lattice matrix (rows = a, b, c vectors), when MP
    /// includes it — real `structure.lattice` payloads normally do. Session
    /// S4b's `standardise(_:symmetry:)` uses this directly when present, and
    /// falls back to rebuilding it from `a,b,c,alpha,beta,gamma` (the same
    /// construction `Crystal.init` does) only when it is absent, so a fixture
    /// or a trimmed `_fields` response that omits it still works.
    package let matrix: [[Double]]?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(
        a: Double, b: Double, c: Double, alpha: Double, beta: Double, gamma: Double,
        matrix: [[Double]]? = nil
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.alpha = alpha
        self.beta = beta
        self.gamma = gamma
        self.matrix = matrix
    }
}

package nonisolated struct MaterialsProjectSite: Decodable, Sendable {
    package let label: String?
    package let species: [MaterialsProjectSpecies]?
    package let abc: [Double]?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(label: String? = nil, species: [MaterialsProjectSpecies]? = nil, abc: [Double]? = nil) {
        self.label = label
        self.species = species
        self.abc = abc
    }
}

package nonisolated struct MaterialsProjectSpecies: Decodable, Sendable {
    package let element: String
    package let occu: Double

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(element: String, occu: Double) {
        self.element = element
        self.occu = occu
    }
}

package nonisolated struct MaterialsProjectSymmetry: Decodable, Sendable {
    package let crystalSystem: String?
    package let symbol: String?
    package let number: Int?
    package let pointGroup: String?
    package let hall: String?

    private enum CodingKeys: String, CodingKey {
        case crystalSystem = "crystal_system"
        case symbol
        case number
        case pointGroup = "point_group"
        case hall
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(
        crystalSystem: String? = nil, symbol: String? = nil, number: Int? = nil,
        pointGroup: String? = nil, hall: String? = nil
    ) {
        self.crystalSystem = crystalSystem
        self.symbol = symbol
        self.number = number
        self.pointGroup = pointGroup
        self.hall = hall
    }
}

package nonisolated struct MaterialsProjectError: Decodable, Sendable {
    package let code: Int
    package let message: String

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Phase expectation

/// What the user expected the fetched material to be, before it is trusted.
/// Both fields are independently optional — `MaterialsProjectImport.check`
/// grades whatever the caller actually knows.
package nonisolated struct PhaseExpectation: Equatable, Sendable {
    package var formula: String?
    package var spaceGroupNumber: Int?

    package init(formula: String? = nil, spaceGroupNumber: Int? = nil) {
        self.formula = formula
        self.spaceGroupNumber = spaceGroupNumber
    }
}

package nonisolated enum PhaseExpectationVerdict: Equatable, Sendable {
    case matches
    /// Neither `formula` nor `spaceGroupNumber` was supplied — nothing to
    /// grade against.
    case unchecked
    case mismatch(reason: String)
}

// MARK: - Cell standardisation (session S4b)

/// Whether `MaterialsProjectImport.standardise` had to convert the served
/// cell. The MP API's `structure` is the relaxed cell as stored — normally a
/// *primitive* cell for a centred lattice, converted to conventional
/// CLIENT-side by the mp-api Python client with pymatgen's
/// `SpacegroupAnalyzer` (verified 2026-09-21 from `mprester.py`). mac4DSTEM
/// talks to the REST API directly and gets the served cell as-is, so this
/// importer has to do that conversion itself — or refuse when it cannot
/// verify one — rather than silently classifying the primitive cell's metric
/// (an FCC primitive is a=b=c, α=β=γ=60°, which reads as `.identity`, not
/// `.cubic`; a zone axis typed in conventional indices is then wrong).
package nonisolated enum CellStandardisation: Equatable, Sendable {
    /// The served cell already was the conventional cell (`P`-centred, or a
    /// centred cell metrically conventional already), or there was no
    /// reported symmetry to standardise against.
    case asServed
    /// The served cell was a primitive cell for the named centring, and was
    /// transformed to the conventional cell by the fixed ITA basis change
    /// for that centring.
    case conventional(centring: Character)
}

/// Row-major 3×3 helpers for the fixed integer centring-transformation
/// matrices below. Deliberately separate from `Crystal`'s private metric-
/// tensor helpers (`Crystal.swift`, `gram`/`matMul`/`invert3x3` ~ lines
/// 350-390) — those compute the real/reciprocal metric tensor, a different
/// piece of math from an integer change-of-basis between two real-space
/// settings, and they are `private` to that file, so this is a second small
/// implementation by necessity, not a duplicate of the same science.
private nonisolated enum Matrix3 {
    static func determinant(_ m: [[Double]]) -> Double {
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
    }

    static func determinant(_ rows: [SIMD3<Double>]) -> Double {
        determinant([
            [rows[0].x, rows[0].y, rows[0].z],
            [rows[1].x, rows[1].y, rows[1].z],
            [rows[2].x, rows[2].y, rows[2].z],
        ])
    }

    static func inverse(_ m: [[Double]]) -> [[Double]]? {
        let det = determinant(m)
        guard abs(det) > 1e-12 else { return nil }
        // Cofactor matrix; the inverse is its transpose (the adjugate) over
        // the determinant.
        let cof: [[Double]] = [
            [
                m[1][1] * m[2][2] - m[1][2] * m[2][1],
                -(m[1][0] * m[2][2] - m[1][2] * m[2][0]),
                m[1][0] * m[2][1] - m[1][1] * m[2][0],
            ],
            [
                -(m[0][1] * m[2][2] - m[0][2] * m[2][1]),
                m[0][0] * m[2][2] - m[0][2] * m[2][0],
                -(m[0][0] * m[2][1] - m[0][1] * m[2][0]),
            ],
            [
                m[0][1] * m[1][2] - m[0][2] * m[1][1],
                -(m[0][0] * m[1][2] - m[0][2] * m[1][0]),
                m[0][0] * m[1][1] - m[0][1] * m[1][0],
            ],
        ]
        var inv = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                inv[i][j] = cof[j][i] / det
            }
        }
        return inv
    }

    /// New lattice row *i* = Σⱼ `m[i][j]` · `oldRows[j]` — the convention the
    /// pre-registration's centring matrices are written in ("rows are the
    /// new basis vectors in terms of the old"). Verified 2026-09-21 on the
    /// Si case: applying the F matrix this way to the F-centred primitive's
    /// `a/2·(0,1,1), a/2·(1,0,1), a/2·(1,1,0)` reproduces the conventional
    /// cubic `(a,0,0), (0,a,0), (0,0,a)` exactly.
    static func transformRows(_ oldRows: [SIMD3<Double>], by m: [[Double]]) -> [SIMD3<Double>] {
        (0..<3).map { i in
            m[i][0] * oldRows[0] + m[i][1] * oldRows[1] + m[i][2] * oldRows[2]
        }
    }

    /// Row-vector-times-matrix: result_j = Σᵢ `v[i]` · `m[i][j]`. Fractional
    /// coordinates transform with the matrix that carries the LATTICE from
    /// conventional back to primitive, i.e. the inverse of the matrix used
    /// in `transformRows` above (derivation: r = xₚᵀ·Aₚ = xᵀ·(M·Aₚ) requires
    /// xₚᵀ = xᵀ·M, so x = xₚ·M⁻¹ as row vectors) — verified on Si: with
    /// `Minv` for the F matrix, (0,0,0)↦(0,0,0) and
    /// (0.25,0.25,0.25)↦(0.25,0.25,0.25), and adding the four F-centring
    /// translations to each reproduces exactly the eight conventional
    /// diamond-cubic sites.
    static func applyToRowVector(_ v: SIMD3<Double>, _ m: [[Double]]) -> SIMD3<Double> {
        SIMD3(
            v.x * m[0][0] + v.y * m[1][0] + v.z * m[2][0],
            v.x * m[0][1] + v.y * m[1][1] + v.z * m[2][1],
            v.x * m[0][2] + v.y * m[1][2] + v.z * m[2][2]
        )
    }
}

/// One centred-lattice standardisation: the fixed ITA change-of-basis matrix
/// (rows = conventional basis vectors in terms of the primitive ones), the
/// centring multiplicity (= its determinant), and the centring translations
/// added to every transformed fractional position.
private nonisolated struct CentringTransform {
    let matrix: [[Double]]
    let multiplicity: Int
    let translations: [SIMD3<Double>]
}

private nonisolated func centringTransform(for letter: Character) -> CentringTransform? {
    switch letter {
    case "F":
        return CentringTransform(
            matrix: [[-1, 1, 1], [1, -1, 1], [1, 1, -1]],
            multiplicity: 4,
            translations: [
                SIMD3(0, 0, 0), SIMD3(0, 0.5, 0.5), SIMD3(0.5, 0, 0.5), SIMD3(0.5, 0.5, 0),
            ]
        )
    case "I":
        return CentringTransform(
            matrix: [[0, 1, 1], [1, 0, 1], [1, 1, 0]],
            multiplicity: 2,
            translations: [SIMD3(0, 0, 0), SIMD3(0.5, 0.5, 0.5)]
        )
    case "C":
        return CentringTransform(
            matrix: [[1, -1, 0], [1, 1, 0], [0, 0, 1]],
            multiplicity: 2,
            translations: [SIMD3(0, 0, 0), SIMD3(0.5, 0.5, 0)]
        )
    case "A":
        return CentringTransform(
            matrix: [[1, 0, 0], [0, 1, -1], [0, 1, 1]],
            multiplicity: 2,
            translations: [SIMD3(0, 0, 0), SIMD3(0, 0.5, 0.5)]
        )
    case "B":
        return CentringTransform(
            matrix: [[1, 0, -1], [0, 1, 0], [1, 0, 1]],
            multiplicity: 2,
            translations: [SIMD3(0, 0, 0), SIMD3(0.5, 0, 0.5)]
        )
    case "R":
        // Obverse hexagonal setting.
        return CentringTransform(
            matrix: [[1, -1, 0], [0, 1, -1], [1, 1, 1]],
            multiplicity: 3,
            translations: [
                SIMD3(0, 0, 0), SIMD3(2.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), SIMD3(1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0),
            ]
        )
    default:
        return nil
    }
}

/// Reduce one fractional coordinate into `[0, 1)`, snapping values within
/// 1e-9 of an integer to exactly 0 — the same "don't leave a 0.999999999998
/// where a 0 belongs" precaution `CIFImport`'s own axis-wrapping applies
/// (`CIFImport.swift`, `wrapAxis`, a `private` sibling of this one; not
/// reused verbatim for the same file-boundary reason as `Matrix3` above).
private nonisolated func wrap01(_ x: Double) -> Double {
    var m = x.truncatingRemainder(dividingBy: 1)
    if m < 0 { m += 1 }
    if m >= 1 - 1e-9 || abs(m) < 1e-9 { m = 0 }
    return m
}

/// Angle between two Cartesian vectors, in degrees, clamping the cosine to
/// `[-1, 1]` before `acos` so float rounding on a near-parallel/antiparallel
/// pair can't produce a NaN.
private nonisolated func angleDeg(between u: SIMD3<Double>, and v: SIMD3<Double>) -> Double {
    let cosTheta = dot(u, v) / (length(u) * length(v))
    return acos(min(1, max(-1, cosTheta))) * 180 / .pi
}

/// Does this cell metric already look like the conventional cell for
/// `system` (MP's lowercased `symmetry.crystal_system`)? Tolerances per the
/// pre-registration: 1e-3 relative on lengths, 1e-2° on angles. Used both to
/// decide whether a served cell needs standardising at all, and — on the
/// transformed cell — as guard (a) that the transform actually produced a
/// conventional cell for the stated system (never a silently-wrong one for a
/// system that doesn't match, e.g. a cubic result reported as "hexagonal").
private nonisolated func isAlreadyConventionalCell(
    system: String, a: Double, b: Double, c: Double, alphaDeg: Double, betaDeg: Double, gammaDeg: Double
) -> Bool {
    func lengthsMatch(_ x: Double, _ y: Double) -> Bool {
        abs(x - y) <= 1e-3 * max(1, max(abs(x), abs(y)))
    }
    func angleMatches(_ angle: Double, _ target: Double) -> Bool {
        abs(angle - target) <= 1e-2
    }
    switch system {
    case "cubic":
        return lengthsMatch(a, b) && lengthsMatch(a, c)
            && angleMatches(alphaDeg, 90) && angleMatches(betaDeg, 90) && angleMatches(gammaDeg, 90)
    case "tetragonal":
        return lengthsMatch(a, b)
            && angleMatches(alphaDeg, 90) && angleMatches(betaDeg, 90) && angleMatches(gammaDeg, 90)
    case "orthorhombic":
        return angleMatches(alphaDeg, 90) && angleMatches(betaDeg, 90) && angleMatches(gammaDeg, 90)
    case "hexagonal", "trigonal":
        return lengthsMatch(a, b)
            && angleMatches(alphaDeg, 90) && angleMatches(betaDeg, 90) && angleMatches(gammaDeg, 120)
    case "monoclinic":
        // b-unique setting.
        return angleMatches(alphaDeg, 90) && angleMatches(gammaDeg, 90)
    case "triclinic":
        return true
    default:
        // An unrecognized/absent crystal-system string means there is no
        // formula to check a standardisation against — never treated as
        // "already fine" (see the `.nonStandardCell` guard this feeds).
        return false
    }
}

// MARK: - Importer

package nonisolated enum MaterialsProjectImport {

    /// Every named refusal this importer produces. `.deprecated` is
    /// deliberately absent — a deprecated MP entry still imports; the flag
    /// rides in provenance (`materials_project_deprecated`) instead of
    /// blocking the fetch, per this session's brief.
    package nonisolated enum Failure: LocalizedError, Equatable {
        /// `materialID` does not match `^mp-[0-9]+$`.
        case invalidMaterialID(String)
        /// The response's `data` array was empty.
        case emptyResult(String)
        /// The response's `errors` array was non-empty.
        case apiError(code: Int, message: String)
        /// The document decoded, but is missing structure/lattice/sites, or
        /// carries a non-finite number or an unusable coordinate/element —
        /// named so a scientist can see what the response actually lacked.
        case malformed(String)
        /// MP served a centred (non-`P`) primitive cell that
        /// `standardise(_:symmetry:)` could not verify a safe conventional
        /// standardisation for — the reported crystal system's metric test
        /// failed on the served cell, on the transformed cell, on the
        /// centring multiplicity, or on the transformed site list. Session
        /// S4b's Gate D diagnosis: silently classifying an unstandardised
        /// primitive cell (e.g. an FCC primitive, a=b=c/α=β=γ=60°) mis-scores
        /// its family (`.identity` instead of `.cubic`) and types zone axes
        /// in the wrong indices, so this refuses rather than guesses.
        case nonStandardCell(String)

        package var errorDescription: String? {
            switch self {
            case .invalidMaterialID(let id):
                return "\"\(id)\" is not a valid Materials Project material id (expected \"mp-<digits>\")."
            case .emptyResult(let reason):
                return "Materials Project returned no usable result: \(reason)"
            case .apiError(let code, let message):
                return "Materials Project API error \(code): \(message)"
            case .malformed(let reason):
                return "Materials Project response could not be used: \(reason)"
            case .nonStandardCell(let reason):
                return "Materials Project cell could not be safely standardised: \(reason)"
            }
        }
    }

    /// Standardises a served MP structure to the conventional cell when it is
    /// a primitive cell for a centred lattice, per the session S4b
    /// pre-registration. Called from `crystalModel(from:fetchedAt:)` BEFORE
    /// family classification — see `CellStandardisation`'s header for why.
    ///
    /// Centring letter = first character of `symmetry.symbol`. No symmetry,
    /// no symbol, or a `P` centring → `.asServed` (nothing to standardise
    /// against, or already primitive-is-conventional). Otherwise the served
    /// cell metric is checked against the conventional-cell test for the
    /// reported `symmetry.crystal_system`; if it already passes, `.asServed`
    /// (some MP entries already carry the conventional cell despite a
    /// centred symbol). Otherwise the fixed ITA transformation for that
    /// centring is applied, and the result must pass every one of:
    ///  (a) the transformed cell itself passes the conventional-cell test
    ///      for the stated system,
    ///  (b) the transformation matrix's determinant is the centring's
    ///      multiplicity, and the transformed cell's volume is that same
    ///      multiple of the served cell's volume (1e-6 relative),
    ///  (c) the transformed site list has exactly `multiplicity × served
    ///      count` sites, no two same-element sites closer than 1e-3 in
    ///      fractional distance (mod 1), and each element's site count
    ///      scales by exactly `multiplicity`.
    /// Any failure throws `.nonStandardCell` — this importer never guesses.
    package static func standardise(
        _ structure: MaterialsProjectStructure, symmetry: MaterialsProjectSymmetry?
    ) throws -> (structure: MaterialsProjectStructure, how: CellStandardisation) {
        guard let lattice = structure.lattice else {
            throw Failure.malformed("structure has no lattice to standardise.")
        }
        guard let sites = structure.sites, !sites.isEmpty else {
            throw Failure.malformed("structure lists no atomic sites to standardise.")
        }

        guard let symbol = symmetry?.symbol, let centring = symbol.first else {
            return (structure, .asServed)
        }
        if centring == "P" {
            return (structure, .asServed)
        }

        guard let crystalSystemRaw = symmetry?.crystalSystem else {
            throw Failure.nonStandardCell(
                "no crystal_system was reported to verify a \(centring)-centred cell's "
                    + "standardisation against."
            )
        }
        let system = crystalSystemRaw.lowercased()

        if isAlreadyConventionalCell(
            system: system, a: lattice.a, b: lattice.b, c: lattice.c,
            alphaDeg: lattice.alpha, betaDeg: lattice.beta, gammaDeg: lattice.gamma
        ) {
            return (structure, .asServed)
        }

        guard let transform = centringTransform(for: centring) else {
            throw Failure.nonStandardCell("unrecognized centring letter '\(centring)' in symbol \"\(symbol)\".")
        }

        // Served lattice as Cartesian row vectors — from the wire `matrix`
        // when present, else rebuilt from a,b,c,α,β,γ the way `Crystal.init`
        // does (`Crystal.swift` ~86-108), reused via `Crystal.init` itself
        // (with an empty site list, purely to read `.latReal` back out)
        // rather than a second copy of that trig.
        let servedRows: [SIMD3<Double>]
        if let rawMatrix = lattice.matrix, rawMatrix.count == 3, rawMatrix.allSatisfy({ $0.count == 3 }) {
            servedRows = rawMatrix.map { SIMD3($0[0], $0[1], $0[2]) }
        } else {
            servedRows = Crystal(
                a: lattice.a, b: lattice.b, c: lattice.c,
                alphaDeg: lattice.alpha, betaDeg: lattice.beta, gammaDeg: lattice.gamma,
                sites: []
            ).latReal
        }

        let matrixDeterminant = Matrix3.determinant(transform.matrix)
        guard abs(matrixDeterminant - Double(transform.multiplicity)) < 1e-9 else {
            throw Failure.nonStandardCell(
                "the \(centring)-centring transformation matrix's determinant (\(matrixDeterminant)) "
                    + "does not match its expected multiplicity \(transform.multiplicity)."
            )
        }
        guard let inverseMatrix = Matrix3.inverse(transform.matrix) else {
            throw Failure.nonStandardCell("the \(centring)-centring transformation matrix is not invertible.")
        }

        let newRows = Matrix3.transformRows(servedRows, by: transform.matrix)
        let newA = length(newRows[0]), newB = length(newRows[1]), newC = length(newRows[2])
        let newAlpha = angleDeg(between: newRows[1], and: newRows[2])
        let newBeta = angleDeg(between: newRows[0], and: newRows[2])
        let newGamma = angleDeg(between: newRows[0], and: newRows[1])

        // GUARD (a): the transformed cell must itself read as conventional
        // for the *stated* system — catches both a wrong transform and
        // inconsistent MP metadata (a cubic-symbol cell reported as a
        // different crystal system).
        guard isAlreadyConventionalCell(
            system: system, a: newA, b: newB, c: newC,
            alphaDeg: newAlpha, betaDeg: newBeta, gammaDeg: newGamma
        ) else {
            throw Failure.nonStandardCell(
                "standardising as a \(centring)-centred primitive did not produce a conventional "
                    + "\(system) cell (got a=\(newA), b=\(newB), c=\(newC), "
                    + "α=\(newAlpha)°, β=\(newBeta)°, γ=\(newGamma)°)."
            )
        }

        // GUARD (b): the transformed cell's volume must be exactly the
        // centring's multiplicity times the served cell's.
        let servedVolume = abs(Matrix3.determinant(servedRows))
        guard servedVolume > 0, servedVolume.isFinite else {
            throw Failure.nonStandardCell("the served primitive cell has no finite positive volume.")
        }
        let newVolume = abs(Matrix3.determinant(newRows))
        let volumeRatio = newVolume / servedVolume
        guard abs(volumeRatio - Double(transform.multiplicity)) <= 1e-6 * Double(transform.multiplicity) else {
            throw Failure.nonStandardCell(
                "the standardised cell's volume is \(volumeRatio)× the served cell's, not the "
                    + "expected \(transform.multiplicity)× for \(centring)-centring."
            )
        }

        // Transform every fractional site position, then add the centring
        // translations.
        var newSites: [MaterialsProjectSite] = []
        newSites.reserveCapacity(sites.count * transform.translations.count)
        for site in sites {
            guard let abc = site.abc, abc.count == 3 else {
                throw Failure.malformed("a site has no usable fractional coordinates to standardise.")
            }
            let servedFractional = SIMD3(abc[0], abc[1], abc[2])
            let base = Matrix3.applyToRowVector(servedFractional, inverseMatrix)
            for translation in transform.translations {
                let combined = base + translation
                let wrapped = SIMD3(wrap01(combined.x), wrap01(combined.y), wrap01(combined.z))
                newSites.append(
                    MaterialsProjectSite(label: site.label, species: site.species, abc: [wrapped.x, wrapped.y, wrapped.z])
                )
            }
        }

        // GUARD (c): the arithmetic invariant (never actually false unless
        // the loop above has a bug), the composition ratio, and — the guard
        // that actually screens bad served data — no two same-element sites
        // landing on top of each other.
        let expectedCount = sites.count * transform.translations.count
        guard newSites.count == expectedCount else {
            throw Failure.nonStandardCell(
                "standardisation produced \(newSites.count) sites, expected \(expectedCount)."
            )
        }

        func elementCounts(_ list: [MaterialsProjectSite]) -> [String: Int] {
            var counts: [String: Int] = [:]
            for site in list {
                for species in site.species ?? [] {
                    counts[CIFImport.elementSymbol(from: species.element), default: 0] += 1
                }
            }
            return counts
        }
        let servedCounts = elementCounts(sites)
        let newCounts = elementCounts(newSites)
        for (element, servedCount) in servedCounts {
            let expected = servedCount * transform.multiplicity
            guard newCounts[element] == expected else {
                throw Failure.nonStandardCell(
                    "standardisation changed \(element)'s site count (\(servedCount) -> "
                        + "\(newCounts[element] ?? 0)), expected ×\(transform.multiplicity) = \(expected)."
                )
            }
        }

        for i in 0..<newSites.count {
            guard let abcI = newSites[i].abc, abcI.count == 3 else { continue }
            let elementsI = Set((newSites[i].species ?? []).map { CIFImport.elementSymbol(from: $0.element) })
            guard !elementsI.isEmpty else { continue }
            let posI = SIMD3(abcI[0], abcI[1], abcI[2])
            for j in (i + 1)..<newSites.count {
                guard let abcJ = newSites[j].abc, abcJ.count == 3 else { continue }
                let elementsJ = Set((newSites[j].species ?? []).map { CIFImport.elementSymbol(from: $0.element) })
                guard !elementsI.isDisjoint(with: elementsJ) else { continue }
                let posJ = SIMD3(abcJ[0], abcJ[1], abcJ[2])
                let distance = (
                    axisDelta(posI.x, posJ.x) * axisDelta(posI.x, posJ.x)
                        + axisDelta(posI.y, posJ.y) * axisDelta(posI.y, posJ.y)
                        + axisDelta(posI.z, posJ.z) * axisDelta(posI.z, posJ.z)
                ).squareRoot()
                guard distance >= 1e-3 else {
                    let shared = elementsI.intersection(elementsJ).sorted().joined(separator: ",")
                    throw Failure.nonStandardCell(
                        "standardisation produced two \(shared) sites \(distance) apart in fractional "
                            + "distance — the served site list is not this centring's true asymmetric unit."
                    )
                }
            }
        }

        let newLattice = MaterialsProjectLattice(
            a: newA, b: newB, c: newC, alpha: newAlpha, beta: newBeta, gamma: newGamma,
            matrix: newRows.map { [$0.x, $0.y, $0.z] }
        )
        return (MaterialsProjectStructure(lattice: newLattice, sites: newSites), .conventional(centring: centring))
    }

    /// Build the `GET /materials/summary/` request for one material id.
    /// Validates the id up front — a malformed id sent to the API comes back
    /// as an empty `data` array indistinguishable from "not found", so the
    /// more specific refusal is worth catching here.
    package static func request(materialID: String, apiKey: String) throws -> URLRequest {
        guard isValidMaterialID(materialID) else {
            throw Failure.invalidMaterialID(materialID)
        }
        var components = URLComponents(string: "https://api.materialsproject.org/materials/summary/")!
        components.queryItems = [
            URLQueryItem(name: "material_ids", value: materialID),
            URLQueryItem(
                name: "_fields",
                value: "material_id,formula_pretty,structure,symmetry,deprecated,last_updated"
            ),
        ]
        guard let url = components.url else {
            throw Failure.invalidMaterialID(materialID)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        return request
    }

    private static func isValidMaterialID(_ id: String) -> Bool {
        guard id.hasPrefix("mp-") else { return false }
        let digits = id.dropFirst(3)
        guard !digits.isEmpty else { return false }
        return digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Decode the raw response body. Unknown keys are ignored automatically;
    /// a response that isn't the documented envelope shape throws whatever
    /// `DecodingError` `JSONDecoder` produces — this layer names *usable but
    /// empty/erroring* responses (see `firstDocument`), not malformed JSON.
    package static func decode(_ data: Data) throws -> MaterialsProjectSummaryResponse {
        try JSONDecoder().decode(MaterialsProjectSummaryResponse.self, from: data)
    }

    /// The one document this session's importer acts on. Checks `errors`
    /// before `data`: an API error alongside an empty result is reported as
    /// the error, not as "not found".
    package static func firstDocument(in response: MaterialsProjectSummaryResponse) throws -> MaterialsProjectDocument {
        if let first = response.errors.first {
            throw Failure.apiError(code: first.code, message: first.message)
        }
        guard let doc = response.data.first else {
            throw Failure.emptyResult("the response's data array was empty.")
        }
        return doc
    }

    /// Build a validated `CrystalModel` from one fetched document.
    ///
    /// Structural absence (`structure`/`lattice`/`sites` missing, a site with
    /// no coordinates, no species, or an unrecognized element symbol) is
    /// checked explicitly here, because there is no value to fall back on.
    /// Everything else a *number* can get wrong — non-finite cell parameters,
    /// non-finite fractional coordinates, an occupancy out of (0, 1], an
    /// unsupported element's missing scattering factors, atoms too close
    /// together — is left to `CrystalModel.validationIssues`, the same gate
    /// every built-in, custom and CIF-imported model already passes through;
    /// re-checking those here would be a second, divergeable copy of that
    /// logic. Any non-empty `validationIssues` becomes `.malformed`.
    package static func crystalModel(from doc: MaterialsProjectDocument, fetchedAt: Date) throws -> CrystalModel {
        guard let originalStructure = doc.structure else {
            throw Failure.malformed("\(doc.materialID) has no structure block.")
        }
        guard originalStructure.lattice != nil else {
            throw Failure.malformed("\(doc.materialID)'s structure has no lattice.")
        }
        guard let originalSites = originalStructure.sites, !originalSites.isEmpty else {
            throw Failure.malformed("\(doc.materialID)'s structure lists no atomic sites.")
        }

        // Standardise BEFORE family classification (session S4b, Gate D):
        // the served cell is normally the relaxed PRIMITIVE cell for a
        // centred lattice, and classifying that metric directly mis-scores
        // the family (an FCC primitive is a=b=c, α=β=γ=60° — `.identity`,
        // not `.cubic`). See `CellStandardisation`'s header and `standardise`.
        let structure: MaterialsProjectStructure
        let cellHow: CellStandardisation
        do {
            (structure, cellHow) = try standardise(originalStructure, symmetry: doc.symmetry)
        } catch Failure.nonStandardCell(let reason) {
            throw Failure.nonStandardCell(
                "\(doc.materialID): \(reason) Import a conventional CIF for this phase instead."
            )
        }

        guard let lattice = structure.lattice else {
            throw Failure.malformed("\(doc.materialID)'s structure has no lattice.")
        }
        guard let rawSites = structure.sites, !rawSites.isEmpty else {
            throw Failure.malformed("\(doc.materialID)'s structure lists no atomic sites.")
        }

        var atomSites: [AtomSite] = []
        atomSites.reserveCapacity(rawSites.count)
        for (index, site) in rawSites.enumerated() {
            guard let abc = site.abc, abc.count == 3 else {
                throw Failure.malformed(
                    "Site \(index) of \(doc.materialID) has no usable fractional coordinates."
                )
            }
            guard let species = site.species, !species.isEmpty else {
                throw Failure.malformed("Site \(index) of \(doc.materialID) lists no species.")
            }
            let fractional = SIMD3(abc[0], abc[1], abc[2])
            for sp in species {
                let symbol = CIFImport.elementSymbol(from: sp.element)
                guard let z = CIFImport.elementSymbolToZ[symbol] else {
                    throw Failure.malformed(
                        "Site \(index) of \(doc.materialID) has an unrecognized element symbol \"\(sp.element)\"."
                    )
                }
                atomSites.append(AtomSite(z: z, fractional: fractional, occupancy: sp.occu))
            }
        }

        let crystal = Crystal(
            a: lattice.a, b: lattice.b, c: lattice.c,
            alphaDeg: lattice.alpha, betaDeg: lattice.beta, gammaDeg: lattice.gamma,
            sites: atomSites
        )

        // Verbatim reuse, not a re-implementation — see the file header and
        // docs/v3-materials-project-preregistration.md. MP's own
        // `symmetry.crystal_system` never reaches this decision; it is
        // recorded in provenance below only.
        let symmetry = try CIFImport.classifyFamily(
            a: lattice.a, b: lattice.b, c: lattice.c,
            alphaDeg: lattice.alpha, betaDeg: lattice.beta, gammaDeg: lattice.gamma
        )

        let formulaLabel = doc.formulaPretty?.trimmingCharacters(in: .whitespaces)
        let displayName: String
        if let formulaLabel, !formulaLabel.isEmpty {
            displayName = "\(formulaLabel) (\(doc.materialID))"
        } else {
            displayName = doc.materialID
        }

        let cellProvenance: String
        switch cellHow {
        case .asServed:
            cellProvenance = "as served"
        case .conventional(let centring):
            cellProvenance = "conventional from \(centring)-centred primitive"
        }
        var extraProvenance: [String: String] = [
            "materials_project_id": doc.materialID,
            "materials_project_fetched": isoFormatter.string(from: fetchedAt),
            "materials_project_cell": cellProvenance,
        ]
        if doc.deprecated == true {
            extraProvenance["materials_project_deprecated"] = "true"
        }
        if let symbol = doc.symmetry?.symbol {
            extraProvenance["materials_project_symbol"] = symbol
        }
        if let crystalSystem = doc.symmetry?.crystalSystem {
            extraProvenance["materials_project_crystal_system"] = crystalSystem
        }

        let model = CrystalModel(
            id: doc.materialID,
            displayName: displayName,
            crystal: crystal,
            symmetry: symmetry,
            source: .materialsProject,
            spaceGroupNumber: doc.symmetry?.number,
            extraProvenance: extraProvenance
        )
        let issues = model.validationIssues
        guard issues.isEmpty else {
            throw Failure.malformed(
                "\(doc.materialID) failed validation: \(issues.map(\.message).joined(separator: "; "))"
            )
        }
        return model
    }

    /// Grades a fetched document against what the user expected.
    ///
    /// Formula comparison is order-independent by literal element counts —
    /// "LiAl2Cu" == "Al2CuLi", but "Al2Cu" != "AlCu" (counts are compared as
    /// written, never reduced to a smallest ratio). A formula match does
    /// **not** imply `.matches` on its own: when a space-group expectation is
    /// also given, both must agree — the owner's rule that formula alone is
    /// not enough to confirm a phase (mp-1185307 misidentified this way,
    /// 2026-09-17).
    package static func check(
        _ doc: MaterialsProjectDocument, against expectation: PhaseExpectation
    ) -> PhaseExpectationVerdict {
        guard expectation.formula != nil || expectation.spaceGroupNumber != nil else {
            return .unchecked
        }

        if let expectedFormula = expectation.formula {
            guard let expectedCounts = parseFormula(expectedFormula) else {
                return .mismatch(reason: "Could not parse expected formula \"\(expectedFormula)\".")
            }
            guard let docFormula = doc.formulaPretty, let docCounts = parseFormula(docFormula) else {
                return .mismatch(
                    reason: "\(doc.materialID) has no usable formula to compare against \"\(expectedFormula)\"."
                )
            }
            guard docCounts == expectedCounts else {
                return .mismatch(reason: "\(doc.materialID) is \(docFormula); expected \(expectedFormula).")
            }
        }

        if let expectedSpaceGroup = expectation.spaceGroupNumber {
            let actualSpaceGroup = doc.symmetry?.number
            guard actualSpaceGroup == expectedSpaceGroup else {
                let docFormulaLabel = doc.formulaPretty ?? doc.materialID
                let actualDescription: String
                if let actualSpaceGroup {
                    if let actualSymbol = doc.symmetry?.symbol {
                        actualDescription = "\(actualSymbol) (\(actualSpaceGroup))"
                    } else {
                        actualDescription = "space group \(actualSpaceGroup)"
                    }
                } else {
                    actualDescription = "an unrecorded space group"
                }
                return .mismatch(
                    reason: "\(doc.materialID) is \(docFormulaLabel) in \(actualDescription); "
                        + "expected space group \(expectedSpaceGroup)."
                )
            }
        }

        return .matches
    }

    /// Parses "element symbol + optional integer count" chemical formulas
    /// with no parentheses, e.g. "LiAl2Cu" -> ["Li": 1, "Al": 2, "Cu": 1].
    /// Returns nil on anything else (lowercase-leading token, punctuation, an
    /// empty string, a zero/negative count) rather than guessing.
    private static func parseFormula(_ text: String) -> [String: Int]? {
        var result: [String: Int] = [:]
        let chars = Array(text)
        guard !chars.isEmpty else { return nil }
        var i = 0
        while i < chars.count {
            guard chars[i].isASCII, chars[i].isUppercase, chars[i].isLetter else { return nil }
            var symbol = String(chars[i])
            i += 1
            while i < chars.count, chars[i].isASCII, chars[i].isLowercase, chars[i].isLetter {
                symbol.append(chars[i])
                i += 1
            }
            var digits = ""
            while i < chars.count, chars[i].isASCII, chars[i].isNumber {
                digits.append(chars[i])
                i += 1
            }
            let count = digits.isEmpty ? 1 : Int(digits)
            guard let count, count > 0 else { return nil }
            result[symbol, default: 0] += count
        }
        return result
    }

    /// ISO-8601 UTC, fixed regardless of the caller's calendar/time zone —
    /// `materials_project_fetched` records when mac4DSTEM asked, not a
    /// locale-dependent rendering of it.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
