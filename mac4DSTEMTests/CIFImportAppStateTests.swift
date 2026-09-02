import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// `CIFImport.swift` (`mac4DSTEMTests/CIFImportTests.swift`) only covers the
/// pure parser. This covers the AppState wiring that makes an imported CIF
/// actually reachable: `importCrystalModel(from:)`, `.imported` selection
/// resolution, error routing, and the reopen/"missing model" behaviour
/// described in `AppState.importedCrystalModels`'s doc comment.
final class CIFImportAppStateTests: XCTestCase {

    private let goldCIF = """
    data_gold
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

    private let orthorhombicCIF = """
    data_orthorhombic
    _cell_length_a 5.0
    _cell_length_b 6.0
    _cell_length_c 7.0
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    Fe1 Fe 0 0 0
    """

    /// Writes `text` to a fresh temp file with the given base name and `.cif`
    /// extension, matching what a real `.fileImporter` selection hands the
    /// app: a URL, not a `String`.
    private func writeTempCIF(_ text: String, named baseName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cif-app-state-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(baseName).cif")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Successful import selects and resolves

    func testImportingCIFAddsItAndSelectsItAndResolvedACOMModelSeesIt() throws {
        let state = AppState()
        let url = try writeTempCIF(goldCIF, named: "gold")

        state.importCrystalModel(from: url)

        XCTAssertNil(state.errorMessage, "a valid CIF must not raise the modal error")
        XCTAssertEqual(state.importedCrystalModels.count, 1)
        let imported = try XCTUnwrap(state.importedCrystalModels.first)
        XCTAssertEqual(imported.source, .imported)
        XCTAssertEqual(imported.symmetry, .cubic)
        XCTAssertEqual(state.acomModelSelection, .imported(imported.id),
                        "a successful import must select the model, not just add it")

        let resolved = try XCTUnwrap(state.resolvedACOMModel)
        XCTAssertEqual(resolved.id, imported.id)
        XCTAssertEqual(resolved.displayName, imported.displayName)
        XCTAssertNil(state.acomModelSelectionIssue)
        XCTAssertTrue(state.productWorkflowReadiness.hasSupportedACOMMaterial)
    }

    /// Re-importing a CIF with the same base name replaces the prior entry in
    /// place rather than accumulating a duplicate picker row.
    func testReimportingSameBaseNameReplacesRatherThanDuplicates() throws {
        let state = AppState()
        let firstURL = try writeTempCIF(goldCIF, named: "gold")
        state.importCrystalModel(from: firstURL)
        XCTAssertEqual(state.importedCrystalModels.count, 1)

        let secondURL = try writeTempCIF(goldCIF, named: "gold")
        state.importCrystalModel(from: secondURL)
        XCTAssertEqual(state.importedCrystalModels.count, 1,
                        "importing the same file base name again must replace, not duplicate")
    }

    // MARK: - Error routing: specific CIFImportError message, modal path

    func testRejectedPointGroupSurfacesSpecificMessageOnTheModalPath() throws {
        let state = AppState()
        let url = try writeTempCIF(orthorhombicCIF, named: "ortho")

        state.importCrystalModel(from: url)

        XCTAssertTrue(state.importedCrystalModels.isEmpty,
                       "a rejected import must not be added to the picker")
        XCTAssertEqual(state.acomModelSelection, .none,
                        "a failed import must not change the current selection")
        let message = try XCTUnwrap(state.errorMessage,
            "a bad CIF is a file-open failure, which uses the modal path (present), not the status-bar-only compute-failure path")
        XCTAssertTrue(message.contains("not cubic or hexagonal"),
                       "the point-group rejection must name the reason, not read as a generic failure: \(message)")
        XCTAssertTrue(state.statusText.contains(message))
    }

    func testUnreadableFileAlsoRoutesToTheModalPath() {
        let state = AppState()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).cif")

        state.importCrystalModel(from: missing)

        XCTAssertNotNil(state.errorMessage)
        XCTAssertTrue(state.importedCrystalModels.isEmpty)
    }

    // MARK: - Reopen behaviour: never a silent fallback to a different model

    /// `activate(descriptor:reader:)` resets `acomModelSelection` to `.none`
    /// on every dataset (re)open — for `.library`, `.customCubic`, and now
    /// `.imported` alike. This is the app's existing mechanism for Priority 1
    /// ("every result keeps its model... through reopen"): rather than
    /// persisting a phase-model selection that could silently drift or
    /// dangle, reopening a dataset always demands an explicit reselection.
    /// This test proves an imported selection follows that same rule.
    func testDatasetReactivationResetsImportedSelectionRatherThanCarryingItOver() async throws {
        let state = AppState()
        let url = try writeTempCIF(goldCIF, named: "gold")
        state.importCrystalModel(from: url)
        XCTAssertNotEqual(state.acomModelSelection, .none)

        // Simulate a reopen: activating a (demo) dataset is the same code
        // path `openFile`/`openRecent` use for both a first open and a
        // recovery-driven reopen after relaunch.
        await state.openDemoFixture()

        XCTAssertEqual(state.acomModelSelection, .none,
                        "reopening must never silently keep computing with a stale imported model")
        XCTAssertNil(state.resolvedACOMModel)
    }

    /// If a selection ever does reference an imported model that is no
    /// longer in this run's list (the defensive branch in
    /// `acomModelSelectionIssue`), the UI must explicitly say so rather than
    /// resolving to nil with no explanation or silently falling back to a
    /// different phase model.
    func testSelectionReferencingAMissingImportedModelExplicitlyReportsRatherThanFallingBackSilently() {
        let state = AppState()
        state.acomModelSelection = .imported("imported_does_not_exist")

        XCTAssertNil(state.resolvedACOMModel)
        let issue = state.acomModelSelectionIssue
        XCTAssertNotNil(issue)
        XCTAssertTrue(issue?.contains("no longer available") == true, "\(issue ?? "nil")")
    }
}
