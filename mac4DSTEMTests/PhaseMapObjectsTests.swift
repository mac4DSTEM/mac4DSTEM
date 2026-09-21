//
//  PhaseMapObjectsTests.swift
//  Class-map → per-class objects → per-class statistics
//  (docs/v3-precipitate-classification.md §2 steps 5–6, decision 019).
//  Every expected number here is arithmetic on a hand-drawn 12 × 9 label map,
//  written before the implementation and broken against it before trusted.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseMapObjectsTests: XCTestCase {

    // MARK: - Fixture
    //
    // 12 wide × 9 tall, row-major. 0 = matrix, 1 / 2 = precipitate classes,
    // N (-1) = not indexed.
    //
    //   col: 0 1 2 3 4 5 6 7 8 9 10 11
    // row0:  0 0 0 0 0 0 0 0 0 0  0  0
    // row1:  0 0 1 1 1 0 0 0 0 0  0  0     A1: class 1, 3 × 2 = 6 px
    // row2:  0 0 1 1 1 0 0 0 0 0  0  0
    // row3:  0 0 0 2 2 2 2 N 0 0  0  0     B1: class 2, 4 × 2 = 8 px
    // row4:  0 0 0 2 2 2 2 N 0 0  1  1     A2: class 1, 2 × 2 = 4 px, on the right edge
    // row5:  0 0 0 0 0 N 0 0 0 0  1  1
    // row6:  0 0 0 0 0 0 0 0 0 0  0  0
    // row7:  0 0 0 0 0 0 0 0 0 0  0  0
    // row8:  0 0 0 0 0 0 0 0 0 0  0  0
    //
    // A1 and B1 are 8-adjacent (row 2 / row 3) but different classes, so they
    // must never merge. Three not-indexed holes: (3,7), (4,7), (5,5).
    //
    // Pixel accounting: total 108 = class 1 (10) + class 2 (8) + N (3) + matrix (87).
    // Analysed = 108 − 3 = 105.

    private let width = 12
    private let height = 9
    private let notIndexed: Int32 = -1

    private func fixtureLabels() -> [Int32] {
        var labels = [Int32](repeating: 0, count: 12 * 9)
        func set(_ row: Int, _ cols: ClosedRange<Int>, _ value: Int32) {
            for c in cols { labels[row * 12 + c] = value }
        }
        set(1, 2...4, 1); set(2, 2...4, 1)          // A1
        set(3, 3...6, 2); set(4, 3...6, 2)          // B1
        set(4, 10...11, 1); set(5, 10...11, 1)      // A2 (touches col 11)
        labels[3 * 12 + 7] = notIndexed
        labels[4 * 12 + 7] = notIndexed
        labels[5 * 12 + 5] = notIndexed
        return labels
    }

    private func roles(classes: Set<Int32> = [1, 2]) -> PrecipitateSegmentation.LabelRoles {
        return PrecipitateSegmentation.LabelRoles(
            precipitateClasses: classes, matrix: [0], notIndexed: [notIndexed]
        )
    }

    private func classMap(
        classes: Set<Int32> = [1, 2], pixelSize: Double? = nil, pixelUnit: String? = nil
    ) -> PrecipitateSegmentation.ClassMapObjects {
        return PrecipitateSegmentation.classObjects(
            labels: fixtureLabels(), width: width, height: height,
            roles: roles(classes: classes), pixelSize: pixelSize, pixelUnit: pixelUnit
        )
    }

    private func cls(_ label: Int32, in result: PrecipitateSegmentation.ClassMapObjects,
                     file: StaticString = #filePath, line: UInt = #line)
        throws -> PrecipitateSegmentation.ClassObjects {
        return try XCTUnwrap(result.classes.first { $0.label == label },
                             "class \(label) missing from the result", file: file, line: line)
    }

    // MARK: - 1. Objects per class, pixel counts, centroids, the edge flag

    func testTwoClassOneObjectsAndOneClassTwoObjectWithEdgeFlag() throws {
        let result = classMap()
        XCTAssertEqual(result.width, 12)
        XCTAssertEqual(result.height, 9)
        XCTAssertEqual(result.classes.map(\.label), [1, 2], "classes come back in ascending label order")

        let one = try cls(1, in: result)
        XCTAssertEqual(one.objects.count, 2, "A1 and A2, both listed — the edge object is flagged, not deleted")
        XCTAssertEqual(one.pixelCount, 10)

        // Largest first, matching `segment`'s ordering.
        let a1 = one.objects[0], a2 = one.objects[1]
        XCTAssertEqual(a1.area, 6)
        XCTAssertEqual(a1.pixelIndices, [14, 15, 16, 26, 27, 28], "row-major, ascending")
        XCTAssertEqual(a1.centroidX, 3, accuracy: 1e-6)
        XCTAssertEqual(a1.centroidY, 1.5, accuracy: 1e-6)
        XCTAssertFalse(a1.touchesEdge)
        // Existing measurement, unchanged: a 3 × 2 block is 3 long, 2 wide, along +x.
        XCTAssertEqual(a1.lengthPx, 3, accuracy: 1e-6)
        XCTAssertEqual(a1.widthPx, 2, accuracy: 1e-6)
        XCTAssertEqual(a1.orientationDegrees, 0, accuracy: 1e-6)

        XCTAssertEqual(a2.area, 4)
        XCTAssertEqual(a2.centroidX, 10.5, accuracy: 1e-6)
        XCTAssertEqual(a2.centroidY, 4.5, accuracy: 1e-6)
        XCTAssertTrue(a2.touchesEdge, "col 11 is the last column")

        XCTAssertEqual(one.density.acceptedCount, 1, "A2 touches the scan edge and is not counted")
        XCTAssertEqual(one.density.edgeCount, 1)

        let two = try cls(2, in: result)
        XCTAssertEqual(two.objects.count, 1, "B1 alone — it touches A1 but is another class")
        XCTAssertEqual(two.pixelCount, 8)
        let b1 = two.objects[0]
        XCTAssertEqual(b1.area, 8)
        XCTAssertEqual(b1.centroidX, 4.5, accuracy: 1e-6)
        XCTAssertEqual(b1.centroidY, 3.5, accuracy: 1e-6)
        XCTAssertFalse(b1.touchesEdge)
        XCTAssertEqual(b1.lengthPx, 4, accuracy: 1e-6)
        XCTAssertEqual(b1.widthPx, 2, accuracy: 1e-6)
        XCTAssertEqual(two.density.acceptedCount, 1)
        XCTAssertEqual(two.density.edgeCount, 0)

        // Object ids are unique across classes, so one inspector list can
        // key on `rowIdentity` without collisions.
        let ids = result.classes.flatMap { $0.objects.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - 2. Connectivity: 8-connected, matching py4DSTEM's explicit
    // `BraggVectorClassification` `skimage.measure.label(..., connectivity: 2)` path.

    func testDiagonalNeighboursFormOneObjectUnderEightConnectivity() throws {
        // 4 × 4. Class 1 at (0,0) and (1,1) — corner contact only — plus two
        // isolated class-1 pixels (3,0) and (3,2) separated by a gap. Class 2
        // at (1,2), 4-adjacent to the class-1 pixel at (1,1): never merged.
        // skimage.measure.label with connectivity=2 on this array gives 3
        // class-1 objects (verified 2026-09-21, skimage 0.24.0); connectivity=1
        // would give 4. py4DSTEM's `BraggVectorClassification` states 2 explicitly.
        var labels = [Int32](repeating: 0, count: 16)
        labels[0 * 4 + 0] = 1; labels[1 * 4 + 1] = 1
        labels[3 * 4 + 0] = 1; labels[3 * 4 + 2] = 1
        labels[1 * 4 + 2] = 2
        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 4, height: 4,
            roles: .init(precipitateClasses: [1, 2], matrix: [0], notIndexed: [notIndexed]),
            pixelSize: nil, pixelUnit: nil
        )
        XCTAssertEqual(result.connectivity, 8)
        let one = try cls(1, in: result)
        XCTAssertEqual(one.objects.count, 3, "the diagonal pair is ONE object under 8-connectivity")
        XCTAssertEqual(one.objects.map(\.area), [2, 1, 1], "largest first")
        XCTAssertEqual(one.objects[0].pixelIndices, [0, 5])
        let two = try cls(2, in: result)
        XCTAssertEqual(two.objects.count, 1)
        XCTAssertEqual(two.objects[0].pixelIndices, [6])
    }

    // MARK: - 3. Not-indexed holes leave the analysed area; area fraction is per analysed pixel

    func testNotIndexedHolesReduceTheAnalysedAreaByTheirCount() throws {
        let result = classMap()
        XCTAssertEqual(result.notIndexedPixels, 3)
        XCTAssertEqual(result.analysedPixels, 105, "108 − 3 holes")
        XCTAssertEqual(result.matrixPixels, 87)
        XCTAssertEqual(result.otherPixels, 0)
        XCTAssertEqual(try XCTUnwrap(result.notIndexedFraction), 3.0 / 108.0, accuracy: 1e-12)
        // The accounting closes: every position is exactly one of these.
        let classPixels = result.classes.reduce(0) { $0 + $1.pixelCount }
        XCTAssertEqual(result.matrixPixels + classPixels + result.otherPixels + result.notIndexedPixels, 108)

        let one = try cls(1, in: result), two = try cls(2, in: result)
        XCTAssertEqual(try XCTUnwrap(one.areaFraction), 10.0 / 105.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(two.areaFraction), 8.0 / 105.0, accuracy: 1e-12)
        XCTAssertEqual(one.density.analysedPixels, 105)
        XCTAssertEqual(two.density.analysedPixels, 105)
        XCTAssertFalse(result.analysedAreaRule.isEmpty, "the rule travels with the result for provenance")

        // A phase that is indexed but marked neither precipitate nor matrix
        // still received a verdict: it stays in the analysed area, as "other".
        let onlyOne = classMap(classes: [1])
        XCTAssertEqual(onlyOne.classes.map(\.label), [1])
        XCTAssertEqual(onlyOne.otherPixels, 8, "class 2's pixels, no longer a precipitate class")
        XCTAssertEqual(onlyOne.analysedPixels, 105, "unchanged — a verdict is a verdict")
    }

    // MARK: - 4. Density arithmetic at the Thronsen stride-3 step; nil pixel size → nil density

    func testArealDensityAtKnownPixelSizeAndRefusalWithout() throws {
        let px = 7.4829 // nm
        let result = classMap(pixelSize: px, pixelUnit: "nm")
        let one = try cls(1, in: result), two = try cls(2, in: result)

        let expected = 1.0 / (105.0 * px * px)   // one accepted object over the analysed area
        let d1 = try XCTUnwrap(one.density.arealDensity)
        let d2 = try XCTUnwrap(two.density.arealDensity)
        XCTAssertEqual(abs(d1 - expected) / expected, 0, accuracy: 1e-9, "class 1: A2 on the edge, so 1 counted")
        XCTAssertEqual(abs(d2 - expected) / expected, 0, accuracy: 1e-9, "class 2: B1 alone")
        XCTAssertEqual(one.density.pixelSize, px)
        XCTAssertEqual(one.density.pixelUnit, "nm")
        // Length/width summaries come through the existing type (edge object excluded).
        XCTAssertEqual(try XCTUnwrap(one.density.meanLength), 3, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(one.density.meanWidth), 2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(two.density.medianLength), 4, accuracy: 1e-6)

        let refused = classMap(pixelSize: nil, pixelUnit: nil)
        for c in refused.classes {
            XCTAssertNil(c.density.arealDensity, "class \(c.label): no pixel size, no density — never a number")
            XCTAssertNil(c.density.pixelSize)
        }
    }

    // MARK: - 5. A class with no objects is reported, count 0, density 0 when calibrated

    func testAbsentClassReportsZeroCountAndZeroDensityWhenCalibrated() throws {
        let result = classMap(classes: [1, 2, 3], pixelSize: 7.4829, pixelUnit: "nm")
        XCTAssertEqual(result.classes.map(\.label), [1, 2, 3], "an absent class is still a row")
        let three = try cls(3, in: result)
        XCTAssertTrue(three.objects.isEmpty)
        XCTAssertEqual(three.pixelCount, 0)
        XCTAssertEqual(three.density.acceptedCount, 0)
        XCTAssertEqual(three.density.edgeCount, 0)
        XCTAssertEqual(try XCTUnwrap(three.density.arealDensity), 0, "0 ÷ a known area is 0, not a refusal")
        XCTAssertEqual(try XCTUnwrap(three.areaFraction), 0)
        XCTAssertNil(three.density.meanLength)

        let uncalibrated = classMap(classes: [3])
        XCTAssertNil(try cls(3, in: uncalibrated).density.arealDensity, "and without a pixel size it is still a refusal")
    }
}
