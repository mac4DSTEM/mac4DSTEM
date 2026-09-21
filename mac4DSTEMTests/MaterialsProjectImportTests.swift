import XCTest
import Security
import simd
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

    // MARK: - (l) Session S4b: primitive-cell standardisation

    /// `a,b,c,α,β,γ` for a lattice given as three Cartesian row vectors,
    /// using the same convention `Crystal.init` and
    /// `MaterialsProjectImport.standardise` use: α between rows 1/2 (b,c), β
    /// between rows 0/2 (a,c), γ between rows 0/1 (a,b). Computed rather than
    /// hand-derived so every fixture's served `a,b,c,α,β,γ` is guaranteed
    /// consistent with its `matrix`, the way a real MP payload's are.
    private func latticeParams(
        _ rows: [SIMD3<Double>]
    ) -> (a: Double, b: Double, c: Double, alpha: Double, beta: Double, gamma: Double) {
        func angleDegrees(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> Double {
            let cosTheta = dot(u, v) / (length(u) * length(v))
            return acos(min(1, max(-1, cosTheta))) * 180 / .pi
        }
        return (
            length(rows[0]), length(rows[1]), length(rows[2]),
            angleDegrees(rows[1], rows[2]), angleDegrees(rows[0], rows[2]), angleDegrees(rows[0], rows[1])
        )
    }

    private func assertFractionalSite(
        _ sites: [AtomSite], contains expected: SIMD3<Double>, z: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let found = sites.contains { site in
            site.z == z
                && axisDelta(site.fractional.x, expected.x) < 1e-6
                && axisDelta(site.fractional.y, expected.y) < 1e-6
                && axisDelta(site.fractional.z, expected.z) < 1e-6
        }
        XCTAssertTrue(
            found,
            "expected a Z=\(z) site at \(expected), got \(sites.filter { $0.z == z }.map(\.fractional))",
            file: file, line: line
        )
    }

    // (a) Cubic Si mp-149 as MP actually serves it: the F-centred primitive
    // cell (a=b=c=3.8404, α=β=γ=60°), not the already-conventional fixture
    // `siliconJSON` above uses.
    func testSiliconFCentredPrimitiveStandardisesToConventionalCubicEightSites() throws {
        let a = 5.431
        let half = a / 2
        let matrix: [[Double]] = [[0, half, half], [half, 0, half], [half, half, 0]]
        let rows = matrix.map { SIMD3($0[0], $0[1], $0[2]) }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        // Sanity: this really is the F-centred primitive the pre-registration
        // names (a=b=c, 60°), not accidentally already conventional.
        XCTAssertEqual(pa, 3.8404, accuracy: 1e-3)
        XCTAssertEqual(pb, pa, accuracy: 1e-9)
        XCTAssertEqual(palpha, 60, accuracy: 1e-6)
        XCTAssertEqual(pbeta, 60, accuracy: 1e-6)
        XCTAssertEqual(pgamma, 60, accuracy: 1e-6)

        let doc = MaterialsProjectDocument(
            materialID: "mp-149", formulaPretty: "Si",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0, 0, 0]),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0.25, 0.25, 0.25]
                    ),
                ]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "cubic", symbol: "Fd-3m", number: 227)
        )

        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertEqual(model.crystal.sites.count, 8)
        XCTAssertEqual(model.crystal.a, 5.431, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.b, 5.431, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.c, 5.431, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.alphaDeg, 90, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.betaDeg, 90, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.gammaDeg, 90, accuracy: 1e-6)
        XCTAssertEqual(model.provenance["materials_project_cell"], "conventional from F-centred primitive")
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")

        // The row-vector convention x_c = x_p·M⁻¹, plus the four F-centring
        // translations, must reproduce exactly the eight diamond-cubic sites
        // (verified by hand, 2026-09-21, before writing `Matrix3` — see its
        // doc comments in MaterialsProjectImport.swift).
        for p in [
            SIMD3(0.0, 0.0, 0.0), SIMD3(0.0, 0.5, 0.5), SIMD3(0.5, 0.0, 0.5), SIMD3(0.5, 0.5, 0.0),
            SIMD3(0.25, 0.25, 0.25), SIMD3(0.25, 0.75, 0.75), SIMD3(0.75, 0.25, 0.75), SIMD3(0.75, 0.75, 0.25),
        ] {
            assertFractionalSite(model.crystal.sites, contains: p, z: CIFImport.elementSymbolToZ["Si"]!)
        }
    }

    // (b) LiAl2Cu Heusler mp-1185307, served as its 4-atom F-centred
    // primitive. The owner's example (misidentified via formula alone,
    // 2026-09-17) must still mismatch a wrong space-group expectation after
    // standardisation.
    func testHeuslerLiAl2CuFCentredPrimitiveStandardisesTo16ConventionalSites() throws {
        let a = 5.98
        let half = a / 2
        let matrix: [[Double]] = [[0, half, half], [half, 0, half], [half, half, 0]]
        let rows = matrix.map { SIMD3($0[0], $0[1], $0[2]) }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        let doc = MaterialsProjectDocument(
            materialID: "mp-1185307", formulaPretty: "LiAl2Cu",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Li", occu: 1.0)], abc: [0, 0, 0]),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Cu", occu: 1.0)], abc: [0.5, 0.5, 0.5]
                    ),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Al", occu: 1.0)], abc: [0.25, 0.25, 0.25]
                    ),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Al", occu: 1.0)], abc: [0.75, 0.75, 0.75]
                    ),
                ]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "cubic", symbol: "Fm-3m", number: 225)
        )

        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertEqual(model.crystal.sites.count, 16)
        XCTAssertEqual(model.crystal.a, 5.98, accuracy: 1e-6)
        XCTAssertEqual(model.provenance["materials_project_cell"], "conventional from F-centred primitive")
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")

        guard case .mismatch = MaterialsProjectImport.check(
            doc, against: PhaseExpectation(formula: "Al2CuLi", spaceGroupNumber: 191)
        ) else {
            return XCTFail("expected the owner's example to still mismatch after standardisation")
        }
    }

    // (c) bcc Fe (Im-3m 229): the rhombohedral I-centred primitive.
    func testBCCIronICentredPrimitiveStandardisesToConventionalTwoSiteCell() throws {
        let a = 2.8713
        let half = a / 2
        let matrix: [[Double]] = [[-half, half, half], [half, -half, half], [half, half, -half]]
        let rows = matrix.map { SIMD3($0[0], $0[1], $0[2]) }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        XCTAssertEqual(pa, 2.4866, accuracy: 1e-3)
        XCTAssertEqual(palpha, 109.471, accuracy: 1e-2)

        let doc = MaterialsProjectDocument(
            materialID: "mp-13", formulaPretty: "Fe",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Fe", occu: 1.0)], abc: [0, 0, 0])]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "cubic", symbol: "Im-3m", number: 229)
        )

        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.symmetry, .cubic)
        XCTAssertEqual(model.crystal.sites.count, 2)
        XCTAssertEqual(model.crystal.a, 2.8713, accuracy: 1e-6)
        XCTAssertEqual(model.provenance["materials_project_cell"], "conventional from I-centred primitive")
        for p in [SIMD3(0.0, 0.0, 0.0), SIMD3(0.5, 0.5, 0.5)] {
            assertFractionalSite(model.crystal.sites, contains: p, z: CIFImport.elementSymbolToZ["Fe"]!)
        }
    }

    // (d) θ′ Al2Cu (I-4m2 119, tetragonal): the body-centred tetragonal
    // primitive. Tetragonal is not orientation-mappable yet, so `.identity`
    // is the correct (still usable) family — the point of this fixture is
    // that the CELL comes out right, not that tetragonal gets a family.
    func testThetaPrimeAl2CuBodyCentredTetragonalPrimitiveStandardisesToSixSites() throws {
        let a = 4.04, c = 5.80
        let ah = a / 2, ch = c / 2
        let matrix: [[Double]] = [[-ah, ah, ch], [ah, -ah, ch], [ah, ah, -ch]]
        let rows = matrix.map { SIMD3($0[0], $0[1], $0[2]) }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        let doc = MaterialsProjectDocument(
            materialID: "mp-1200517", formulaPretty: "Al2Cu",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Al", occu: 1.0)], abc: [0, 0, 0]),
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Al", occu: 1.0)], abc: [0.5, 0.5, 0]),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Cu", occu: 1.0)], abc: [0.75, 0.25, 0.5]
                    ),
                ]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "tetragonal", symbol: "I-4m2", number: 119)
        )

        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.symmetry, .identity)
        XCTAssertEqual(model.crystal.sites.count, 6)
        XCTAssertEqual(model.crystal.a, 4.04, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.b, 4.04, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.c, 5.80, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.alphaDeg, 90, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.betaDeg, 90, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.gammaDeg, 90, accuracy: 1e-6)
        XCTAssertTrue(model.isUsable, "\(model.validationIssues)")
        XCTAssertFalse(model.supportsOrientationMapping)
        XCTAssertEqual(model.provenance["materials_project_cell"], "conventional from I-centred primitive")
        for (p, symbol) in [
            (SIMD3(0.0, 0.0, 0.0), "Al"), (SIMD3(0.0, 0.0, 0.5), "Al"), (SIMD3(0.5, 0.5, 0.5), "Al"),
            (SIMD3(0.5, 0.5, 0.0), "Al"), (SIMD3(0.0, 0.5, 0.25), "Cu"), (SIMD3(0.5, 0.0, 0.75), "Cu"),
        ] {
            assertFractionalSite(model.crystal.sites, contains: p, z: CIFImport.elementSymbolToZ[symbol]!)
        }
    }

    // (e) Mg (P6_3/mmc, hexagonal): `magnesiumJSON` above is `P`-centred and
    // already conventional — confirms it takes the `.asServed` path, not
    // that it happens to already look right.
    func testMagnesiumPCentredConventionalCellStandardisesAsServed() throws {
        let response = try decodeResponse(magnesiumJSON)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.provenance["materials_project_cell"], "as served")
        XCTAssertEqual(model.crystal.sites.count, 2)
    }

    // (f) NEGATIVE, strengthened from the original brief. The brief's literal
    // fixture — an F cell served on a doubled/non-reduced primitive basis
    // (a/2·(0,1,1), a/2·(1,0,1), a·(1,1,0)) — was checked by hand: the
    // doubled third vector makes the F-transform produce a non-cubic
    // parallelepiped, so guard (a) (the metric check) refuses it before
    // guard (c) is ever reached, and deleting guard (c) alone (the session's
    // mandatory M2 mutation) would NOT turn this fixture green — it would
    // stay red on guard (a), failing to witness guard (c) at all. Per the
    // brief's own escape hatch ("if (f) stays green under M2, strengthen (f)
    // until it is the check's witness, and say so"), this fixture instead
    // uses a valid F-primitive basis and metric (guards (a)/(b) both pass)
    // but a served site list that lists the SAME atom twice — a data error
    // only guard (c)'s same-element distance check can see.
    func testDuplicateServedSiteIsRefusedNeverSilentlyAccepted() {
        let a = 5.431
        let half = a / 2
        let matrix: [[Double]] = [[0, half, half], [half, 0, half], [half, half, 0]]
        let rows = matrix.map { SIMD3($0[0], $0[1], $0[2]) }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        let doc = MaterialsProjectDocument(
            materialID: "mp-999002", formulaPretty: "Si",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0, 0, 0]),
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0, 0, 0]),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0.25, 0.25, 0.25]
                    ),
                ]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "cubic", symbol: "Fd-3m", number: 227)
        )

        XCTAssertThrowsError(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())) { error in
            guard case let MaterialsProjectImport.Failure.nonStandardCell(reason)? =
                error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .nonStandardCell, got \(error)")
            }
            XCTAssertTrue(reason.contains("mp-999002"), reason)
            XCTAssertTrue(reason.lowercased().contains("cif"), reason)
        }
    }

    // (g) NEGATIVE: inconsistent MP metadata — an F-centred cubic symbol
    // reported under crystal_system "hexagonal". Guard (a) refuses because
    // the standardised (cubic) cell cannot pass the hexagonal conventional
    // test (γ must be 120°, not 90°).
    func testInconsistentCentringSymbolAndCrystalSystemIsRefused() {
        let a = 5.431
        let half = a / 2
        let matrix: [[Double]] = [[0, half, half], [half, 0, half], [half, half, 0]]
        let rows = matrix.map { SIMD3($0[0], $0[1], $0[2]) }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        let doc = MaterialsProjectDocument(
            materialID: "mp-999003", formulaPretty: "Si",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [
                    MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0, 0, 0]),
                    MaterialsProjectSite(
                        species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0.25, 0.25, 0.25]
                    ),
                ]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "hexagonal", symbol: "Fm-3m", number: nil)
        )

        XCTAssertThrowsError(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())) { error in
            guard case let MaterialsProjectImport.Failure.nonStandardCell(reason)? =
                error as? MaterialsProjectImport.Failure else {
                return XCTFail("expected .nonStandardCell, got \(error)")
            }
            XCTAssertTrue(reason.contains("mp-999003"), reason)
        }
    }

    // (h) R-centred trigonal: a synthetic rhombohedral primitive (a=b=c,
    // α=β=γ≠90°) built by the exact obverse-setting formula from a chosen
    // hexagonal cell (a=4, c=13), so the standardisation's guard (a) is
    // guaranteed (by construction, to floating precision) to see it recover
    // that exact hexagonal cell. Whichever the guard produces is asserted —
    // here, success — and it must never be a silently-wrong `.hexagonal`
    // with the wrong site count.
    func testRhombohedralRCentredPrimitiveStandardisesToHexagonalThreeSites() throws {
        let aHex = 4.0, cHex = 13.0
        let vectorA = SIMD3(aHex, 0.0, 0.0)
        let vectorB = SIMD3(-aHex / 2, aHex * (3.0).squareRoot() / 2, 0.0)
        let vectorC = SIMD3(0.0, 0.0, cHex)
        // Obverse-setting primitive vectors in terms of the hexagonal axes
        // (International Tables); this is the same relation that makes the
        // R matrix in `centringTransform(for:)` recover A,B,C exactly.
        let p1 = (2.0 / 3.0) * vectorA + (1.0 / 3.0) * vectorB + (1.0 / 3.0) * vectorC
        let p2 = (-1.0 / 3.0) * vectorA + (1.0 / 3.0) * vectorB + (1.0 / 3.0) * vectorC
        let p3 = (-1.0 / 3.0) * vectorA + (-2.0 / 3.0) * vectorB + (1.0 / 3.0) * vectorC
        let rows = [p1, p2, p3]
        let matrix = rows.map { [$0.x, $0.y, $0.z] }
        let (pa, pb, pc, palpha, pbeta, pgamma) = latticeParams(rows)

        // Sanity: a genuine rhombohedral primitive (a=b=c, one non-90° angle
        // repeated three times), not accidentally already conventional.
        XCTAssertEqual(pa, pb, accuracy: 1e-6)
        XCTAssertEqual(pb, pc, accuracy: 1e-6)
        XCTAssertEqual(palpha, pbeta, accuracy: 1e-6)
        XCTAssertEqual(pbeta, pgamma, accuracy: 1e-6)
        XCTAssertTrue(abs(palpha - 90) > 1, "expected a non-90° rhombohedral angle, got \(palpha)")

        let doc = MaterialsProjectDocument(
            materialID: "mp-999004", formulaPretty: "Bi",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(
                    a: pa, b: pb, c: pc, alpha: palpha, beta: pbeta, gamma: pgamma, matrix: matrix
                ),
                sites: [MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Bi", occu: 1.0)], abc: [0, 0, 0])]
            ),
            symmetry: MaterialsProjectSymmetry(crystalSystem: "trigonal", symbol: "R-3m", number: 166)
        )

        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        XCTAssertEqual(model.symmetry, .hexagonal)
        XCTAssertEqual(model.crystal.sites.count, 3)
        XCTAssertEqual(model.crystal.a, aHex, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.b, aHex, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.c, cHex, accuracy: 1e-6)
        XCTAssertEqual(model.crystal.gammaDeg, 120, accuracy: 1e-6)
        XCTAssertEqual(model.provenance["materials_project_cell"], "conventional from R-centred primitive")
    }

    /// The live API omits `errors` (and `meta`) on success — the owner's first
    /// real fetch (mp-134, 2026-09-21) failed on exactly this key.
    func testLiveResponseWithoutErrorsKeyDecodes() throws {
        let json = """
        {"data":[{"material_id":"mp-134","formula_pretty":"Al","structure":{"lattice":{"a":4.05,"b":4.05,"c":4.05,"alpha":90,"beta":90,"gamma":90,"volume":66.4},"sites":[{"species":[{"element":"Al","occu":1}],"abc":[0,0,0]},{"species":[{"element":"Al","occu":1}],"abc":[0,0.5,0.5]},{"species":[{"element":"Al","occu":1}],"abc":[0.5,0,0.5]},{"species":[{"element":"Al","occu":1}],"abc":[0.5,0.5,0]}]},"symmetry":{"symbol":"Fm-3m","number":225,"crystal_system":"Cubic"}}],"meta":{"api_version":"v3"}}
        """
        let response = try MaterialsProjectImport.decode(Data(json.utf8))
        XCTAssertTrue(response.errors.isEmpty)
        let doc = try MaterialsProjectImport.firstDocument(in: response)
        XCTAssertEqual(doc.materialID, "mp-134")
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(model.symmetry, .cubic)
    }
}
