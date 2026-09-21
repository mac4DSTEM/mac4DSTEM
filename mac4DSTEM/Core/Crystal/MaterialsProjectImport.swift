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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
    package init(a: Double, b: Double, c: Double, alpha: Double, beta: Double, gamma: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.alpha = alpha
        self.beta = beta
        self.gamma = gamma
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
            }
        }
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
        guard let structure = doc.structure else {
            throw Failure.malformed("\(doc.materialID) has no structure block.")
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

        var extraProvenance: [String: String] = [
            "materials_project_id": doc.materialID,
            "materials_project_fetched": isoFormatter.string(from: fetchedAt),
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
