//
//  EDSFourDLinkTests.swift
//  The EDS room (macTEM 1.0's, 2026-10-23) with mac4DSTEM's 4D links: the scan's pools as regions, the Quantify verb's replay step
//  with the old room's keys, the precipitate joins reading the session's quantification maps. Each test names the mutation it catches.
//

import DSTEMCore
@testable import DSTEMSession
import SpectroCore
import SpectroEDX
import XCTest
@testable import mac4DSTEM
import ShellEDXModel

@MainActor
final class EDSFourDLinkTests: XCTestCase {
    private var keep: [AppState] = []

    private func waitFor(_ what: String, timeout: TimeInterval = 60, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func pool(_ name: String, key: String, nx: Int = 32, ny: Int = 32, kind: String = "phase") -> EDXPoolRegion {
        EDXPoolRegion(kind: kind, name: name, mask: (0..<(nx * ny)).map { $0 % nx < nx / 2 }, key: key, validation: "none")
    }

    /// A pool is its own mask (half the scan here), its name and kind, and a cache key that carries its content key.
    /// Mutations: `mask` falling through to `shape` (nil, every pixel) - red; the key without `p.key` - red.
    func testAPoolIsItsOwnMaskNameAndKey() {
        let p = pool("beta''", key: "1000@3")
        let r = EDXRegion.pool(p)
        XCTAssertEqual(r.pixelCount(nx: 32, ny: 32), 512)
        XCTAssertEqual(r.name, "beta''")
        XCTAssertEqual(r.shapeName, "phase")
        XCTAssertEqual(r.cacheKey, "pool:1000@3")
        XCTAssertNotEqual(EDXRegion.pool(pool("beta''", key: "1000@4")).cacheKey, r.cacheKey, "a rebuilt pool is a new cache entry")
    }

    /// The window's catalogue becomes the Source row's pools with the replay kind and a generation-bearing key.
    /// Mutation: the key without the generation - a rebuilt phase map keeps a stale spectrum - red.
    func testTheCatalogueBecomesPoolsKeyedByIdAndGeneration() {
        let catalogue = PoolCatalogue(pools: [SpectrumPool(id: 1000, kind: .phase, name: "A", sourceGeneration: 7, pixelCount: 2,
                                                           mask: [true, true, false], validation: "none")])
        let pools = AppState.edsPools(catalogue)
        XCTAssertEqual(pools.map(\.key), ["1000@7"])
        XCTAssertEqual(pools.first?.kind, "phase")
        XCTAssertEqual(pools.first?.validation, "none")
    }

    /// A selected pool that changed or vanished falls back to the whole map (never a fit on a stale mask, H8); an unchanged one stays.
    /// Mutation: `applyPools` not checking the selected region - the session keeps the old pool - red.
    func testAChangedPoolFallsBackToTheWholeMap() async {
        let session = EDXSession(host: .mac4DSTEM)
        await session.bind(DemoSpectrumImageSource.make(beamEnergyKeV: 200)).value
        let a = pool("A", key: "1000@1")
        session.applyPools([a])
        session.selectPool(a)
        XCTAssertEqual(session.region, .pool(a))
        session.applyPools([a])
        XCTAssertEqual(session.region, .pool(a), "an unchanged pool stays selected")
        session.applyPools([pool("A", key: "1000@2")])
        XCTAssertEqual(session.region, .wholeMap)
        session.selectPool(a)
        XCTAssertEqual(session.region, .wholeMap, "a pool the catalogue no longer holds cannot be selected")
    }

    /// The step's region keys are the old room's kinds, so Results rows label them as before ("A · phase pool").
    /// Mutation: the shape name ("rectangle", "whole") recorded instead - red.
    func testTheReplayRegionKeysAreTheOldRoomsKinds() {
        XCTAssertEqual(AppState.replayRegion(.wholeMap, pinName: nil).kind, "wholeMap")
        XCTAssertEqual(AppState.replayRegion(.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2)), pinName: "Region 1").kind, "drawn")
        XCTAssertEqual(AppState.replayRegion(.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2)), pinName: "Region 1").name, "Region 1")
        let a = AppState.replayRegion(.pool(pool("A", key: "1000@1")), pinName: nil)
        XCTAssertEqual(a.kind, "phase"); XCTAssertEqual(a.name, "A")
        XCTAssertEqual(QuantificationRows.regionLabel(kind: a.kind, name: a.name), "A \u{00B7} phase pool")
    }

    /// The verb on the demo scan: a fit lands and the lineage gets one "quantification" step with the old room's keys (the method
    /// JSON, the region, the result line), so Results rows read it as before.
    /// Mutations: `quantifyEDS` not recording - no step - red; `region_kind` from the shape name ("whole") - red; `result_at` not written - red.
    func testQuantifyRecordsTheReplayStepWithTheOldKeys() async throws {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(DemoSpectrumImageSource.make(beamEnergyKeV: 200))
        try await waitFor("the open's Auto ID") { !state.edx.isBusy && state.edx.autoID != .idle }
        for s in ["Mg", "Al", "Si"] where !state.edx.picks.contains(where: { $0.symbol == s }) { state.edx.toggle(s) }
        await state.quantifyEDS()
        XCTAssertNotNil(state.edx.fit, state.edx.fitFailure ?? "no fit")
        let step = try XCTUnwrap(state.replay.lineage.nodes.last { $0.kind == QuantificationStep.kind })
        XCTAssertEqual(step.parameters["region_kind"], "wholeMap")
        XCTAssertEqual(step.parameters["region_name"], "Whole map")
        XCTAssertNotNil(step.parameters["method_json"])
        // The result line is the fit's at% as it stands after the unlisted-line check (empty when the check withholds it, as the old room wrote).
        let expected = AppState.edsResultParameters(try XCTUnwrap(state.edx.fit))["result_at"]
        XCTAssertEqual(step.parameters["result_at"], expected)
        XCTAssertEqual(step.parameters["validation"], "none")
        var recorded = step.parameters
        recorded["method"] = recorded["method_json"]
        XCTAssertNotNil(QuantificationStep(parameters: recorded), "the recorded method JSON reads back")
    }
}
