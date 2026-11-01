//
//  ResultsQuantificationRowsTests.swift
//  Owner card P4 option b (ADR 061 §3): the Quantify steps of a 4D window are rows in the Results room, read from the record;
//  a spectrum-only window shows none. Each test names the mutation it catches; each was broken once (the lane report).
//

import AppKit
import SwiftUI
import XCTest
@testable import DSTEMCore
@testable import DSTEMSession
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

    /// A window on demo-edx-tiny (6 x 4), with a 4D cube (or none) and a phase map (A = columns 0-2), ready to Quantify in the EDS room.
    private func window(withCube: Bool) async throws -> AppState {
        let loaded = try SpectroQuantFixtures.image()
        let (nx, ny) = (loaded.nx, loaded.ny)
        let state = AppState(); keep.append(state)
        if withCube {
            state.descriptor = DatasetDescriptor(filePath: path, datasetPath: "/d", shape: [ny, nx, 8, 8], dtypeDescription: "float32", chunkShape: nil)
        }
        state.openSpectrumImage(loaded)
        try await waitFor("the open's Auto ID") { !state.edx.isBusy && state.edx.autoID != .idle }
        if withCube {
            state.spectroscopy.registration = PoolCatalogue.identityRegistration(width: nx, height: ny)
            state.spectroscopy.registeredCubePath = path
            state.phaseMapping.publish(phaseMap(nx, ny, String(repeating: "AAABBB", count: ny)), ranWith: Self.runRecord())
            await state.spectroscopy.poolTask?.value
        }
        for s in ["Al", "Mg", "Si", "Cu"] where !state.edx.picks.contains(where: { $0.symbol == s }) { state.edx.toggle(s) }
        for s in ["Al", "Mg", "Si", "Cu"] { state.edx.setRole(.quantify, of: s) }
        if loaded.metadata.beamEnergyKeV == nil { state.edx.changeMethod { $0.beamEnergyKeV = 200 } }
        return state
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 60, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The Quantify verb on a pool ("A") or the whole map (nil), as the toolbar runs it.
    private func quantify(_ state: AppState, pool name: String?) async {
        if let name, let pool = state.edx.pools.first(where: { $0.name == name }) { state.edx.selectPool(pool) } else { state.edx.selectWholeMap() }
        state.navigation.workspaceArea = .spectroscopy
        await state.runPrimaryWorkspaceTask()
    }

    /// A phase pool quantified in a 4D window is one row: named, with the fit's at% and wt% strings, the badge, the method.
    /// Mutations: `quantificationRows` returning [] - red; the pool's kind not recorded - red; `unvalidated` always false - red.
    func testAQuantifiedPhasePoolIsOneRowWithTheFitsStrings() async throws {
        let state = try await window(withCube: true)
        XCTAssertTrue(state.quantificationRows.isEmpty, "nothing quantified yet")
        XCTAssertTrue(state.edx.pools.contains { $0.name == "A" }, "the phase map's pools reach the EDS room")
        await quantify(state, pool: "A")
        let fit = try XCTUnwrap(state.edx.fit)
        let expected = AppState.edsResultParameters(fit)
        let rows = state.quantificationRows
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.title, "A \u{00B7} phase pool")
        XCTAssertEqual(row.result, (expected["result_at"] ?? "").isEmpty ? "no at% computed" : (expected["result_at"]! + " at%"))
        XCTAssertTrue(row.unvalidated)
        XCTAssertNil(row.parameters.first { $0.key == "method_json" }, "the method JSON is not a readable key")
        XCTAssertEqual(row.parameters.first { $0.key == "region_kind" }?.value, "phase")
        XCTAssertNotNil(state.replay.lineage.nodes.last?.parameters["registration"], "a pool's step records the registration it went through")
    }

    /// The whole map is a row named "Whole map" (kind wholeMap); a pool is a new step beside it.
    /// Mutation: `kind == "wholeMap"` label returning the name with a suffix - red.
    func testWholeMapRowThenAPoolRow() async throws {
        let state = try await window(withCube: true)
        await quantify(state, pool: nil)
        XCTAssertEqual(state.quantificationRows.first?.title, "Whole map")
        await quantify(state, pool: "A")
        XCTAssertEqual(state.quantificationRows.first?.title, "A \u{00B7} phase pool")
    }

    /// An EMD opened alone shows no row, even after a Quantify recorded into its replay.
    /// Mutation: dropping the `hasDataset` gate - red.
    func testASpectrumOnlyWindowHasNoRows() async throws {
        let state = try await window(withCube: false)
        await quantify(state, pool: nil)
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

    /// The Results list draws rows of `validation: "none"` steps with no badge: renders offscreen. With
    /// MAC4DSTEM_SHOT_PATH set (TEST_RUNNER_MAC4DSTEM_SHOT_PATH through xcodebuild) it writes the PNG there for review.
    func testQuantificationRowsRenderWithoutABadge() throws {
        let replay = SessionReplay()
        let s = SpectroscopySession()
        s.recordQuantification(in: replay, regionKind: "phase", regionName: "A",
                               extra: ["result_at": "Al 97.6 \u{00B1} 0.5 \u{00B7} Si 1.5 \u{00B1} 0.3", "result_unit": "at%", "validation": "none"])
        replay.markProduct(step: replay.lineage.nodes[0].id, as: "q1")
        s.recordQuantification(in: replay, regionKind: "drawn", regionName: "Region 1",
                               extra: ["result_at": "Al 90.0 \u{00B1} 1.0", "result_unit": "at%", "validation": "none"])
        let rows = QuantificationRows.rows(in: replay.lineage)
        XCTAssertEqual(rows.count, 2)
        let view = VStack(alignment: .leading, spacing: 8) {
            Text("Quantifications").font(.headline)
            ForEach(rows) { QuantificationRowView(row: $0) }
        }
        .padding(16).frame(width: 460, alignment: .leading).background(Color.white)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "the Results rows render offscreen")
        XCTAssertGreaterThan(image.width, 0)
        if let path = ProcessInfo.processInfo.environment["MAC4DSTEM_SHOT_PATH"], !path.isEmpty {
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
