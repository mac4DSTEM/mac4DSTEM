import XCTest
import Security
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Coverage for session S4a's Materials Project Core plumbing
/// (`MaterialsProjectImport`, `PhaseExpectation`, and the Keychain-backed
/// `APIKeyStore`). Fixtures are inline JSON strings, matching the convention
/// `CIFImportTests` uses for CIF text.
final class MaterialsProjectImportTests: XCTestCase {

    // MARK: - Helpers

    private func decodeResponse(_ json: String) throws -> MaterialsProjectSummaryResponse {
        try MaterialsProjectImport.decode(Data(json.utf8))
    }

    private func cifText(a: Double, b: Double, c: Double, alpha: Double, beta: Double, gamma: Double) -> String {
        [
            "data_probe",
            "_cell_length_a \(a)",
            "_cell_length_b \(b)",
            "_cell_length_c \(c)",
            "_cell_angle_alpha \(alpha)",
            "_cell_angle_beta \(beta)",
            "_cell_angle_gamma \(gamma)",
            "loop_",
            "_atom_site_label",
            "_atom_site_type_symbol",
            "_atom_site_fract_x",
            "_atom_site_fract_y",
            "_atom_site_fract_z",
            "Fe1 Fe 0.0 0.0 0.0",
        ].joined(separator: "\n")
    }

    // MARK: - (a) Cubic Si mp-149

    private let siliconJSON = """
    {
      "data": [
        {
          "material_id": "mp-149",
          "formula_pretty": "Si",
          "deprecated": false,
          "last_updated": "2020-01-01T00:00:00.000000",
          "structure": {
            "lattice": {"a": 5.431, "b": 5.431, "c": 5.431, "alpha": 90, "beta": 90, "gamma": 90},
            "sites": [
              {"label": "Si1", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.0, 0.0, 0.0]},
              {"label": "Si2", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.5, 0.5, 0.0]},
              {"label": "Si3", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.5, 0.0, 0.5]},
              {"label": "Si4", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.0, 0.5, 0.5]},
              {"label": "Si5", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.25, 0.25, 0.25]},
              {"label": "Si6", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.75, 0.75, 0.25]},
              {"label": "Si7", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.75, 0.25, 0.75]},
              {"label": "Si8", "species": [{"element": "Si", "occu": 1.0}], "abc": [0.25, 0.75, 0.75]}
            ]
          },
          "symmetry": {"crystal_system": "cubic", "symbol": "Fd-3m", "number": 227, "point_group": "m-3m", "hall": "F 4d 2 3 -1d"}
        }
      ],
      "errors": []
    }
    """

    func testSiliconCubicDocumentBuildsValidatedModel() throws {
        let response = try decodeResponse(siliconJSON)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: fetchedAt)

        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertEqual(model.spaceGroupNumber, 227)
        XCTAssertEqual(model.crystal.sites.count, 8)
        XCTAssertEqual(model.source, .materialsProject)
        XCTAssertEqual(model.id, "mp-149")
        XCTAssertEqual(model.displayName, "Si (mp-149)")
        XCTAssertTrue(model.supportsOrientationMapping)
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")

        let provenance = model.provenance
        XCTAssertEqual(provenance["materials_project_id"], "mp-149")
        XCTAssertEqual(provenance["space_group_number"], "227")
        XCTAssertEqual(provenance["materials_project_symbol"], "Fd-3m")
        XCTAssertEqual(provenance["materials_project_crystal_system"], "cubic")
        guard let fetchedString = provenance["materials_project_fetched"] else {
            return XCTFail("expected materials_project_fetched in provenance")
        }
        let parsedBack = ISO8601DateFormatter().date(from: fetchedString)
        XCTAssertNotNil(parsedBack)
        XCTAssertEqual(parsedBack?.timeIntervalSince1970 ?? -1, fetchedAt.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - (b) Hexagonal Mg-like

    private let magnesiumJSON = """
    {
      "data": [
        {
          "material_id": "mp-153",
          "formula_pretty": "Mg",
          "structure": {
            "lattice": {"a": 3.209, "b": 3.209, "c": 5.211, "alpha": 90, "beta": 90, "gamma": 120},
            "sites": [
              {"species": [{"element": "Mg", "occu": 1.0}], "abc": [0.0, 0.0, 0.0]},
              {"species": [{"element": "Mg", "occu": 1.0}], "abc": [0.6666666667, 0.3333333333, 0.5]}
            ]
          },
          "symmetry": {"crystal_system": "hexagonal", "symbol": "P6_3/mmc", "number": 194, "point_group": "6/mmm", "hall": "-P 6c 2c"}
        }
      ],
      "errors": []
    }
    """

    func testMagnesiumHexagonalDocumentClassifiesHexagonal() throws {
        let response = try decodeResponse(magnesiumJSON)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())

        XCTAssertEqual(model.symmetry, .hexagonal)
        XCTAssertEqual(model.spaceGroupNumber, 194)
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")
        XCTAssertTrue(model.supportsOrientationMapping)
    }

    // MARK: - (c) Low-symmetry (monoclinic) -> .identity, still usable for ID

    private let monoclinicJSON = """
    {
      "data": [
        {
          "material_id": "mp-999001",
          "formula_pretty": "AlO",
          "structure": {
            "lattice": {"a": 6.0, "b": 4.0, "c": 5.0, "alpha": 90, "beta": 100, "gamma": 90},
            "sites": [
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.0, 0.0, 0.0]},
              {"species": [{"element": "O", "occu": 1.0}], "abc": [0.3, 0.2, 0.4]}
            ]
          },
          "symmetry": {"crystal_system": "monoclinic", "symbol": "C2/m", "number": 12, "point_group": "2/m", "hall": "-C 2y"}
        }
      ],
      "errors": []
    }
    """

    func testMonoclinicDocumentIsIdentityButStillUsableForIdentification() throws {
        let response = try decodeResponse(monoclinicJSON)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())

        XCTAssertEqual(model.symmetry, .identity)
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")
        XCTAssertFalse(model.supportsOrientationMapping)
        XCTAssertNotNil(model.orientationMappingIssue)
        XCTAssertEqual(model.spaceGroupNumber, 12)
    }

    // MARK: - (d) symmetry null -> model still builds, spaceGroupNumber nil

    private let noSymmetryJSON = """
    {
      "data": [
        {
          "material_id": "mp-134",
          "formula_pretty": "Al",
          "structure": {
            "lattice": {"a": 4.0495, "b": 4.0495, "c": 4.0495, "alpha": 90, "beta": 90, "gamma": 90},
            "sites": [
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.0, 0.0, 0.0]},
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.5, 0.5, 0.0]},
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.5, 0.0, 0.5]},
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.0, 0.5, 0.5]}
            ]
          }
        }
      ],
      "errors": []
    }
    """

    func testMissingSymmetryBlockStillBuildsModelWithNilSpaceGroup() throws {
        let response = try decodeResponse(noSymmetryJSON)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        XCTAssertNil(doc.symmetry)
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())

        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertNil(model.spaceGroupNumber)
        XCTAssertNil(model.provenance["space_group_number"])
        XCTAssertNil(model.provenance["materials_project_symbol"])
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")
    }

    // MARK: - (e) Malformed responses never crash

    func testMissingLatticeIsMalformed() throws {
        let json = """
        {"data": [{"material_id": "mp-1", "formula_pretty": "X",
          "structure": {"sites": [{"species": [{"element": "Fe", "occu": 1.0}], "abc": [0, 0, 0]}]}}],
         "errors": []}
        """
        let response = try decodeResponse(json)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        XCTAssertThrowsError(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())) { error in
            guard case let MaterialsProjectImport.Failure.malformed(reason)? =
                error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .malformed, got \(error)")
            }
            XCTAssertTrue(reason.lowercased().contains("lattice"), reason)
        }
    }

    func testEmptySitesIsMalformed() throws {
        let json = """
        {"data": [{"material_id": "mp-2", "formula_pretty": "X",
          "structure": {"lattice": {"a": 3, "b": 3, "c": 3, "alpha": 90, "beta": 90, "gamma": 90}, "sites": []}}],
         "errors": []}
        """
        let response = try decodeResponse(json)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        XCTAssertThrowsError(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())) { error in
            guard case let MaterialsProjectImport.Failure.malformed(reason)? =
                error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .malformed, got \(error)")
            }
            XCTAssertTrue(reason.lowercased().contains("site"), reason)
        }
    }

    /// JSON itself cannot encode NaN/Infinity (Foundation's `JSONDecoder`
    /// refuses even a huge exponent like `1e309` as "not representable"), so
    /// the non-finite case is built directly via the package memberwise
    /// inits rather than round-tripped through JSON text.
    func testNonFiniteCellLengthIsMalformedNeverCrashes() {
        let doc = MaterialsProjectDocument(
            materialID: "mp-3", formulaPretty: "X",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(a: .nan, b: 3, c: 3, alpha: 90, beta: 90, gamma: 90),
                sites: [MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Fe", occu: 1.0)], abc: [0, 0, 0])]
            )
        )
        XCTAssertThrowsError(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())) { error in
            guard case let MaterialsProjectImport.Failure.malformed(reason)? =
                error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .malformed, got \(error)")
            }
            XCTAssertTrue(reason.contains("mp-3"), reason)
        }
    }

    // MARK: - (f) errors array / empty data

    func testErrorsArrayThrowsAPIError() throws {
        let response = try decodeResponse(#"{"data": [], "errors": [{"code": 404, "message": "not found"}]}"#)
        XCTAssertThrowsError(try MaterialsProjectImport.firstDocument(in: response)) { error in
            guard case let MaterialsProjectImport.Failure.apiError(code, message)? =
                error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .apiError, got \(error)")
            }
            XCTAssertEqual(code, 404)
            XCTAssertEqual(message, "not found")
        }
    }

    func testEmptyDataThrowsEmptyResult() throws {
        let response = try decodeResponse(#"{"data": [], "errors": []}"#)
        XCTAssertThrowsError(try MaterialsProjectImport.firstDocument(in: response)) { error in
            guard case MaterialsProjectImport.Failure.emptyResult? = error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .emptyResult, got \(error)")
            }
        }
    }

    // MARK: - (g) Invalid ids; request URL/query/header exact

    func testInvalidMaterialIDsAreRejected() {
        for bad in ["mp149", "mp-", "1185307"] {
            XCTAssertThrowsError(try MaterialsProjectImport.request(materialID: bad, apiKey: "key")) { error in
                XCTAssertEqual(error as? MaterialsProjectImport.Failure, .invalidMaterialID(bad))
            }
        }
    }

    func testRequestURLQueryAndHeaderExact() throws {
        let request = try MaterialsProjectImport.request(materialID: "mp-149", apiKey: "test-key-123")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "test-key-123")
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return XCTFail("request has no URL")
        }
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.materialsproject.org")
        XCTAssertEqual(components.path, "/materials/summary/")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["material_ids"], "mp-149")
        XCTAssertEqual(items["_fields"], "material_id,formula_pretty,structure,symmetry,deprecated,last_updated")
    }

    // MARK: - (h) PhaseExpectation

    private func lial2cuDocument(spaceGroupNumber: Int? = 225, symbol: String? = "Fm-3m") -> MaterialsProjectDocument {
        MaterialsProjectDocument(
            materialID: "mp-1185307", formulaPretty: "LiAl2Cu",
            symmetry: MaterialsProjectSymmetry(symbol: symbol, number: spaceGroupNumber)
        )
    }

    func testPhaseExpectationSpaceGroupMismatchNamesBothNumbers() {
        let doc = lial2cuDocument()
        let verdict = MaterialsProjectImport.check(doc, against: PhaseExpectation(formula: "Al2CuLi", spaceGroupNumber: 191))
        guard case let .mismatch(reason) = verdict else {
            return XCTFail("expected .mismatch, got \(verdict)")
        }
        XCTAssertTrue(reason.contains("225"), reason)
        XCTAssertTrue(reason.contains("191"), reason)
    }

    func testPhaseExpectationFormulaOnlyMatches() {
        let doc = lial2cuDocument()
        XCTAssertEqual(MaterialsProjectImport.check(doc, against: PhaseExpectation(formula: "Al2CuLi")), .matches)
    }

    func testPhaseExpectationBothNilIsUnchecked() {
        let doc = lial2cuDocument()
        XCTAssertEqual(MaterialsProjectImport.check(doc, against: PhaseExpectation()), .unchecked)
    }

    func testPhaseExpectationFormulaCountMismatch() {
        let doc = MaterialsProjectDocument(materialID: "mp-x", formulaPretty: "Al2Cu")
        guard case .mismatch = MaterialsProjectImport.check(doc, against: PhaseExpectation(formula: "AlCu")) else {
            return XCTFail("expected .mismatch for Al2Cu vs AlCu")
        }
    }

    func testPhaseExpectationFormulaOrderIndependent() {
        for permuted in ["LiAl2Cu", "Al2CuLi", "CuLiAl2"] {
            let doc = MaterialsProjectDocument(materialID: "mp-y", formulaPretty: permuted)
            XCTAssertEqual(
                MaterialsProjectImport.check(doc, against: PhaseExpectation(formula: "Al2CuLi")), .matches,
                permuted
            )
        }
    }

    // MARK: - (i) classifyFamily reuse: same function, not parallel code

    func testClassifyFamilyReuseMatchesCIFImporterAcrossCells() throws {
        struct Cell { let a, b, c, alpha, beta, gamma: Double }
        let cells: [Cell] = [
            Cell(a: 3.209, b: 3.209, c: 5.211, alpha: 90, beta: 90, gamma: 120),  // hexagonal metric
            Cell(a: 4.05, b: 4.05, c: 4.05, alpha: 90, beta: 90, gamma: 90),      // cubic metric
            Cell(a: 6.0, b: 4.0, c: 5.0, alpha: 90, beta: 100, gamma: 90),        // monoclinic -> identity
        ]
        for cell in cells {
            let cif = cifText(a: cell.a, b: cell.b, c: cell.c, alpha: cell.alpha, beta: cell.beta, gamma: cell.gamma)
            let cifModel = try CIFImport.crystalModel(from: cif, fileBaseName: "probe")

            let doc = MaterialsProjectDocument(
                materialID: "mp-probe", formulaPretty: "Fe",
                structure: MaterialsProjectStructure(
                    lattice: MaterialsProjectLattice(
                        a: cell.a, b: cell.b, c: cell.c, alpha: cell.alpha, beta: cell.beta, gamma: cell.gamma
                    ),
                    sites: [MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Fe", occu: 1.0)], abc: [0, 0, 0])]
                )
            )
            let mpModel = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
            XCTAssertEqual(mpModel.symmetry, cifModel.symmetry, "cell a=\(cell.a) b=\(cell.b) c=\(cell.c)")
        }
    }

    // MARK: - (j) Keychain

    func testInMemoryAPIKeyStoreRoundTrips() throws {
        let store = InMemoryAPIKeyStore()
        XCTAssertNil(try store.load())
        try store.save("abc123")
        XCTAssertEqual(try store.load(), "abc123")
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testKeychainAPIKeyStoreRoundTrips() throws {
        let service = "com.mac4dstem.materials-project.test.\(UUID().uuidString)"
        let store = KeychainAPIKeyStore(service: service, account: "test-account")
        defer { try? store.delete() }

        do {
            XCTAssertNil(try store.load())
            try store.save("test-key-value")
        } catch let KeychainAPIKeyStore.KeychainFailure.unhandled(status)
            where status == errSecMissingEntitlement
                || status == errSecInteractionNotAllowed
                || status == errSecNotAvailable {
            throw XCTSkip("keychain unavailable: OSStatus \(status)")
        }

        XCTAssertEqual(try store.load(), "test-key-value")
        try store.save("updated-key-value")
        XCTAssertEqual(try store.load(), "updated-key-value")
        try store.delete()
        XCTAssertNil(try store.load())
    }

    // MARK: - (k) CIFImport space-group parsing

    private let goldSpaceGroupCIF = """
    data_gold_sg
    _cell_length_a 4.0782
    _cell_length_b 4.0782
    _cell_length_c 4.0782
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    _symmetry_Int_Tables_number 225
    loop_
    _symmetry_equiv_pos_as_xyz
    'x, y, z'
    'x+1/2, y+1/2, z'
    'x+1/2, y, z+1/2'
    'x, y+1/2, z+1/2'
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Au1 Au 0 0 0
    """

    private let goldNoSpaceGroupCIF = """
    data_gold_no_sg
    _cell_length_a 4.0782
    _cell_length_b 4.0782
    _cell_length_c 4.0782
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Au1 Au 0.0 0.0 0.0
    Au2 Au 0.5 0.5 0.0
    Au3 Au 0.5 0.0 0.5
    Au4 Au 0.0 0.5 0.5
    """

    func testCIFSpaceGroupNumberParsedWhenPresent() throws {
        let model = try CIFImport.crystalModel(from: goldSpaceGroupCIF, fileBaseName: "gold_sg")
        XCTAssertEqual(model.spaceGroupNumber, 225)
        XCTAssertEqual(model.provenance["space_group_number"], "225")
        XCTAssertEqual(model.crystal.sites.count, 4)
    }

    func testCIFSpaceGroupNumberNilWhenAbsent() throws {
        let model = try CIFImport.crystalModel(from: goldNoSpaceGroupCIF, fileBaseName: "gold_no_sg")
        XCTAssertNil(model.spaceGroupNumber)
        XCTAssertNil(model.provenance["space_group_number"])
    }
}
