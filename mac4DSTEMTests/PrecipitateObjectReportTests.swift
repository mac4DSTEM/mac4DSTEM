//
//  PrecipitateObjectReportTests.swift
//  The object table (`Session/PrecipitateObjectReport.swift`): the minimum
//  size and edge rules, physical units from the report-time calibration, the
//  CSV, and the objects image. Every expected value is hand-derived from the
//  8 × 6 fixture below.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PrecipitateObjectReportTests: XCTestCase {

    /// 8 wide × 6 high, row-major. Phase 1 has three objects:
    ///   A — 3 px, interior, row 2 cols 2–4 (a horizontal bar)
    ///   B — 1 px, interior, row 4 col 5
    ///   C — 2 px on the right edge, rows 1–2 col 7
    /// Label 0 is the matrix everywhere else; label −1 (not indexed) at (0, 5).
    private func fixture() -> (labels: [Int32], objects: PrecipitateSegmentation.ClassMapObjects) {
        var labels = [Int32](repeating: 0, count: 8 * 6)
        for x in 2...4 { labels[2 * 8 + x] = 1 }       // A
        labels[4 * 8 + 5] = 1                          // B
        labels[1 * 8 + 7] = 1; labels[2 * 8 + 7] = 1   // C
        labels[5 * 8 + 0] = -1
        let objects = PrecipitateSegmentation.classObjects(
            labels: labels, width: 8, height: 6,
            roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [-1]),
            pixelSize: nil, pixelUnit: nil)
        return (labels, objects)
    }

    private let names = ["Al", "θ′"]

    /// (1) Minimum size 2: A is counted, B is small, C is on the edge.
    /// Break-first: `area >= minimum` changed to `>` in `make` makes C (2 px)
    /// "small" as well — belowMinimumExcluded 2, edgeExcluded 0 — so this must
    /// go red.
    func testMinimumSizeAndEdgeRules() throws {
        let report = PrecipitateObjectReport.make(
            objects: fixture().objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: nil, pixelUnit: nil, minimumAreaPx: 2)
        let summary = try XCTUnwrap(report.summaries.first)
        XCTAssertEqual(summary.phaseName, "θ′")
        XCTAssertEqual(summary.totalObjects, 3)
        XCTAssertEqual(summary.countedObjects, 1, "only A")
        XCTAssertEqual(summary.edgeExcluded, 1, "C")
        XCTAssertEqual(summary.belowMinimumExcluded, 1, "B")
        XCTAssertEqual(summary.medianLengthPx, 3, "A alone: a 3-px bar is 3 long")
        XCTAssertEqual(report.rows.count, 3, "excluded objects stay listed")
        XCTAssertEqual(report.rows.filter(\.isCounted).map(\.areaPx), [3])
        XCTAssertEqual(Set(report.rows.compactMap(\.exclusion)), ["small", "edge"])
    }

    /// (2) Minimum size 1 keeps every object; 0 or negative clamps to 1.
    /// Break-first: dropping `max(1, …)` stores 0, so this must go red.
    func testMinimumSizeClampsToOne() {
        let report = PrecipitateObjectReport.make(
            objects: fixture().objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: nil, pixelUnit: nil, minimumAreaPx: 0)
        XCTAssertEqual(report.minimumAreaPx, 1)
        XCTAssertEqual(report.summaries.first?.belowMinimumExcluded, 0)
        XCTAssertEqual(report.summaries.first?.countedObjects, 2, "A and B; C is on the edge")
    }

    /// (3) Physical values come from the report-time scale: 2 nm per pixel
    /// makes A 12 nm² and 6 nm long, and density = counted / (analysed × 4).
    /// Analysed = 48 − 1 not indexed = 47. Break-first: area scaled by the
    /// pixel size once instead of squared gives 6, so this must go red.
    func testPhysicalValuesUseTheReportTimeScale() throws {
        let report = PrecipitateObjectReport.make(
            objects: fixture().objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: 2, pixelUnit: "nm", minimumAreaPx: 1)
        let a = try XCTUnwrap(report.rows.first { $0.areaPx == 3 })
        XCTAssertEqual(try XCTUnwrap(a.area), 12, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(a.length), 6, accuracy: 1e-6)
        let summary = try XCTUnwrap(report.summaries.first)
        XCTAssertEqual(try XCTUnwrap(summary.arealDensity), 2.0 / (47.0 * 4.0), accuracy: 1e-12)

        let unscaled = PrecipitateObjectReport.make(
            objects: fixture().objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: nil, pixelUnit: nil, minimumAreaPx: 1)
        XCTAssertNil(unscaled.rows.first?.area, "no scale, no physical value")
        XCTAssertNil(unscaled.summaries.first?.arealDensity, "no scale, no density")
        XCTAssertFalse(unscaled.hasPhysicalScale)
    }

    /// (4) The CSV carries the provenance, one header, one line per object,
    /// and leaves physical columns empty without a scale. Break-first: the
    /// provenance loop removed drops `# validation: none`, so this must go red.
    func testCSVCarriesProvenanceAndOneLinePerObject() {
        let report = PrecipitateObjectReport.make(
            objects: fixture().objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: nil, pixelUnit: nil, minimumAreaPx: 2,
            provenance: [("validation", "none"), ("method", "vector_matching")])
        let lines = report.csv().split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.isEmpty }
        XCTAssertTrue(lines.contains("# validation: none"))
        let header = lines.firstIndex { $0.hasPrefix("id,phase,counted") }
        XCTAssertNotNil(header)
        let data = lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix("id,") }
        XCTAssertEqual(data.count, 3)
        for line in data {
            XCTAssertTrue(line.hasSuffix(",,,"), "physical columns empty without a scale: \(line)")
        }
        XCTAssertTrue(data.contains { $0.contains(",0,small,1,") }, "B: not counted, small, 1 px")
    }

    /// (5) The image draws what the numbers count: A (counted) in full phase
    /// colour, B (small) dimmed, the not-indexed position hatched grey.
    /// Break-first: drawing every object in full colour makes B equal A, so
    /// this must go red.
    func testImageDrawsCountedObjectsFullAndExcludedDimmed() {
        let (labels, objects) = fixture()
        let report = PrecipitateObjectReport.make(
            objects: objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: nil, pixelUnit: nil, minimumAreaPx: 2)
        let verdicts: [PhaseVerdict] = labels.map {
            $0 == -1 ? .notIndexed : ($0 == 0 ? .matrix : .indexed)
        }
        let image = PrecipitateObjectReport.image(
            objects: objects, report: report, verdicts: verdicts, matrixPhaseIndex: 0)
        func rgb(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * 8 + x) * 4
            return Array(image.rgba[i..<i + 3])
        }
        let full = PhaseMapPresentation.color(phaseIndex: 1, matrixPhaseIndex: 0)
        XCTAssertEqual(rgb(3, 2), [full.r, full.g, full.b], "A counted: full colour")
        XCTAssertNotEqual(rgb(5, 4), rgb(3, 2), "B small: dimmed, not full")
        XCTAssertNotEqual(rgb(5, 4), rgb(0, 0), "B is still drawn, not matrix")
        let hatch = PhaseMapPresentation.notIndexedColors
        XCTAssertTrue([[hatch.0.r, hatch.0.g, hatch.0.b], [hatch.1.r, hatch.1.g, hatch.1.b]]
                        .contains(rgb(0, 5)), "not indexed keeps the phase map's hatch")
    }
}
