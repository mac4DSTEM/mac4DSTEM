// ROADMAP task 4: the wt% / at% maps come from `EDXQuantification.quantifyMaps`; the app holds the method mapping, the tiles
// and the words. No numerics here: the map is pinned against the kit's single-spectrum call, pixel by pixel.

import XCTest
@testable import SpectroCore
@testable import SpectroEDX
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

    private static let meta = SpectrumImageMetadata(fileName: "t", filePath: "", scanWidth: 3, scanHeight: 2, channelCount: 1500,
                                                    energyOffsetEV: 0, energyDispersionEV: 10)
    /// The typed-k setup without a fit (the fit's own k is used when there is one, below).
    private func typedSetup(_ m: QuantificationMethod, _ elements: [String]) -> Result<QuantMapsPlan, QuantMapsRefusal> {
        QuantMapsSetup.plan(method: m, elements: elements, fit: nil, metadata: Self.meta)
    }

    func testComputedKWithoutAFitIsRefusedInTheAppsWords() throws {
        var m = typedMethod(); m.kFactorSource = .computed
        guard case .failure(let why) = typedSetup(m, ["Mg", "Si", "Al"]) else { return XCTFail("computed k needs the fit") }
        XCTAssertTrue(why.text.contains("Quantify first"))
    }

    // MARK: computed k and absorption from the pooled fit (SpectroKit 0.8.2)

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)
    private static func planted(_ areas: [String: Double]) -> [UInt64] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 0.4 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3)) : 0
        }
        let model = EDSLineModel.build(elements: ["Al", "Mg", "Si"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: true)
        for g in model.groups {
            guard let area = areas[g.id] else { continue }
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += area * col[i] }
        }
        return mu.map { UInt64($0.rounded()) }
    }
    private func veloxMeta() -> SpectrumImageMetadata {
        var m = Self.meta
        m.origin = .veloxEMD; m.alphaTiltDegrees = -16.87; m.betaTiltDegrees = 0
        m.detectors = [(45.0, 0.4), (135.0, 0.2), (225.0, 0.1), (315.0, 0.3)].enumerated().map { i, a in
            SpectrumDetectorSegment(name: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngle: a.1)
        }
        return m
    }
    private func fit(computed: Bool, thickness: Double?, meta: SpectrumImageMetadata) throws -> PooledQuantification {
        var m = QuantificationMethod()
        m.elements = ["Al", "Mg", "Si"].map { .init(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200; m.lockEnergyAxis = true
        m.absorptionCorrection = thickness != nil
        if let t = thickness { m.thickness = .init(nanometres: t, sigmaNanometres: 10) }
        if !computed {
            m.kFactorSource = .typed; m.kSource = "planted"; m.kDate = "2026-10-21"; m.kReference = "Al"
            m.typedK = [.init(element: "Al", k: 1), .init(element: "Mg", k: 1.2), .init(element: "Si", k: 0.9)]
        }
        let counts = Self.planted(["Al_Ka": 30000, "Mg_Ka": 6000, "Si_Ka": 12000])
        return try PooledQuantifier.run(PooledQuantificationInput(counts: counts, axis: Self.axis, method: m, metadata: meta,
                                                                  regionName: "p", pixelCount: 1), tables: QuantificationTables.bundled())
    }

    /// Computed k: the map uses the pooled fit's own k. A pixel carrying the fit's nets gets the fit's weight percent.
    func testComputedKMapsUseTheFitsOwnK() throws {
        let f = try fit(computed: true, thickness: nil, meta: Self.meta)
        var m = QuantificationMethod(); m.elements = ["Al", "Mg", "Si"].map { .init(symbol: $0, role: .quantify, isManual: false) }
        guard case .success(let plan) = QuantMapsSetup.plan(method: m, elements: f.rows.map(\.element), fit: f, metadata: Self.meta) else { return XCTFail() }
        XCTAssertNil(plan.setup.absorption)
        XCTAssertTrue(plan.absorptionNote.hasPrefix("no absorption correction"), plan.absorptionNote)
        let one = try EDXQuantification.quantify(intensities: f.rows.map { max($0.net, 0) }, setup: plan.setup)
        for (i, r) in f.rows.enumerated() { XCTAssertEqual(one.weightPercent[i], try XCTUnwrap(r.weightPercent), accuracy: 1e-6) }
    }

    /// With a thickness and a Velox geometry the maps carry the absorption correction, one take-off angle, named in the note.
    func testAbsorptionIsOnWhenThicknessAndGeometryAreThere() throws {
        let meta = veloxMeta()
        let f = try fit(computed: true, thickness: 200, meta: meta)
        var m = QuantificationMethod(); m.elements = ["Al", "Mg", "Si"].map { .init(symbol: $0, role: .quantify, isManual: false) }
        m.thickness = .init(nanometres: 200, sigmaNanometres: 10)
        guard case .success(let plan) = QuantMapsSetup.plan(method: m, elements: f.rows.map(\.element), fit: f, metadata: meta) else { return XCTFail() }
        let a = try XCTUnwrap(plan.setup.absorption)
        XCTAssertEqual(a.takeOffDegrees, try EDXQuantification.takeOffDegrees(metadata: meta), accuracy: 1e-12)
        XCTAssertEqual(a.lineEnergiesKeV, f.rows.map { $0.lineEnergyKeV! })
        XCTAssertTrue(plan.absorptionNote.contains("absorption corrected"), plan.absorptionNote)
        // Close to the pooled number (which averages four segments), not equal to it.
        let one = try EDXQuantification.quantify(intensities: f.rows.map { max($0.net, 0) }, setup: plan.setup)
        for (i, r) in f.rows.enumerated() { XCTAssertEqual(one.weightPercent[i], try XCTUnwrap(r.weightPercent), accuracy: 1.5) }
    }

    func testNoThicknessOrNoGeometryMeansNoAbsorptionAndTheNoteSaysWhy() throws {
        let f = try fit(computed: true, thickness: nil, meta: Self.meta)
        var m = QuantificationMethod(); m.elements = ["Al", "Mg", "Si"].map { .init(symbol: $0, role: .quantify, isManual: false) }
        guard case .success(let noThickness) = QuantMapsSetup.plan(method: m, elements: f.rows.map(\.element), fit: f, metadata: Self.meta) else { return XCTFail() }
        XCTAssertTrue(noThickness.absorptionNote.contains("no thickness"), noThickness.absorptionNote)
        m.thickness = .init(nanometres: 200, sigmaNanometres: 10)
        guard case .success(let noGeometry) = QuantMapsSetup.plan(method: m, elements: f.rows.map(\.element), fit: f, metadata: Self.meta) else { return XCTFail() }
        XCTAssertNil(noGeometry.setup.absorption)
        XCTAssertTrue(noGeometry.absorptionNote.hasPrefix("no absorption correction ("), noGeometry.absorptionNote)
    }

    func testMissingTypedKNamesTheElement() {
        var m = typedMethod(); m.typedK.removeAll { $0.element == "Si" }
        guard case .failure(let why) = typedSetup(m, ["Mg", "Si", "Al"]) else { return XCTFail() }
        XCTAssertEqual(why.text, "No typed k for Si: type it in Quantification.")
    }

    func testSetupCarriesTypedKInTileOrderAndThickness() throws {
        guard case .success(let plan) = typedSetup(typedMethod(thickness: 80), ["Al", "Mg"]) else { return XCTFail() }
        let s = plan.setup
        XCTAssertEqual(s.elements, ["Al", "Mg"])
        XCTAssertEqual(s.method, .cliffLorimer(kFactors: [1.0, 1.1], thicknessNm: 80))
        XCTAssertNil(s.absorption)
    }

    /// The pin: a 3 x 2 planted net-count image through the pass equals the kit's call on each pixel's three intensities,
    /// for wt% and at%; the negative pixel fails with the kit's reason and is counted, drawn 0.
    func testMapEqualsThePerPixelKitCallAndCountsFailures() throws {
        let method = typedMethod(thickness: 80)
        guard case .success(let plan) = typedSetup(method, ["Mg", "Si", "Al"]) else { return XCTFail() }
        let setup = plan.setup
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
        guard case .success(let plan) = typedSetup(typedMethod(), ["Mg", "Al"]) else { return XCTFail() }
        let setup = plan.setup
        let request = QuantMapsRequest(setup: setup, rows: 1, columns: 3, minimumCounts: 50, methodHash: "h")
        let maps = try QuantMapsPass.run(request, netMaps: [[10, 100, 20], [20, 300, 5]])
        XCTAssertEqual(maps.weightPercent[0][0], 0)   // masked: composition 0
        XCTAssertGreaterThan(maps.weightPercent[0][1], 0)
    }

    func testCSVCarriesProvenanceAndTheRawPercent() throws {
        guard case .success(let plan) = typedSetup(typedMethod(), ["Mg", "Al"]) else { return XCTFail() }
        let setup = plan.setup
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
