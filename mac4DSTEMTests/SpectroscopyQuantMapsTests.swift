// ROADMAP task 4: the wt% / at% maps come from `EDXQuantification.quantifyMaps`; the app holds the method mapping, the tiles
// and the words. No numerics here: the map is pinned against the kit's single-spectrum call, pixel by pixel.

import XCTest
import SpectroCore
import SpectroEDX
@testable import mac4DSTEM

final class SpectroscopyQuantMapsTests: XCTestCase {
    private func typedMethod(thickness: Double? = nil) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = [.init(symbol: "Mg", role: .quantify, isManual: true), .init(symbol: "Si", role: .quantify, isManual: true),
                      .init(symbol: "Al", role: .quantify, isManual: true), .init(symbol: "Cu", role: .fitOnly, isManual: true)]
        m.kFactorSource = .typed
        m.kSource = "planted"; m.kDate = "2026-10-21"; m.kReference = "Al"
        m.typedK = [.init(element: "Mg", k: 1.1), .init(element: "Si", k: 1.3), .init(element: "Al", k: 1.0)]
        if let t = thickness { m.thickness = .init(nanometres: t, sigmaNanometres: 5) }
        return m
    }

    func testComputedKIsRefusedInTheAppsWords() throws {
        var m = typedMethod(); m.kFactorSource = .computed
        guard case .failure(let why) = QuantMapsSetup.setup(method: m, elements: ["Mg", "Si", "Al"]) else { return XCTFail("computed k must be refused") }
        XCTAssertTrue(why.text.contains("typed k"))
    }

    func testMissingTypedKNamesTheElement() {
        var m = typedMethod(); m.typedK.removeAll { $0.element == "Si" }
        guard case .failure(let why) = QuantMapsSetup.setup(method: m, elements: ["Mg", "Si", "Al"]) else { return XCTFail() }
        XCTAssertEqual(why.text, "No typed k for Si: type it in Quantification.")
    }

    func testSetupCarriesTypedKInTileOrderAndThickness() throws {
        guard case .success(let s) = QuantMapsSetup.setup(method: typedMethod(thickness: 80), elements: ["Al", "Mg"]) else { return XCTFail() }
        XCTAssertEqual(s.elements, ["Al", "Mg"])
        XCTAssertEqual(s.method, .cliffLorimer(kFactors: [1.0, 1.1], thicknessNm: 80))
        XCTAssertNil(s.absorption)
    }

    /// The pin: a 3 x 2 planted net-count image through the pass equals the kit's call on each pixel's three intensities,
    /// for wt% and at%; the negative pixel fails with the kit's reason and is counted, drawn 0.
    func testMapEqualsThePerPixelKitCallAndCountsFailures() throws {
        let method = typedMethod(thickness: 80)
        guard case .success(let setup) = QuantMapsSetup.setup(method: method, elements: ["Mg", "Si", "Al"]) else { return XCTFail() }
        let mg: [Double] = [120, 80, 10, 60, 200, -5]
        let si: [Double] = [60, 90, 12, 30, 100, 40]
        let al: [Double] = [900, 700, 800, 650, 500, 600]
        let request = QuantMapsRequest(setup: setup, rows: 2, columns: 3, minimumCounts: 0, methodHash: method.hash)
        let maps = try QuantMapsPass.run(request, netMaps: [mg, si, al])
        XCTAssertEqual(maps.validation, "none")
        for p in 0..<6 where maps.failures[p] == nil {
            let one = try EDXQuantification.quantify(intensities: [mg[p], si[p], al[p]], setup: setup)
            for e in 0..<3 {
                XCTAssertEqual(maps.weightPercent[e][p], one.weightPercent[e], accuracy: 1e-12)
                XCTAssertEqual(maps.atomicPercent[e][p], one.atomicPercent[e], accuracy: 1e-12)
            }
            XCTAssertEqual(try XCTUnwrap(maps.massThickness)[p], try XCTUnwrap(one.massThickness), accuracy: 1e-18)
        }
        XCTAssertNotNil(maps.failures[5], "a negative net count is a failed pixel, not a number")
        let summary = QuantMapsPass.summary(maps)
        XCTAssertEqual(summary.failedPixels, 1)
        let tile = QuantMapsPass.tile(z: 12, percent: try XCTUnwrap(QuantMapsPass.percentMap(maps, index: 0, mode: .weight)),
                                      width: 3, height: 2, summary: summary, mode: .weight)
        XCTAssertEqual(tile.values[5], 0)
        XCTAssertEqual(tile.values.max(), 1)
        let footer = try XCTUnwrap(tile.footer)
        XCTAssertTrue(footer.contains("1 failed px") && footer.contains("no \u{03C3}") && footer.contains("validation: none"), footer)
    }

    func testMinimumCountsMasksThinPixels() throws {
        guard case .success(let setup) = QuantMapsSetup.setup(method: typedMethod(), elements: ["Mg", "Al"]) else { return XCTFail() }
        let request = QuantMapsRequest(setup: setup, rows: 1, columns: 3, minimumCounts: 50, methodHash: "h")
        let maps = try QuantMapsPass.run(request, netMaps: [[10, 100, 20], [20, 300, 5]])
        XCTAssertEqual(maps.weightPercent[0][0], 0)   // masked: composition 0
        XCTAssertGreaterThan(maps.weightPercent[0][1], 0)
    }

    func testCSVCarriesProvenanceAndTheRawPercent() throws {
        guard case .success(let setup) = QuantMapsSetup.setup(method: typedMethod(), elements: ["Mg", "Al"]) else { return XCTFail() }
        let request = QuantMapsRequest(setup: setup, rows: 1, columns: 3, minimumCounts: 50, methodHash: "abc")
        let nets: [[Double]] = [[10, 100, -3], [20, 300, 40]]
        let maps = try QuantMapsPass.run(request, netMaps: nets)
        XCTAssertEqual(QuantMapsPass.maskedCount(request, netMaps: nets), 2)
        let summary = QuantMapsPass.summary(maps, masked: 2)
        let tile = QuantMapsPass.tile(z: 12, percent: maps.weightPercent[0], width: 3, height: 1, summary: summary, mode: .weight)
        let csv = try MapsExport.csv(stem: "s", mode: .weight, tiles: [tile], provenance: QuantMapsPass.provenance(summary, methodHash: "abc", minimumCounts: 50)) { _ in "Mg" }
        XCTAssertTrue(csv.contains("# method hash: abc") && csv.contains("# validation: none") && csv.contains("left out (2 px)"), csv)
        XCTAssertTrue(csv.contains("0,0,0\n") || csv.contains("0,0,0"), csv)
    }

    func testCompositionChipsAppearOnlyAfterQuantify() {
        XCTAssertFalse(MapMode.weight.isOffered(quantified: false))
        XCTAssertTrue(MapMode.atomic.isOffered(quantified: true))
        XCTAssertTrue(MapMode.netCounts.isOffered(quantified: false))
    }
}
