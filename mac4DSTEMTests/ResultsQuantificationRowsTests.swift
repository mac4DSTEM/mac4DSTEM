//
//  ResultsQuantificationRowsTests.swift
//  Owner card P4 option b (ADR 061 §3): the Quantify steps of a 4D window are rows in the Results room, read from the record;
//  a spectrum-only window shows none. Each test names the mutation it catches; each was broken once (the lane report).
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
import DiffractoOrientation
@testable import mac4DSTEM

@MainActor
final class ResultsQuantificationRowsTests: XCTestCase {
    private var keep: [AppState] = []
    private let path = "/tmp/p4.h5"

    private func phaseMap(_ w: Int, _ h: Int, _ chars: String) -> PhaseMap {
        var m = PhaseMap(width: w, height: h, matrixEntryIndex: -1, phaseNames: ["A", "B"], matrixPhaseIndex: 0)
        for (i, ch) in chars.enumerated() {
            m.results[i].verdict = .indexed; m.results[i].phaseIndex = ch == "A" ? 0 : 1
        }
        return m
    }
    private static func runRecord() -> PhaseMappingProduct.RunRecord {
        PhaseMappingProduct.RunRecord(
            phaseSignature: "p4", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: false, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0)))
    }

    /// A window on demo-edx-tiny (6 x 4), with a 4D cube (or none) and a phase map (A = columns 0-2), ready to Quantify.
    private func window(withCube: Bool) async throws -> (AppState, SpectroscopyRoomController) {
        let loaded = try SpectroscopyQuantifyTests.image()
        let (nx, ny) = (loaded.nx, loaded.ny)
        let state = AppState(); keep.append(state)
        if withCube {
            state.descriptor = DatasetDescriptor(filePath: path, datasetPath: "/d", shape: [ny, nx, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        }
        state.openSpectrumImage(loaded)
        let c = state.spectroscopyRoom; c.autoIDOnOpen?.cancel()
        if withCube {
            state.spectroscopy.registration = PoolCatalogue.identityRegistration(width: nx, height: ny)
            state.spectroscopy.registeredCubePath = path
            state.phaseMapping.publish(phaseMap(nx, ny, String(repeating: "AAABBB", count: ny)), ranWith: Self.runRecord())
            await state.spectroscopy.poolTask?.value
        }
        for z in [13, 12, 14, 29] { c.model.elements.set(z, .quantify) }
        c.elementsChanged()
        if loaded.metadata.beamEnergyKeV == nil { c.model.quantify.beamEnergy = 200; c.quantifySettingsChanged() }
        return (state, c)
    }

    private func quantify(_ state: AppState, _ c: SpectroscopyRoomController, region id: Int) async {
        c.selectRegion(id: id)
        await c.lastRefresh?.value
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
        await c.checkTask?.value
    }

    /// The abundance cells of the room's own table, element by element, as `ResultsSection` prints them.
    private func tableLine(_ c: SpectroscopyRoomController, _ unit: AbundanceUnit) -> String {
        c.model.results.filter { $0.hasAbundance && $0.failure == nil }
            .map { "\(PeriodicLayout.symbol($0.z)) \(ResultFormat.fitCells($0, unit: unit, hasFit: true, locale: ResultFormat.recordLocale).abundance)" }
            .joined(separator: " \u{00B7} ")
    }

    /// A phase pool quantified in a 4D window is one row: named, with the room table's at% and wt% strings, the badge, the method.
    /// Mutations: `quantificationRows` returning [] - red; the row's result read from a recompute with `%.2f` - red (strings);
    /// `unvalidated` always false - red.
    func testAQuantifiedPhasePoolIsOneRowWithTheRoomsTableStrings() async throws {
        let (state, c) = try await window(withCube: true)
        XCTAssertTrue(state.quantificationRows.isEmpty, "nothing quantified yet")
        await quantify(state, c, region: 1000)
        let line = tableLine(c, .atomic)
        XCTAssertFalse(line.isEmpty, "the fixture must produce an at% to compare")
        let rows = state.quantificationRows
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.title, "A \u{00B7} phase pool")
        // The unit label is the room's: at% with its "· no absorption" honesty label when the correction was not applied.
        XCTAssertEqual(row.result, line + " at%" + (c.model.abundanceWithoutAbsorption ? " " + ResultFormat.noAbsorptionLabel : ""))
        XCTAssertEqual(row.parameters.first { $0.key == "result_wt%" }?.value, tableLine(c, .weight))
        XCTAssertTrue(row.unvalidated)
        let m = state.spectroscopy.method
        XCTAssertEqual(row.method, [m.background == .empiricalWithAlEdge ? "Empirical" : "Polynomial", m.kFactorSource == .typed ? "Typed" : "Computed",
                                    m.estimator == .leastSquares ? "Least squares" : "Poisson ML"].joined(separator: " \u{00B7} "))
        XCTAssertNil(row.parameters.first { $0.key == "method_json" }, "the method JSON is not a readable key")
        XCTAssertEqual(row.parameters.first { $0.key == "region_kind" }?.value, "phase")
    }

    /// The whole map is a row named "Whole map" (kind wholeMap), and a rerun of unchanged inputs collapses into it (the lineage's
    /// own rule, ADR 047 R3): the newest region and numbers stand.
    /// Mutation: `kind == "wholeMap"` label returning the name with a suffix - red.
    func testWholeMapRowAndTheLineagesCollapseRule() async throws {
        let (state, c) = try await window(withCube: true)
        await quantify(state, c, region: 0)
        XCTAssertEqual(state.quantificationRows.map(\.title), ["Whole map"])
        await quantify(state, c, region: 1000)
        XCTAssertEqual(state.quantificationRows.map(\.title), ["A \u{00B7} phase pool"], "same inputs: the rerun is the same step")
    }

    /// An EMD opened alone shows no row, even after a Quantify recorded into its replay.
    /// Mutation: dropping the `hasDataset` gate - red.
    func testASpectrumOnlyWindowHasNoRows() async throws {
        let (state, c) = try await window(withCube: false)
        await quantify(state, c, region: 0)
        XCTAssertFalse(state.replay.lineage.nodes.filter { $0.kind == "quantification" }.isEmpty, "the step was recorded")
        XCTAssertTrue(state.isSpectrumOnly)
        XCTAssertTrue(state.quantificationRows.isEmpty)
    }

    /// The region kinds are named, newest step first, and the badge follows the pool or the fit's validation.
    /// Mutations: `reversed()` removed - red (order); "drawn" label changed - red; "group" counted as unvalidated - red.
    func testRegionKindsAreNamedNewestFirstWithTheirBadges() throws {
        let replay = SessionReplay()
        let s = SpectroscopySession()
        s.recordQuantification(in: replay, regionKind: "drawn", regionName: "Region 1", extra: ["result_at": "Al 90.0 \u{00B1} 1.0", "result_unit": "at%", "validation": "none"])
        replay.markProduct(step: replay.lineage.nodes[0].id, as: "q1")   // a saved product: the next run is a new step
        s.recordQuantification(in: replay, regionKind: "group", regionName: "Group 2", extra: ["result_at": "", "result_unit": "at%"])
        replay.markProduct(step: replay.lineage.nodes[1].id, as: "q2")
        s.recordQuantification(in: replay, regionKind: "notIndexed", regionName: "Not indexed")
        let rows = QuantificationRows.rows(in: replay.lineage)
        XCTAssertEqual(rows.map(\.title), ["Not indexed pool", "Group 2 \u{00B7} group pool", "Region 1 \u{00B7} drawn region"])
        XCTAssertEqual(rows.map(\.unvalidated), [true, false, true])
        XCTAssertEqual(rows.map(\.result), ["no result recorded in this step", "no at% computed", "Al 90.0 \u{00B1} 1.0 at%"])
    }
}
