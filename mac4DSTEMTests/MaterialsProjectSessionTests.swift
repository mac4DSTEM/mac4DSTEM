//
//  MaterialsProjectSessionTests.swift
//  Coverage for session S5's App/Session half of the Materials Project
//  importer: `MaterialsProjectSettings` (the Settings-scene owner),
//  `AppState.fetchMaterialsProject`/`importFetchedCrystalModel`, and the
//  pure `canImport(outcome:)` decision the sheet's Import button reads.
//
//  Every `AppState` here is built with an in-memory `APIKeyStore` — never the
//  default `KeychainAPIKeyStore()` — so these tests can never read or write
//  the real Keychain item a developer's own Materials Project key lives in.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class MaterialsProjectSessionTests: XCTestCase {

    // MARK: - Fixtures

    /// A stub transport that never touches the network. `callCount` is what
    /// test (c) checks to prove a missing key short-circuits before any
    /// request is built.
    private final class StubTransport: MaterialsProjectTransport {
        let statusCode: Int
        let body: Data
        private(set) var callCount = 0

        init(statusCode: Int, body: Data) {
            self.statusCode = statusCode
            self.body = body
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            callCount += 1
            let url = request.url ?? URL(string: "https://api.materialsproject.org/materials/summary/")!
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        }
    }

    private func appState(key: String? = nil) -> AppState {
        AppState(materialsProject: MaterialsProjectSettings(store: InMemoryAPIKeyStore(initial: key)))
    }

    /// A single-site cubic Si document/model pair, same shape as
    /// `MaterialsProjectImportTests.siliconJSON` — built directly rather than
    /// round-tripped through JSON, since (f)'s tests need a `CrystalModel`
    /// and never touch the network.
    private func siliconFixture() throws -> (MaterialsProjectDocument, CrystalModel) {
        let doc = MaterialsProjectDocument(
            materialID: "mp-149", formulaPretty: "Si",
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(a: 5.431, b: 5.431, c: 5.431, alpha: 90, beta: 90, gamma: 90),
                sites: [MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Si", occu: 1.0)], abc: [0, 0, 0])]
            ),
            // `crystalSystem` is required from S4b's `standardise` step
            // onward: an F-centred symbol with no reported crystal system
            // refuses as `.nonStandardCell` rather than guessing. This cell
            // is already the conventional one (a=b=c, 90°), so it passes the
            // "already conventional" shortcut without needing the eight-site
            // expansion `siliconJSON` (`MaterialsProjectImportTests.swift`)
            // exercises.
            symmetry: MaterialsProjectSymmetry(crystalSystem: "cubic", symbol: "Fd-3m", number: 227)
        )
        let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: Date())
        return (doc, model)
    }

    /// mp-134, Al FCC, space group 225 — the "expectation matches" fixture.
    private static let alMatchJSON = """
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
          },
          "symmetry": {"crystal_system": "cubic", "symbol": "Fm-3m", "number": 225, "point_group": "m-3m", "hall": "-F 4 2 3"}
        }
      ],
      "errors": []
    }
    """

    /// mp-1185307: real Fm-3m/225 LiAl2Cu, checked against the T1 precipitate
    /// (Al2CuLi, P6/mmm/191) it is not — the owner's misidentification case
    /// (2026-09-17, `py4dstem-headtohead-recipe`). The cell/sites here are a
    /// stand-in cubic lattice sized to clear the close-contact gate; only
    /// `formula_pretty` and `symmetry.number` are load-bearing for `check`.
    private static let lial2cuJSON = """
    {
      "data": [
        {
          "material_id": "mp-1185307",
          "formula_pretty": "LiAl2Cu",
          "structure": {
            "lattice": {"a": 6.0, "b": 6.0, "c": 6.0, "alpha": 90, "beta": 90, "gamma": 90},
            "sites": [
              {"species": [{"element": "Li", "occu": 1.0}], "abc": [0.0, 0.0, 0.0]},
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.5, 0.5, 0.0]},
              {"species": [{"element": "Al", "occu": 1.0}], "abc": [0.5, 0.0, 0.5]},
              {"species": [{"element": "Cu", "occu": 1.0}], "abc": [0.0, 0.5, 0.5]}
            ]
          },
          "symmetry": {"crystal_system": "cubic", "symbol": "Fm-3m", "number": 225, "point_group": "m-3m", "hall": "-F 4 2 3"}
        }
      ],
      "errors": []
    }
    """

    // MARK: - (a) MaterialsProjectSettings

    func testSettingsSaveSetsHasKeyAndRemoveClearsIt() throws {
        let settings = MaterialsProjectSettings(store: InMemoryAPIKeyStore())
        XCTAssertFalse(settings.hasKey)
        try settings.save("test-key-123")
        XCTAssertTrue(settings.hasKey)
        XCTAssertEqual(settings.currentKey(), "test-key-123")
        try settings.remove()
        XCTAssertFalse(settings.hasKey)
        XCTAssertNil(settings.currentKey())
    }

    // MARK: - (b) fetchMaterialsProject: matches and the T1 mismatch

    func testFetchReturnsMatchesWhenFormulaAndSpaceGroupAgree() async throws {
        let state = appState(key: "test-key")
        let transport = StubTransport(statusCode: 200, body: Data(Self.alMatchJSON.utf8))
        let outcome = await state.fetchMaterialsProject(
            materialID: "mp-134",
            expectation: PhaseExpectation(formula: "Al", spaceGroupNumber: 225),
            transport: transport
        )
        guard case .fetched(let document, let model, let verdict, _) = outcome else {
            return XCTFail("expected .fetched, got \(outcome)")
        }
        XCTAssertEqual(document.materialID, "mp-134")
        XCTAssertEqual(model.source, .materialsProject)
        XCTAssertEqual(verdict, .matches)
        XCTAssertEqual(transport.callCount, 1)
    }

    func testFetchReturnsMismatchForTheLiAl2CuVsT1Case() async throws {
        let state = appState(key: "test-key")
        let transport = StubTransport(statusCode: 200, body: Data(Self.lial2cuJSON.utf8))
        let outcome = await state.fetchMaterialsProject(
            materialID: "mp-1185307",
            expectation: PhaseExpectation(formula: "Al2CuLi", spaceGroupNumber: 191),
            transport: transport
        )
        guard case .fetched(_, _, let verdict, _) = outcome else {
            return XCTFail("expected .fetched, got \(outcome)")
        }
        guard case .mismatch(let reason) = verdict else {
            return XCTFail("expected .mismatch, got \(verdict)")
        }
        XCTAssertTrue(reason.contains("225"), reason)
        XCTAssertTrue(reason.contains("191"), reason)
    }

    // MARK: - (c) No key: .noAPIKey, transport never called

    func testFetchWithNoStoredKeyNeverCallsTransport() async throws {
        let state = appState(key: nil)
        let transport = StubTransport(statusCode: 200, body: Data(Self.alMatchJSON.utf8))
        let outcome = await state.fetchMaterialsProject(
            materialID: "mp-134", expectation: PhaseExpectation(), transport: transport
        )
        guard case .noAPIKey = outcome else {
            return XCTFail("expected .noAPIKey, got \(outcome)")
        }
        XCTAssertEqual(transport.callCount, 0)
    }

    // MARK: - (d) 401: failure text names the key

    func testFetch401NamesTheKeyAsRejected() async throws {
        let state = appState(key: "a-bad-key")
        let body = #"{"data": [], "errors": [{"code": 401, "message": "invalid API key"}]}"#
        let transport = StubTransport(statusCode: 401, body: Data(body.utf8))
        let outcome = await state.fetchMaterialsProject(
            materialID: "mp-134", expectation: PhaseExpectation(), transport: transport
        )
        guard case .failure(let message) = outcome else {
            return XCTFail("expected .failure, got \(outcome)")
        }
        XCTAssertTrue(message.lowercased().contains("key"), message)
    }

    // MARK: - (e) importFetchedCrystalModel

    func testImportFetchedCrystalModelStoresImportedSelectionAndSource() throws {
        let state = appState()
        let (_, model) = try siliconFixture()
        state.importFetchedCrystalModel(model)
        XCTAssertEqual(state.acomSession.importedCrystalModels.map(\.id), [model.id])
        XCTAssertEqual(state.acomSession.importedCrystalModels.first?.source, .materialsProject)
        XCTAssertEqual(state.acomSession.modelSelection, CrystalModelSelection.imported(model.id))
    }

    func testImportFetchedCrystalModelWithPhaseSlotAlsoAddsToPhaseMapping() throws {
        let state = appState()
        let (_, model) = try siliconFixture()
        XCTAssertTrue(state.phaseMapping.phases.isEmpty)
        state.importFetchedCrystalModel(model, addAsPhaseSlot: true)
        XCTAssertEqual(state.phaseMapping.phases.map(\.model.id), [model.id])
        // First phase into an empty list becomes the matrix.
        XCTAssertEqual(state.phaseMapping.phases.first?.isMatrix, true)
    }

    // MARK: - (f) canImport(outcome:) — pure, no network

    func testCanImportTrueForMatchesAndUnchecked() throws {
        let (doc, model) = try siliconFixture()
        XCTAssertTrue(canImport(outcome: .fetched(document: doc, model: model, verdict: .matches, fetchedAt: Date())))
        XCTAssertTrue(canImport(outcome: .fetched(document: doc, model: model, verdict: .unchecked, fetchedAt: Date())))
    }

    func testCanImportFalseForMismatchFailureNoKeyAndNoFetchYet() throws {
        let (doc, model) = try siliconFixture()
        XCTAssertFalse(canImport(outcome: .fetched(
            document: doc, model: model, verdict: .mismatch(reason: "x"), fetchedAt: Date()
        )))
        XCTAssertFalse(canImport(outcome: .failure("x")))
        XCTAssertFalse(canImport(outcome: .noAPIKey))
        XCTAssertFalse(canImport(outcome: nil))
    }
}
