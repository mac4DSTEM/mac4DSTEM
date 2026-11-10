// The thickness row (design rooms-2026-10-21 §3): a typed value with its source, accepted from macTEM's EELS method JSON as the
// source, carried by the objects run's lineage node (the sidecar's record) and named in the objects CSV.

import XCTest
@testable import ShellControls
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
@testable import mac4DSTEM

@MainActor
final class ThicknessEntryTests: XCTestCase {
    func testUsableNeedsPositiveThicknessAndASource() {
        XCTAssertTrue(ThicknessEntry(nanometres: 120, sigmaNanometres: 15, source: "CBED").isUsable)
        XCTAssertFalse(ThicknessEntry(nanometres: 0, sigmaNanometres: 15, source: "CBED").isUsable)
        XCTAssertFalse(ThicknessEntry(nanometres: 120, sigmaNanometres: -1, source: "CBED").isUsable)
        XCTAssertFalse(ThicknessEntry(nanometres: 120, sigmaNanometres: 15, source: "  ").isUsable)
    }

    func testTheEELSMethodJSONNamesTheSourceAndNothingElse() throws {
        let json = #"{"file":"lamella.dm4","origin":"x","method":"log-ratio, estimated threshold","validation":"none","mean_free_path_nm":120.5,"width":8,"height":6}"#
        let read = try ThicknessEntry.source(fromEELSMethodJSON: json)
        XCTAssertTrue(read.text.contains("lamella.dm4") && read.text.contains("log-ratio") && read.text.contains("120.5"), read.text)
        XCTAssertFalse(read.text.contains("validation"), "the file's validation key is not repeated: \(read.text)")
        guard case .eelsMethodJSON(let file, _, let lambda) = read.origin else { return XCTFail() }
        XCTAssertEqual(file, "lamella.dm4"); XCTAssertEqual(lambda, 120.5)
        XCTAssertThrowsError(try ThicknessEntry.source(fromEELSMethodJSON: "not json"))
        XCTAssertThrowsError(try ThicknessEntry.source(fromEELSMethodJSON: #"{"a":1}"#))
    }

    func testParametersRoundTrip() throws {
        let e = ThicknessEntry(nanometres: 123.5, sigmaNanometres: 12, source: "EELS t/λ, λ = 120 nm", origin: .typed)
        let back = try XCTUnwrap(ThicknessEntry(parameters: e.parameters))
        XCTAssertEqual(back, e)
        XCTAssertNil(ThicknessEntry(parameters: ["thickness_nm": "-3", "thickness_sigma_nm": "1", "thickness_source": "x"]))
    }

    /// The row persists: a thickness set on a window with a standing objects run is on that run's lineage node, a window that adopts
    /// that lineage reads it back, and the objects CSV names it. Mutation: drop the thickness keys from `objectsRunParameters` - red.
    func testThicknessIsOnTheObjectsRunsNodeAndComesBack() throws {
        let state = AppState()
        state.recordLineageRun(kind: "precipitate_objects", parameters: ["connectivity": "8", "minimum_object_area_px": "1"])
        // recordLineageRun is a no-op while a dataset is loading; a fresh state is not loading.
        XCTAssertNotNil(state.replay.lineage.activeNodes().first { $0.kind == "precipitate_objects" })
        state.setPrecipitateThickness(ThicknessEntry(nanometres: 120, sigmaNanometres: 15, source: "CBED fringes"))
        let node = try XCTUnwrap(state.replay.lineage.activeNodes().last { $0.kind == "precipitate_objects" })
        XCTAssertEqual(node.parameters["thickness_nm"], "120.0")
        XCTAssertEqual(node.parameters["thickness_source"], "CBED fringes")
        state.assignPrecipitateThickness(nil)
        state.restorePrecipitateThicknessFromLineage()
        XCTAssertEqual(state.precipitateThickness?.nanometres, 120)
        XCTAssertEqual(state.precipitateThickness?.source, "CBED fringes")
        let pairs = try XCTUnwrap(state.precipitateThickness).provenancePairs
        XCTAssertTrue(pairs.contains { $0.0 == "thickness_source" && $0.1 == "CBED fringes" })
        // Clearing is a change too.
        state.setPrecipitateThickness(nil)
        XCTAssertNil(state.precipitateThickness)
    }

    /// #129 (drive on Thronsen dataset A, 2026-11-05): 50 typed, then the field emptied and Return: the 50 nm stayed, N_V stayed and
    /// the CSV kept its thickness and N_V lines. The commit here goes through the field's own rule (`NumberEntryField.resolve`) with
    /// the thickness rows' setting, as the field does. Mutation: `emptiedFieldClears` false (the old field) - red.
    func testEmptyingTheThicknessFieldClearsTheEntry() {
        typealias Field = NumberEntryField<Double, FloatingPointFormatStyle<Double>>
        let entry = DecimalEntryFormat(FloatingPointFormatStyle<Double>.number)
        let state = AppState()
        state.recordLineageRun(kind: "precipitate_objects", parameters: ["connectivity": "8", "minimum_object_area_px": "1"])
        func commit(_ typed: String) {
            guard case .set(let value) = Field.resolve(typed: typed, current: state.precipitateThickness?.nanometres,
                                                       emptyClears: PrecipitateThicknessRows.emptiedFieldClears, entry: entry, edited: true)
            else { return }
            state.setPrecipitateThickness(value.map { ThicknessEntry(nanometres: $0, sigmaNanometres: 0, source: "typed value") })
        }
        commit("50")
        XCTAssertEqual(state.precipitateThickness?.nanometres, 50)
        commit("")
        XCTAssertNil(state.precipitateThickness, "an emptied thickness field removes the thickness")
        let node = state.replay.lineage.activeNodes().last { $0.kind == "precipitate_objects" }
        XCTAssertNil(node?.parameters["thickness_nm"], "the objects run on record carries no thickness, so the CSV drops its thickness and N_V lines")
    }
}
