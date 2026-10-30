// Suite task 42: composition and strain per precipitate object, on a planted 8 x 8 scan. Registration, stated before the first run:
// three objects that touch neither each other nor the edge: A (rows 1-3, cols 1-2, 6 px), B (rows 5-6, cols 5-6, 4 px), C (rows 1-2,
// cols 5-6, 4 px). Mg/Al net counts are constant per object (A 100/100, B 300/100, C 50/100) so each object's mean equals the kit's
// single-pixel call on its own counts and the three differ. Plants: one failed pixel in A (negative Mg: the fit refuses it), two in C.
// Expected: A is counted over 5 EDS px with 1 excluded; B over 4 px; C has no composition ("under 4 EDS px"); A's value is not B's.
// Strain: exx 0.01 over A, 0.02 / 0.04 over B's pixels (mean 0.03, spread > 0), one B pixel outside the fit mask holding 9.9 that must
// not enter the mean; C has no fitted pixel ("no strain fit under the object"); eyy is the ROW direction (rr), exx the column (cc).

import XCTest
import DSTEMCore
import DSTEMSession
import ImagoCore
import SpectroCore
import SpectroEDX
@testable import mac4DSTEM
import ShellEDXModel

final class ObjectJoinsTests: XCTestCase {
    private let n = 8
    private let rowsA = [1, 2, 3], colsA = [1, 2]
    private let rowsB = [5, 6], colsB = [5, 6]
    private let rowsC = [1, 2], colsC = [5, 6]

    private func pixels(_ rows: [Int], _ cols: [Int]) -> [Int] { rows.flatMap { r in cols.map { r * 8 + $0 } } }

    private func objects() -> PrecipitateSegmentation.ClassMapObjects {
        var labels = [Int32](repeating: 0, count: 64)
        for p in pixels(rowsA, colsA) + pixels(rowsB, colsB) + pixels(rowsC, colsC) { labels[p] = 1 }
        return PrecipitateSegmentation.classObjects(
            labels: labels, width: 8, height: 8, roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [9]),
            pixelSize: nil, pixelUnit: nil)
    }

    /// Object ids by their first pixel (A, C above B in scan order): A, C, B.
    private func ids() -> (a: Int, b: Int, c: Int) {
        let all = objects().classes.flatMap(\.objects)
        func id(_ p: Int) -> Int { all.first { $0.pixelIndices.contains(p) }!.id }
        return (id(8 + 1), id(5 * 8 + 5), id(8 + 5))
    }

    private let setup = EDXQuantificationSetup(elements: ["Mg", "Al"], method: .cliffLorimer(kFactors: [1.1, 1.0], thicknessNm: nil), absorption: nil)

    private func maps() throws -> EDXQuantificationMaps {
        var mg = [Double](repeating: 0, count: 64), al = [Double](repeating: 0, count: 64)
        for p in pixels(rowsA, colsA) { mg[p] = 100; al[p] = 100 }
        for p in pixels(rowsB, colsB) { mg[p] = 300; al[p] = 100 }
        for p in pixels(rowsC, colsC) { mg[p] = 50; al[p] = 100 }
        mg[1 * 8 + 1] = -5                                   // A: one failed pixel
        mg[1 * 8 + 5] = -5; mg[1 * 8 + 6] = -5               // C: two failed pixels
        for p in 0..<64 where mg[p] == 0 && al[p] == 0 { mg[p] = 10; al[p] = 10 }   // matrix, not under any object
        // The kit's map pass, as the EDS session calls it (no count mask).
        return try EDXQuantification.quantifyMaps(intensityMaps: [mg, al], rows: 8, columns: 8, setup: setup, navigationMask: nil)
    }

    func testEachObjectGetsItsOwnPlantedCompositionAndTheFailedPixelIsCounted() throws {
        let id = ids()
        let result = ObjectCompositionJoin.run(objects: objects(), maps: try maps(),
                                               registration: PoolCatalogue.identityRegistration(width: 8, height: 8))
        XCTAssertNil(result.unavailable)
        let a = try XCTUnwrap(result.perObject[id.a]), b = try XCTUnwrap(result.perObject[id.b])
        XCTAssertEqual(a.pixels, 5); XCTAssertEqual(a.excluded, 1)
        XCTAssertEqual(b.pixels, 4); XCTAssertEqual(b.excluded, 0)
        let kitA = try EDXQuantification.quantify(intensities: [100, 100], setup: setup)
        let kitB = try EDXQuantification.quantify(intensities: [300, 100], setup: setup)
        XCTAssertEqual(try XCTUnwrap(a.elements.first { $0.symbol == "Mg" }?.weightPercent), kitA.weightPercent[0], accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.elements.first { $0.symbol == "Mg" }?.atomicPercent), kitB.atomicPercent[0], accuracy: 1e-9)
        XCTAssertNotEqual(a.elements[0].weightPercent, b.elements[0].weightPercent, "objects must not mix")
        XCTAssertNil(result.perObject[id.c])
        XCTAssertEqual(result.reasons[id.c], "under 4 EDS px")
    }

    func testNoMapsNoRegistrationAndWrongGridsSayWhy() throws {
        let identity = PoolCatalogue.identityRegistration(width: 8, height: 8)
        XCTAssertEqual(ObjectCompositionJoin.run(objects: objects(), maps: nil, registration: identity).unavailable,
                       ObjectCompositionJoin.noMapsSentence)
        XCTAssertNotNil(ObjectCompositionJoin.run(objects: objects(), maps: try maps(), registration: nil).unavailable)
        XCTAssertNotNil(ObjectCompositionJoin.run(objects: objects(), maps: try maps(),
                                                  registration: PoolCatalogue.identityRegistration(width: 4, height: 4)).unavailable)
    }

    private func strainMap(dropB: Int) -> StrainMap {
        var exx = [Float](repeating: 0, count: 64), eyy = exx, exy = exx, theta = exx
        var mask = [Bool](repeating: true, count: 64)
        for p in pixels(rowsA, colsA) { exx[p] = 0.01; eyy[p] = -0.005; exy[p] = 0.002; theta[p] = .pi / 180 }
        let b = pixels(rowsB, colsB)
        exx[b[0]] = 0.02; exx[b[1]] = 0.04; exx[b[2]] = 0.02; exx[b[3]] = 0.04
        for p in b { eyy[p] = 0.001 }
        exx[b[dropB]] = 9.9; mask[b[dropB]] = false
        for p in pixels(rowsC, colsC) { mask[p] = false }
        let zeros = [Float](repeating: 0, count: 64)
        return StrainMap(
            width: 8, height: 8, exx: exx, eyy: eyy, exy: exy, theta: theta, mask: mask,
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
        XCTAssertEqual(a.sigmaCC, 0, accuracy: 1e-7); XCTAssertEqual(a.pixels, 6)
        XCTAssertEqual(b.cc, 0.08 / 3, accuracy: 1e-6, "the unfitted pixel's 9.9 must not enter the mean")
        XCTAssertEqual(b.pixels, 3); XCTAssertGreaterThan(b.sigmaCC, 0)
        XCTAssertNil(result.perObject[id.c])
        XCTAssertEqual(result.reasons[id.c], "no strain fit under the object")
    }

    func testNoStrainAndWrongScanSayWhy() {
        XCTAssertEqual(ObjectStrainJoin.run(objects: objects(), strain: nil).unavailable, ObjectStrainJoin.noStrainSentence)
        var other = strainMap(dropB: 0)
        other = StrainMap(width: 4, height: 16, exx: Array(other.exx[0..<64]), eyy: Array(other.eyy[0..<64]),
                          exy: Array(other.exy[0..<64]), theta: Array(other.theta[0..<64]), mask: Array(other.mask[0..<64]),
                          localG1x: other.localG1x, localG1y: other.localG1y, localG2x: other.localG2x, localG2y: other.localG2y,
                          localResidualPixels: other.localResidualPixels, refG1: other.refG1, refG2: other.refG2,
                          referencePositionCount: 0, indexedFraction: 1, diagnostics: other.diagnostics)
        XCTAssertNotNil(ObjectStrainJoin.run(objects: objects(), strain: other.presented(in: .detector)).unavailable)
    }

    func testTheReportCarriesTheJoinsIntoRowsAndCSV() throws {
        let id = ids()
        let comp = ObjectCompositionJoin.run(objects: objects(), maps: try maps(),
                                             registration: PoolCatalogue.identityRegistration(width: 8, height: 8))
        let strain = ObjectStrainJoin.run(objects: objects(), strain: strainMap(dropB: 1).presented(in: .detector))
        let report = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: comp, strainJoin: strain)
        let rowA = try XCTUnwrap(report.rows.first { $0.id == id.a })
        XCTAssertEqual(rowA.compositionPixels, 5)
        XCTAssertEqual(try XCTUnwrap(rowA.strain).pixels, 6)
        let csv = report.csv()
        XCTAssertTrue(csv.contains("mg_at_pct") && csv.contains("strain_rr"), csv)
        let plain = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1)
        XCTAssertFalse(plain.csv().contains("strain_rr") || plain.csv().contains("_at_pct"), "no joins, no columns")
    }
}

extension ObjectJoinsTests {
    func testTheTableCellsSayTheValueOrTheReason() throws {
        let id = ids()
        let comp = ObjectCompositionJoin.run(objects: objects(), maps: try maps(),
                                             registration: PoolCatalogue.identityRegistration(width: 8, height: 8))
        let strain = ObjectStrainJoin.run(objects: objects(), strain: strainMap(dropB: 1).presented(in: .detector))
        let report = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: comp, strainJoin: strain)
        let a = try XCTUnwrap(report.rows.first { $0.id == id.a }), c = try XCTUnwrap(report.rows.first { $0.id == id.c })
        XCTAssertEqual(a.compositionSummary, "Mg 55.0 · Al 45.0 at% (5 px, 1 failed or masked)")
        XCTAssertEqual(a.strainSummary, "rr -0.50 · cc 1.00 · rc 0.20 %, 1.00°")
        XCTAssertEqual(c.compositionSummary, "under 4 EDS px")
        XCTAssertEqual(c.strainSummary, "no strain fit under the object")
        let none = PrecipitateObjectReport.make(
            objects: objects(), phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1,
            compositionJoin: ObjectCompositionJoin.run(objects: objects(), maps: nil, registration: nil),
            strainJoin: ObjectStrainJoin.run(objects: objects(), strain: nil))
        XCTAssertEqual(none.compositionUnavailable, ObjectCompositionJoin.noMapsSentence)
        XCTAssertEqual(none.strainUnavailable, ObjectStrainJoin.noStrainSentence)
        XCTAssertTrue(none.csv().contains("# composition: not available"))
    }
}
