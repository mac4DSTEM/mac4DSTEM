// Pool by Class (design rooms-2026-10-21 §3): each phase pool fitted once with the room's method; the planted two-phase
// composition comes back within the pooled fit's tolerance, the CSV carries class, pixels, element, wt%, at%, sigma, hash.

import XCTest
import SpectroCore
@testable import SpectroEDX
@testable import mac4DSTEM

final class CompositionByClassTests: XCTestCase {
    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)

    /// Noise-free spectrum: a Kramers-type continuum plus the named K-alpha areas (the kit's own planted construction).
    private static func counts(_ areas: [String: Double]) -> [UInt64] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 0.4 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3)) : 0
        }
        let elements = Array(Set(areas.keys.map { String($0.split(separator: "_")[0]) }))
        let model = EDSLineModel.build(elements: elements, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: true)
        for g in model.groups {
            guard let area = areas[g.id] else { continue }
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += area * col[i] }
        }
        return mu.map { UInt64($0.rounded()) }
    }

    private static func method() -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = ["Al", "Mg", "Si"].map { .init(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200; m.lockEnergyAxis = true; m.absorptionCorrection = false
        m.kFactorSource = .typed; m.kSource = "planted"; m.kDate = "2026-10-21"; m.kReference = "Al"
        m.typedK = [.init(element: "Al", k: 1), .init(element: "Mg", k: 1.2), .init(element: "Si", k: 0.9)]
        return m
    }

    private static func metadata() -> SpectrumImageMetadata {
        SpectrumImageMetadata(fileName: "planted.emd", filePath: "", scanWidth: 8, scanHeight: 6, channelCount: axis.size,
                              energyOffsetEV: 0, energyDispersionEV: 10)
    }

    /// Planted truth by Cliff-Lorimer with the typed k: C_i proportional to k_i * area_i.
    private func expectedWeight(_ areas: [String: Double]) -> [String: Double] {
        let k = ["Al": 1.0, "Mg": 1.2, "Si": 0.9]
        let w = areas.reduce(into: [String: Double]()) { $0[String($1.key.prefix(2)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))] = k[String($1.key.prefix(2)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))]! * $1.value }
        let total = w.values.reduce(0, +)
        return w.mapValues { 100 * $0 / total }
    }

    func testPlantedTwoPhasesComeBackPerClass() throws {
        let matrix = ["Al_Ka": 30000.0, "Mg_Ka": 500, "Si_Ka": 800]
        let precipitate = ["Al_Ka": 12000.0, "Mg_Ka": 9000, "Si_Ka": 11000]
        let pools = [CompositionByClass.Pool(name: "Al", pixels: 40, spectrum: Self.counts(matrix)),
                     CompositionByClass.Pool(name: "β″", pixels: 8, spectrum: Self.counts(precipitate))]
        let method = Self.method()
        let results = try CompositionByClass.run(pools: pools, axis: Self.axis, metadata: Self.metadata(), method: method,
                                                 tables: QuantificationTables.bundled())
        XCTAssertEqual(results.map(\.className), ["Al", "β″"])
        XCTAssertEqual(results.map(\.pixels), [40, 8])
        for (r, areas) in zip(results, [matrix, precipitate]) {
            XCTAssertNil(r.failure)
            let want = expectedWeight(areas)
            for row in r.rows {
                let w = try XCTUnwrap(row.weightPercent)
                XCTAssertEqual(w, want[row.element] ?? .nan, accuracy: 1.5, "\(r.className) \(row.element) wt%")
                XCTAssertNotNil(row.weightSigma)
            }
        }
        // The classes differ the way the planting says.
        let mgMatrix = try XCTUnwrap(results[0].rows.first { $0.element == "Mg" }?.weightPercent)
        let mgPrecipitate = try XCTUnwrap(results[1].rows.first { $0.element == "Mg" }?.weightPercent)
        XCTAssertGreaterThan(mgPrecipitate, 10 * mgMatrix)

        let csv = CompositionByClass.csv(results, imageName: "planted.emd", method: method)
        XCTAssertTrue(csv.contains("class,pixels_pooled,counts,element,wt_percent,sigma_wt_percent,at_percent,sigma_at_percent,method_hash,note"))
        XCTAssertTrue(csv.contains("# method: Cliff-Lorimer, k-factors ") && csv.contains(method.hash), csv)
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("validat"), "no validation state in the export")
        XCTAssertEqual(csv.split(separator: "\n").filter { !$0.hasPrefix("#") }.count, 1 + 6, "header and three elements per class")
    }

    func testAPoolTheKitCannotFitIsARowWithItsSentence() throws {
        let empty = CompositionByClass.Pool(name: "none", pixels: 0, spectrum: [UInt64](repeating: 0, count: Self.axis.size))
        let results = try CompositionByClass.run(pools: [empty], axis: Self.axis, metadata: Self.metadata(), method: Self.method(),
                                                 tables: QuantificationTables.bundled())
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse((results[0].failure ?? "").isEmpty, "the class stays listed with the kit's sentence")
    }

    func testCancellingThrows() {
        let pools = [CompositionByClass.Pool(name: "a", pixels: 1, spectrum: Self.counts(["Al_Ka": 1000]))]
        XCTAssertThrowsError(try CompositionByClass.run(pools: pools, axis: Self.axis, metadata: Self.metadata(), method: Self.method(),
                                                         tables: nil, cancelled: { true }))
    }
}
