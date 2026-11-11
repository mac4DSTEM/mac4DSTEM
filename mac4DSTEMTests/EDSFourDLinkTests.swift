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
        EDXPoolRegion(kind: kind, name: name, mask: (0..<(nx * ny)).map { $0 % nx < nx / 2 }, key: key)
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
                                                           mask: [true, true, false])])
        let pools = AppState.edsPools(catalogue)
        XCTAssertEqual(pools.map(\.key), ["1000@7"])
        XCTAssertEqual(pools.first?.kind, "phase")
        XCTAssertNil(pools.first?.validation, "a pool carries no validation word")
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

    /// MacEMUI 0.5.2 (#108): a phase pool applied to the EDS session restarts Auto ID, which then also searches that phase's own
    /// spectrum (an element a small phase holds can fail the proposer's bar in the whole map's sum). The demo image's Mg-Si blob is the
    /// phase. Mutation: MacEMUI 0.5.1 (`applyPools` starts no search, `alsoSearched` does not exist) - does not compile, or stays empty.
    func testAPhasePoolAppliedToTheSessionRestartsAutoIDOnThatPhase() async {
        let session = EDXSession(host: .mac4DSTEM)
        await session.bind(DemoSpectrumImageSource.make(beamEnergyKeV: 200)).value
        if session.autoID == .idle { await session.runAutoID()?.value }
        await session.settled()
        XCTAssertEqual(session.autoID.outcome?.alsoSearched ?? [], [], "no pools yet: only the whole map was searched")
        let blob = EDXPoolRegion(kind: "phase", name: "blob",
                                 mask: (0..<(32 * 32)).map { let x = $0 % 32 - 16, y = $0 / 32 - 16; return x * x + y * y < 64 }, key: "1000@1")
        session.applyPools([blob])
        XCTAssertEqual(session.autoID, .running, "the new phase pool starts a search by itself")
        await session.settled()
        XCTAssertEqual(session.autoID.outcome?.alsoSearched, ["blob"])
        session.applyPools([blob])
        XCTAssertNotEqual(session.autoID, .running, "the same pool again: nothing new to search")
    }

    /// A 32 x 32 spectrum image, 512 channels of 10 eV at 200 kV, with a Mg K-alpha and an Al K-alpha line in every pixel (6 and 12
    /// expected counts, Poisson draws from a seeded LCG) and the kit's detector width: enough for the room to quantify two elements.
    private static func plantedMgAl() -> LoadedSpectrumImage {
        let side = 32, channels = 512, dispersion = 0.01
        func sigma(_ e: Double) -> Double { (2.5 * (e - 5.8987) * 1000 + 130 * 130).squareRoot() / 1000 / 2.3548200450309493 }
        func profile(_ e0: Double) -> [Double] {
            let raw = (0..<channels).map { exp(-pow(Double($0) * dispersion - e0, 2) / (2 * sigma(e0) * sigma(e0))) }
            let total = raw.reduce(0, +)
            return raw.map { $0 / total }
        }
        let mg = profile(1.2536), al = profile(1.4865)
        var state: UInt64 = 0x2545F4914F6CDD1D
        func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / Double(1 << 53)
        }
        func poisson(_ mean: Double) -> UInt32 {
            let limit = exp(-mean); var k: UInt32 = 0, p = uniform()
            while p > limit { k += 1; p *= uniform() }
            return k
        }
        var counts = [UInt32](repeating: 0, count: side * side * channels)
        for p in 0..<side * side { for c in 0..<channels {
            let mean = 6 * mg[c] + 12 * al[c]
            if mean > 1e-9 { counts[p * channels + c] = poisson(mean) }
        } }
        var meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: side, scanHeight: side, channelCount: channels,
                                         energyOffsetEV: 0, energyDispersionEV: dispersion * 1000, scanPixelSize: 1, scanPixelUnit: "nm")
        meta.beamEnergyKeV = 200
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: side, nx: side, channels: channels, counts: counts), metadata: meta,
                                   energyAxis: EnergyAxis(offset: 0, scale: dispersion, size: channels))
    }

    /// Seen on screen after #158 (2026-11-11): every object's composition cell read "No element is switched on". The EDS session puts
    /// the picked elements into its `method` only while a fit runs and empties the list afterwards, and the join fitted each object with
    /// that emptied method. It must take the method the room's fit ran with. Here the real session quantifies a planted image, and the
    /// join is run both ways on a square of a planted Mg + Al image as one object. Mutation: `objectCompositionInputs` returning the session's
    /// method - the object has no composition and this is red.
    func testObjectCompositionIsFittedWithTheMethodTheRoomsFitRanWith() async throws {
        let session = EDXSession(host: .mac4DSTEM)
        let source = Self.plantedMgAl()
        await session.bind(source).value
        if session.autoID == .idle { await session.runAutoID()?.value }
        await session.settled()
        for symbol in ["Mg", "Al"] where !session.picks.contains(where: { $0.symbol == symbol }) { session.toggle(symbol) }
        await session.settled()
        await session.quantify()?.value
        await session.pendingCheck?.value
        let fit = try XCTUnwrap(session.fit, session.fitFailure ?? "no fit")
        XCTAssertTrue(session.method.elements.isEmpty, "the trap: after the fit the session's method lists no element")
        XCTAssertFalse(fit.method.elements.isEmpty, "the fit's own method carries them")

        var labels = [Int32](repeating: 0, count: 32 * 32)
        for y in 1...6 { for x in 1...6 { labels[y * 32 + x] = 1 } }          // 36 px of matrix, clear of the blob
        let objects = PrecipitateSegmentation.classObjects(labels: labels, width: 32, height: 32,
                                                           roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [9]), pixelSize: nil, pixelUnit: nil)
        let id = try XCTUnwrap(objects.classes.first?.objects.first?.id)
        let registration = PoolCatalogue.identityRegistration(width: 32, height: 32)
        let tables = QuantificationTables.bundled()

        let inputs = try XCTUnwrap(AppState.objectCompositionInputs(fit: session.fit, source: session.source))
        XCTAssertEqual(inputs.method, fit.method)
        let joined = ObjectCompositionJoin.run(objects: objects, quantified: .init(source: inputs.source, method: inputs.method, tables: tables),
                                               registration: registration)
        let value = try XCTUnwrap(joined.perObject[id], joined.reasons[id] ?? joined.unavailable ?? "no value")
        XCTAssertEqual(value.pixels, 36)
        XCTAssertNotNil(value.elements.first { $0.symbol == "Mg" }?.atomicPercent, "\(value.elements)")
        XCTAssertNotNil(value.elements.first { $0.symbol == "Mg" }?.atomicSigma)

        let trapped = ObjectCompositionJoin.run(objects: objects, quantified: .init(source: source, method: session.method, tables: tables),
                                                registration: registration)
        XCTAssertNil(trapped.perObject[id], "with the session's emptied method the kit refuses the object")
        XCTAssertNil(AppState.objectCompositionInputs(fit: nil, source: session.source), "nothing quantified, nothing to fit with")
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
        XCTAssertNil(step.parameters["validation"])
        XCTAssertEqual(step.parameters["method_reference"], AppState.edsMethodLine(try XCTUnwrap(state.edx.fit).method))
        XCTAssertTrue(step.parameters["method_reference"]?.hasPrefix("Cliff-Lorimer, k-factors computed") == true)
        var recorded = step.parameters
        recorded["method"] = recorded["method_json"]
        XCTAssertNotNil(QuantificationStep(parameters: recorded), "the recorded method JSON reads back")
    }
}
