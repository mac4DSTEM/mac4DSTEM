// Suite task 42: composition and strain per precipitate object, on a planted 16 x 16 scan. Three objects that touch neither each other
// nor the edge: A (rows 1-6, cols 1-8, 48 px), B (rows 9-13, cols 9-13, 25 px), C (row 1, cols 11-13, 3 px).
// Composition (mac4DSTEM#113): each scan position carries a Poisson EDS spectrum with a Mg K-alpha and an Al K-alpha line and a few
// counts in each (A: 3 and 6 expected counts per pixel, B: 6 and 3, matrix: 0.3 and 8). An object's composition is ONE pooled fit of the
// summed spectrum of its pixels with the room's method (typed k: Mg 1.1 over Al), so A and B recover their planted at% within the fit's
// sigma, C has none ("under 4 EDS px"), and A's value is not B's. Before 5.2.1 the value was the mean of per-pixel at% maps, which at
// these counts is biased and has no sigma (on the Al-Mg-Si demo: Mg 18 at% against 23 planted; the summed spectrum gives 23).
// Strain: exx 0.01 over A, 0.02 / 0.04 over B's first four pixels, one of them outside the fit mask holding 9.9 that must not enter the
// mean; C has no fitted pixel ("no strain fit under the object"); eyy is the ROW direction (rr), exx the column (cc).

import XCTest
import DSTEMCore
import DSTEMSession
import ImagoCore
import SpectroCore
import SpectroEDX
@testable import mac4DSTEM
import ShellEDXModel

final class ObjectJoinsTests: XCTestCase {
    private static let side = 16
    private let rowsA = Array(1...6), colsA = Array(1...8)
    private let rowsB = Array(9...13), colsB = Array(9...13)
    private let rowsC = [1], colsC = [11, 12, 13]

    private func pixels(_ rows: [Int], _ cols: [Int]) -> [Int] { rows.flatMap { r in cols.map { r * Self.side + $0 } } }

    private func objects() -> PrecipitateSegmentation.ClassMapObjects {
        var labels = [Int32](repeating: 0, count: Self.side * Self.side)
        for p in pixels(rowsA, colsA) + pixels(rowsB, colsB) + pixels(rowsC, colsC) { labels[p] = 1 }
        return PrecipitateSegmentation.classObjects(
            labels: labels, width: Self.side, height: Self.side, roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [9]),
            pixelSize: nil, pixelUnit: nil)
    }

    private func ids() -> (a: Int, b: Int, c: Int) {
        let all = objects().classes.flatMap(\.objects)
        func id(_ p: Int) -> Int { all.first { $0.pixelIndices.contains(p) }!.id }
        return (id(pixels(rowsA, colsA)[0]), id(pixels(rowsB, colsB)[0]), id(pixels(rowsC, colsC)[0]))
    }

    // MARK: the planted spectrum image

    private static let channels = 512, dispersionKeV = 0.01
    private static let mgKa = 1.2536, alKa = 1.4865
    /// Expected counts per pixel in (Mg K-alpha, Al K-alpha): A, B, the matrix.
    private static let plantedA = (mg: 3.0, al: 6.0), plantedB = (mg: 6.0, al: 3.0), plantedMatrix = (mg: 0.3, al: 8.0)
    private static let kMg = 1.1

    /// The kit's detector width: FWHM(E) = sqrt(2.5 (E - 5.8987) 1000 + 130^2) eV, as a Gaussian sigma in keV.
    private static func sigma(_ e: Double) -> Double { (2.5 * (e - 5.8987) * 1000 + 130 * 130).squareRoot() / 1000 / 2.3548200450309493 }

    /// A line of `expected` counts shared out over the channels, each channel a Poisson draw (Knuth's product of uniforms; a seeded LCG).
    private func source() -> LoadedSpectrumImage {
        let n = Self.side * Self.side
        var counts = [UInt32](repeating: 0, count: n * Self.channels)
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
        func profile(_ e0: Double) -> [Double] {
            let s = Self.sigma(e0)
            let raw = (0..<Self.channels).map { exp(-pow(Double($0) * Self.dispersionKeV - e0, 2) / (2 * s * s)) }
            let total = raw.reduce(0, +)
            return raw.map { $0 / total }
        }
        let mgShape = profile(Self.mgKa), alShape = profile(Self.alKa)
        let a = Set(pixels(rowsA, colsA)), b = Set(pixels(rowsB, colsB))
        for p in 0..<n {
            let planted = a.contains(p) ? Self.plantedA : (b.contains(p) ? Self.plantedB : Self.plantedMatrix)
            for c in 0..<Self.channels {
                let mean = planted.mg * mgShape[c] + planted.al * alShape[c]
                if mean > 1e-9 { counts[p * Self.channels + c] = poisson(mean) }
            }
        }
        var meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: Self.side, scanHeight: Self.side,
                                         channelCount: Self.channels, energyOffsetEV: 0, energyDispersionEV: Self.dispersionKeV * 1000,
                                         scanPixelSize: 1, scanPixelUnit: "nm")
        meta.beamEnergyKeV = 200
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: Self.side, nx: Self.side, channels: Self.channels, counts: counts),
                                   metadata: meta, energyAxis: EnergyAxis(offset: 0, scale: Self.dispersionKeV, size: Self.channels))
    }

    /// The room's method for the planted image: Mg and Al quantified, Cliff-Lorimer with typed k (Mg 1.1 over Al, no k uncertainty so the
    /// sigma is the counting statistics'), no absorption.
    private var method: QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = [.init(symbol: "Mg", role: .quantify, isManual: true), .init(symbol: "Al", role: .quantify, isManual: true)]
        m.kFactorSource = .typed
        m.kSource = "planted"; m.kDate = "2026-11-10"; m.kReference = "Al"
        m.typedK = [.init(element: "Mg", k: Self.kMg, relativeSigma: 0), .init(element: "Al", k: 1, relativeSigma: 0)]
        m.absorptionCorrection = false
        return m
    }

    private func quantified() -> ObjectCompositionJoin.Quantified {
        .init(source: source(), method: method, tables: QuantificationTables.bundled())
    }

    private var identity: RegistrationRecordM2 { PoolCatalogue.identityRegistration(width: Self.side, height: Self.side) }

    /// The planted at% of Mg for expected line counts (mg, al): wt ratio k_Mg I_Mg / I_Al, then atoms by the atomic weights.
    private func plantedMgAtomicPercent(_ planted: (mg: Double, al: Double)) -> Double {
        let mg = Self.kMg * planted.mg / 24.305, al = planted.al / 26.9815
        return 100 * mg / (mg + al)
    }

    /// mac4DSTEM#113. At 3 to 6 counts per pixel in a line, the pooled fit of an object's summed spectrum recovers the planted at% within
    /// its own sigma (three sigma allowed), carries a sigma, and keeps the objects apart. Mutations: summing the whole map instead of the
    /// object (A and B read the same), the matrix pixels leaking into an object (Mg falls far outside the sigma), dropping the sigma.
    func testEachObjectIsOnePooledFitThatRecoversItsPlantedCompositionWithinItsSigma() throws {
        let id = ids()
        let result = ObjectCompositionJoin.run(objects: objects(), quantified: quantified(), registration: identity)
        XCTAssertNil(result.unavailable)
        let a = try XCTUnwrap(result.perObject[id.a], result.reasons[id.a] ?? "no A"), b = try XCTUnwrap(result.perObject[id.b], result.reasons[id.b] ?? "no B")
        XCTAssertEqual(a.pixels, 48); XCTAssertEqual(b.pixels, 25)
        XCTAssertGreaterThan(a.counts, 300); XCTAssertLessThan(a.counts, 560, "about 48 x 9 counts")
        for (value, planted, name) in [(a, Self.plantedA, "A"), (b, Self.plantedB, "B")] {
            let mg = try XCTUnwrap(value.elements.first { $0.symbol == "Mg" })
            let at = try XCTUnwrap(mg.atomicPercent), sigma = try XCTUnwrap(mg.atomicSigma, "the pooled fit has a sigma")
            XCTAssertGreaterThan(sigma, 0.5, name); XCTAssertLessThan(sigma, 8, name)
            XCTAssertEqual(at, plantedMgAtomicPercent(planted), accuracy: 3 * sigma, "\(name): Mg \(at) ± \(sigma) at%")
            let al = try XCTUnwrap(value.elements.first { $0.symbol == "Al" }?.atomicPercent)
            XCTAssertEqual(at + al, 100, accuracy: 1e-6)
            XCTAssertNotNil(mg.weightPercent); XCTAssertNotNil(mg.weightSigma)
        }
        let mgA = try XCTUnwrap(a.elements.first { $0.symbol == "Mg" }?.atomicPercent), mgB = try XCTUnwrap(b.elements.first { $0.symbol == "Mg" }?.atomicPercent)
        XCTAssertGreaterThan(mgB - mgA, 15, "objects must not mix: planted 37.9 and 70.9 at% Mg")
        XCTAssertNil(result.perObject[id.c])
        XCTAssertEqual(result.reasons[id.c], "under 4 EDS px")
    }

    func testNothingQuantifiedNoRegistrationAndWrongGridsSayWhy() throws {
        XCTAssertEqual(ObjectCompositionJoin.run(objects: objects(), quantified: nil, registration: identity).unavailable,
                       ObjectCompositionJoin.notQuantifiedSentence)
        XCTAssertNotNil(ObjectCompositionJoin.run(objects: objects(), quantified: quantified(), registration: nil).unavailable)
        XCTAssertNotNil(ObjectCompositionJoin.run(objects: objects(), quantified: quantified(),
                                                  registration: PoolCatalogue.identityRegistration(width: 4, height: 4)).unavailable)
    }

    /// A fit the kit refuses is that object's reason, in the kit's words, never a missing row or a made-up number: typed k without the
    /// factor of a quantified element cannot give a composition.
    func testAFitTheKitRefusesIsTheObjectsReason() throws {
        var incomplete = method
        incomplete.typedK = [.init(element: "Al", k: 1, relativeSigma: 0)]
        let result = ObjectCompositionJoin.run(objects: objects(), quantified: .init(source: source(), method: incomplete, tables: QuantificationTables.bundled()),
                                               registration: identity)
        let id = ids()
        XCTAssertNil(result.perObject[id.a])
        XCTAssertFalse(try XCTUnwrap(result.reasons[id.a]).isEmpty)
        XCTAssertEqual(result.reasons[id.c], "under 4 EDS px", "the pixel rule is said before any fit")
    }

    /// A stopped run says so and lands nothing half-made.
    func testACancelledRunSaysSo() {
        let result = ObjectCompositionJoin.run(objects: objects(), quantified: quantified(), registration: identity, cancelled: { true })
        XCTAssertNotNil(result.unavailable); XCTAssertTrue(result.perObject.isEmpty)
    }

    private func strainMap(dropB: Int) -> StrainMap {
        let n = Self.side * Self.side
        var exx = [Float](repeating: 0, count: n), eyy = exx, exy = exx, theta = exx
        var mask = [Bool](repeating: true, count: n)
        for p in pixels(rowsA, colsA) { exx[p] = 0.01; eyy[p] = -0.005; exy[p] = 0.002; theta[p] = .pi / 180 }
        let b = pixels(rowsB, colsB)
        exx[b[0]] = 0.02; exx[b[1]] = 0.04; exx[b[2]] = 0.02; exx[b[3]] = 0.04
        for p in b { eyy[p] = 0.001 }
        for p in b.dropFirst(4) { mask[p] = false }          // B's strain is planted on its first four pixels only
        exx[b[dropB]] = 9.9; mask[b[dropB]] = false
        for p in pixels(rowsC, colsC) { mask[p] = false }
        let zeros = [Float](repeating: 0, count: n)
        return StrainMap(
            width: Self.side, height: Self.side, exx: exx, eyy: eyy, exy: exy, theta: theta, mask: mask,
            localG1x: zeros, localG1y: zeros, localG2x: zeros, localG2y: zeros, localResidualPixels: zeros,
            refG1: (x: 0, y: 0), refG2: (x: 0, y: 0), referencePositionCount: 0, indexedFraction: 1,
            diagnostics: StrainFitDiagnostics(
                automaticBasis: true, referenceMaskApplied: false, basisObservationCount: 0, basisSupportCount: 0,
                basisSupportFraction: 0, basisResidualPixels: 0, basisConditionNumber: 1, indexingTolerancePixels: 0,
                localResidualMedianPixels: 0, referenceCandidateCount: 0, referenceRejectedCount: 0))
    }

    func testStrainIsPerObjectExcludesUnfittedPixelsAndUsesRowsAndColumns() throws {
        let id = ids()
        // Drop the pixel holding 0.04 (index 1), so B's fitted pixels hold 0.02, 0.02, 0.04: mean 0.08/3.
        let result = ObjectStrainJoin.run(objects: objects(), strain: strainMap(dropB: 1).presented(in: .detector))
        XCTAssertNil(result.unavailable)
        let a = try XCTUnwrap(result.perObject[id.a]), b = try XCTUnwrap(result.perObject[id.b])
        XCTAssertEqual(a.cc, 0.01, accuracy: 1e-6); XCTAssertEqual(a.rr, -0.005, accuracy: 1e-6)
        XCTAssertEqual(a.rc, 0.002, accuracy: 1e-6); XCTAssertEqual(a.rotationDegrees, 1, accuracy: 1e-4)
        XCTAssertEqual(a.sigmaCC, 0, accuracy: 1e-7); XCTAssertEqual(a.pixels, 48)
        XCTAssertEqual(b.cc, 0.08 / 3, accuracy: 1e-6, "the unfitted pixel's 9.9 must not enter the mean")
        XCTAssertEqual(b.pixels, 3); XCTAssertGreaterThan(b.sigmaCC, 0)
        XCTAssertNil(result.perObject[id.c])
        XCTAssertEqual(result.reasons[id.c], "no strain fit under the object")
    }

    func testNoStrainAndWrongScanSayWhy() {
        XCTAssertEqual(ObjectStrainJoin.run(objects: objects(), strain: nil).unavailable, ObjectStrainJoin.noStrainSentence)
        var other = strainMap(dropB: 0)
        other = StrainMap(width: 8, height: 32, exx: other.exx, eyy: other.eyy,
                          exy: other.exy, theta: other.theta, mask: other.mask,
                          localG1x: other.localG1x, localG1y: other.localG1y, localG2x: other.localG2x, localG2y: other.localG2y,
                          localResidualPixels: other.localResidualPixels, refG1: other.refG1, refG2: other.refG2,
                          referencePositionCount: 0, indexedFraction: 1, diagnostics: other.diagnostics)
        XCTAssertNotNil(ObjectStrainJoin.run(objects: objects(), strain: other.presented(in: .detector)).unavailable)
    }

    func testTheReportCarriesTheJoinsIntoRowsAndCSV() throws {
        let id = ids()
        let comp = ObjectCompositionJoin.run(objects: objects(), quantified: quantified(), registration: identity)
        let strain = ObjectStrainJoin.run(objects: objects(), strain: strainMap(dropB: 1).presented(in: .detector))
        let report = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: comp, strainJoin: strain)
        let rowA = try XCTUnwrap(report.rows.first { $0.id == id.a })
        XCTAssertEqual(rowA.compositionPixels, 48)
        XCTAssertEqual(rowA.compositionCounts, comp.perObject[id.a]?.counts)
        XCTAssertEqual(try XCTUnwrap(rowA.strain).pixels, 48)
        let csv = report.csv()
        XCTAssertTrue(csv.contains("composition_px,composition_counts,mg_at_pct,mg_at_pct_sigma,mg_wt_pct,mg_wt_pct_sigma,al_at_pct,al_at_pct_sigma"), csv)
        XCTAssertTrue(csv.contains("# composition: one pooled fit per object"), "the header says what the number is")
        XCTAssertTrue(csv.contains("strain_rr"))
        XCTAssertFalse(csv.contains("per-pixel"), "no sentence of the old mean is left")
        let plain = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1)
        XCTAssertFalse(plain.csv().contains("strain_rr") || plain.csv().contains("_at_pct"), "no joins, no columns")
    }

    /// #108: the composition says which elements it covers, so an element the EDS room did not quantify is visibly absent.
    func testTheReportSaysWhichElementsTheCompositionCovers() throws {
        let comp = ObjectCompositionJoin.run(objects: objects(), quantified: quantified(), registration: identity)
        let report = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: comp)
        XCTAssertEqual(report.compositionCoverage, "Composition over Mg, Al (quantified elements)")
        let plain = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1)
        XCTAssertNil(plain.compositionCoverage, "no composition, no coverage line")
    }
}

extension ObjectJoinsTests {
    func testTheTableCellsSayTheValueOrTheReason() throws {
        let id = ids()
        let comp = ObjectCompositionJoin.run(objects: objects(), quantified: quantified(), registration: identity)
        let strain = ObjectStrainJoin.run(objects: objects(), strain: strainMap(dropB: 1).presented(in: .detector))
        let report = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: comp, strainJoin: strain)
        let a = try XCTUnwrap(report.rows.first { $0.id == id.a }), c = try XCTUnwrap(report.rows.first { $0.id == id.c })
        // "Mg 37.x ± s · Al 62.x ± s at% (48 px)": the value with the fit's sigma and the pixels summed.
        XCTAssertTrue(a.compositionSummary.hasPrefix("Mg "), a.compositionSummary)
        XCTAssertTrue(a.compositionSummary.contains(" ± ") && a.compositionSummary.contains(" · Al "), a.compositionSummary)
        XCTAssertTrue(a.compositionSummary.hasSuffix(" at% (48 px)"), a.compositionSummary)
        XCTAssertEqual(a.strainSummary, "rr -0.50 · cc 1.00 · rc 0.20 %, 1.00°")
        XCTAssertEqual(c.compositionSummary, "under 4 EDS px")
        XCTAssertEqual(c.strainSummary, "no strain fit under the object")
        let none = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: ObjectCompositionJoin.run(objects: objects(), quantified: nil, registration: nil),
            strainJoin: ObjectStrainJoin.run(objects: objects(), strain: nil))
        XCTAssertEqual(none.compositionUnavailable, ObjectCompositionJoin.notQuantifiedSentence)
        XCTAssertEqual(none.strainUnavailable, ObjectStrainJoin.noStrainSentence)
        XCTAssertTrue(none.csv().contains("# composition: not available"))
    }
}
