//
//  PrecipitateSegmentationAnalyticTests.swift
//  An analytic harness for `PrecipitateSegmentation`'s class-map → objects
//  step (`classObjects`, `Object`, `ClassObjects`, `ClassMapObjects`,
//  `labelImage`). Every expected number is arithmetic derived by hand from
//  the code's own definitions — cited by file:line below — on small
//  synthetic label maps, not a re-run of the production formula.
//
//  This deliberately does not repeat what `PhaseMapObjectsTests.swift` and
//  `PhaseMapObjectsWiringTests.swift` already pin: the 12x9 fixture's
//  axis-aligned block geometry, the corner-touch-vs-gap connectivity
//  contrast, the edge/density bookkeeping on the right column, and the
//  absent-class / calibrated-vs-uncalibrated density rows. This file adds:
//  a straight needle's length definition read literally off the source, a
//  rotated (diagonal) needle showing length is measured along the true
//  principal axis rather than the axis-aligned bounding box, the full
//  four-sided touchesEdge rule (only the right column was exercised
//  before), corner-adjacent DIFFERENT classes staying separate, the
//  pixelSize <= 0 / non-finite refusal boundary, and two degenerate maps
//  (all-matrix, and a single interior pixel).
//
//  Length/width definition (`measure`, PrecipitateSegmentation.swift:387-438):
//  the principal axis comes from the pixel-index covariance (:408-418); for
//  `classObjects` the "footprint" passed in is the binary class mask itself
//  (:338, `values = mask.map { $0 ? 1 : 0 }`), so `peak` is always 1, `half`
//  is 0.5, and EVERY member pixel qualifies for the length/width projection
//  (:419-429) — there is no half-maximum shrinkage in the class-map path
//  (that only bites the intensity `segment()` path, per the `Object.area`
//  doc comment at :54-59). `length`/`width` are then the projected extent
//  along/across that axis, `+ 1` for the discrete pixel span (:430-431).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PrecipitateSegmentationAnalyticTests: XCTestCase {

    private let none: Int32 = -1

    private func roles(precipitate: Set<Int32>, matrix: Set<Int32> = [0]) -> PrecipitateSegmentation.LabelRoles {
        PrecipitateSegmentation.LabelRoles(precipitateClasses: precipitate, matrix: matrix, notIndexed: [none])
    }

    private func firstObject(
        _ label: Int32, in result: PrecipitateSegmentation.ClassMapObjects,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> PrecipitateSegmentation.Object {
        let cls = try XCTUnwrap(result.classes.first { $0.label == label }, file: file, line: line)
        return try XCTUnwrap(cls.objects.first, "class \(label) has no objects", file: file, line: line)
    }

    // MARK: - 1. Straight (axis-aligned) needle: count, area, length, width, orientation

    // 10 wide x 5 tall. Class 1 is a single horizontal run, row 2, cols 1...7
    // (7 px), clear of every border (row 0/4, col 0/9).
    func testStraightNeedleAreaLengthWidthOrientationAndLabelImage() throws {
        var labels = [Int32](repeating: 0, count: 10 * 5)
        for c in 1...7 { labels[2 * 10 + c] = 1 }

        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 10, height: 5, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        let object = try firstObject(1, in: result)

        // area: 7 contiguous pixels.
        XCTAssertEqual(object.area, 7)
        XCTAssertEqual(object.pixelIndices, (21...27).map { $0 }, "row-major indices, row 2 cols 1...7")
        // centroid: mean col = (1+...+7)/7 = 4, row fixed at 2.
        XCTAssertEqual(object.centroidX, 4, accuracy: 1e-6)
        XCTAssertEqual(object.centroidY, 2, accuracy: 1e-6)
        // A single row: cyy = cxy = 0, so the cxy==0 branch fires and,
        // since cxx > cyy, the axis is exactly +x (PrecipitateSegmentation.swift:504-505).
        XCTAssertEqual(object.orientationDegrees, 0, accuracy: 1e-6)
        // Every member has footprint value 1 (>= half = 0.5), so the u-extent
        // is the full column span: cols 1...7 -> uMax - uMin = 6, length = 7.
        XCTAssertEqual(object.lengthPx, 7, accuracy: 1e-6)
        // All members share one row, so v is 0 everywhere -> vMax == vMin,
        // and the ternary's "else 1" branch fires (:431): width = 1.
        XCTAssertEqual(object.widthPx, 1, accuracy: 1e-6)
        XCTAssertFalse(object.touchesEdge)

        // labelImage reconstructs exactly this object's footprint, id 1
        // (the only object), and 0 everywhere else.
        let allObjects = result.classes.flatMap(\.objects)
        let image = PrecipitateSegmentation.labelImage(objects: allObjects, width: 10, height: 5)
        for i in 0..<50 {
            let expected: Float = object.pixelIndices.contains(i) ? 1 : 0
            XCTAssertEqual(image.pixels[i], expected, "pixel \(i)")
        }
    }

    // MARK: - 4. Rotated needle: length along the true axis, not the bounding box

    // 8x8. Class 1 at the five pixels (row, col) = (k, k) for k = 1...5 — a
    // 45 degree diagonal, corner-adjacent step to step, clear of every
    // border (0 and 7). By hand: col == row for every member, so
    // cxx == cyy == cxy == s where s = Var(0...4) = (5^2 - 1)/12 = 2. The
    // cxy != 0 branch (:501-503) gives trace = 4, diff = 0, discriminant =
    // 4 * 2^2 = 16, root = 4, lambda1 = 4; vx = lambda1 - cyy = 2, vy = cxy
    // = 2 -> a 45 degree axis. Projecting each member's (dx, dy) = (d, d)
    // (d = -2...2) onto that axis gives u = d * sqrt(2), v = 0. So length =
    // (uMax - uMin) + 1 = 4 * sqrt(2) + 1 ~= 6.656854..., while the
    // axis-aligned bounding box is only 5 x 5 (cols/rows 1...5): the two
    // numbers are NOT the same, which is the point of this test.
    func testDiagonalNeedleLengthExceedsAxisAlignedBoundingBox() throws {
        var labels = [Int32](repeating: 0, count: 8 * 8)
        for k in 1...5 { labels[k * 8 + k] = 1 }

        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 8, height: 8, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        let object = try firstObject(1, in: result)

        XCTAssertEqual(object.area, 5, "the 5-step diagonal is one 8-connected object")
        XCTAssertEqual(object.orientationDegrees, 45, accuracy: 1e-4)

        let expectedLength = 4.0 * 2.0.squareRoot() + 1.0
        XCTAssertEqual(Double(object.lengthPx), expectedLength, accuracy: 1e-4,
                        "length runs along the 45 degree axis, not the pixel grid")
        XCTAssertEqual(object.widthPx, 1, accuracy: 1e-6, "a 1-pixel-wide diagonal line has no cross-axis extent")

        // The axis-aligned bounding box (rows/cols 1...5) is only 5 px on a
        // side — smaller than lengthPx, confirming length is NOT the bbox.
        let cols = object.pixelIndices.map { $0 % 8 }
        let rows = object.pixelIndices.map { $0 / 8 }
        let bboxWidth = (cols.max()! - cols.min()! + 1)
        let bboxHeight = (rows.max()! - rows.min()! + 1)
        XCTAssertEqual(bboxWidth, 5)
        XCTAssertEqual(bboxHeight, 5)
        XCTAssertGreaterThan(Double(object.lengthPx), Double(bboxWidth),
                              "the diagonal's true length exceeds its axis-aligned bounding box")
    }

    // MARK: - 2. Connectivity: an 8-connected bent (corner-only) chain is one object

    // 5x5. Class 1 at (1,1), (2,2), (3,1) — a "V": each consecutive pair
    // touches only at a corner (row differs by 1, col differs by 1), never
    // sharing an edge. Under 8-connectivity (PrecipitateSegmentation.swift
    // :453-454, `dy`/`dx` each ranging -1...1) all three merge into one
    // 3-pixel object. Restricting that loop to the four orthogonal
    // neighbours (a 4-connectivity mutation) would leave three singleton
    // objects instead — this is the mutation target for this test.
    func testBentCornerOnlyChainMergesUnderEightConnectivity() throws {
        var labels = [Int32](repeating: 0, count: 5 * 5)
        labels[1 * 5 + 1] = 1
        labels[2 * 5 + 2] = 1
        labels[3 * 5 + 1] = 1

        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 5, height: 5, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        XCTAssertEqual(result.connectivity, 8)
        let cls = try XCTUnwrap(result.classes.first { $0.label == 1 })
        XCTAssertEqual(cls.objects.count, 1, "all three corner-touching pixels are one object")
        XCTAssertEqual(cls.objects[0].area, 3)
        XCTAssertEqual(cls.objects[0].pixelIndices, [6, 12, 16], "row-major (width 5): (1,1)=6, (2,2)=12, (3,1)=16")

        // Edge-sharing control, in the same connectivity regime: two 1x2
        // dominoes placed edge-to-edge (row 0, cols 0-1 and cols 2-3) merge
        // into one 4-pixel object too — connectivity=8 is a superset of
        // edge-adjacency, not an alternative to it.
        var edgeLabels = [Int32](repeating: 0, count: 5 * 5)
        edgeLabels[0] = 1; edgeLabels[1] = 1; edgeLabels[2] = 1; edgeLabels[3] = 1
        let edgeResult = PrecipitateSegmentation.classObjects(
            labels: edgeLabels, width: 5, height: 5, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        let edgeCls = try XCTUnwrap(edgeResult.classes.first { $0.label == 1 })
        XCTAssertEqual(edgeCls.objects.count, 1)
        XCTAssertEqual(edgeCls.objects[0].area, 4)
    }

    // MARK: - 3. touchesEdge: all four sides, and an interior control

    // 6x6. One class-1 pixel on each border (top row, bottom row, left
    // column, right column) plus one interior pixel, spaced so no two are
    // within a Chebyshev distance of 1 (never 8-adjacent to each other):
    // (0,3), (5,2), (2,0), (3,5) — every pairwise row/col gap is >= 2.
    // Reads PrecipitateSegmentation.swift:401-403 literally: `row == 0 ||
    // row == height - 1 || col == 0 || col == width - 1`.
    func testTouchesEdgeFiresOnAllFourBordersNotOnlyOneColumn() throws {
        var labels = [Int32](repeating: 0, count: 6 * 6)
        labels[0 * 6 + 3] = 1   // top row (row 0)
        labels[5 * 6 + 2] = 1   // bottom row (row height-1 = 5)
        labels[2 * 6 + 0] = 1   // left column (col 0)
        labels[3 * 6 + 5] = 1   // right column (col width-1 = 5)

        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 6, height: 6, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        let cls = try XCTUnwrap(result.classes.first { $0.label == 1 })
        XCTAssertEqual(cls.objects.count, 4, "four isolated single-pixel objects")
        XCTAssertTrue(cls.objects.allSatisfy(\.touchesEdge), "every one of them sits on a border")

        // Interior control on a bigger map: one pixel strictly inside must
        // NOT be flagged.
        var interior = [Int32](repeating: 0, count: 5 * 5)
        interior[2 * 5 + 2] = 1
        let interiorResult = PrecipitateSegmentation.classObjects(
            labels: interior, width: 5, height: 5, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        let interiorObject = try firstObject(1, in: interiorResult)
        XCTAssertFalse(interiorObject.touchesEdge)

        // An edge object's pixels still count toward the class's pixelCount
        // / areaFraction (only the *density* accepted-count excludes it —
        // PrecipitateStatistics.swift:106-107) — the flag never deletes the
        // object or shrinks the class footprint.
        let classAll = try XCTUnwrap(result.classes.first { $0.label == 1 })
        XCTAssertEqual(classAll.pixelCount, 4)
        XCTAssertEqual(classAll.density.acceptedCount, 0, "all four accepted objects touch an edge")
        XCTAssertEqual(classAll.density.edgeCount, 4)
    }

    // MARK: - 6. Multiple classes never merge, even at a shared corner

    // 2x2. Class 1 at (0,0), class 2 at (1,1) — corner-adjacent, which WOULD
    // merge under 8-connectivity if they were the same class (as in the
    // bent-chain test above). Different classes are segmented on
    // independent masks (PrecipitateSegmentation.swift:337, `labels.map { $0
    // == label }`), so they must come back as two separate one-pixel
    // objects, each owning only its own pixel.
    func testCornerAdjacentDifferentClassesStaySeparate() throws {
        var labels = [Int32](repeating: 0, count: 2 * 2)
        labels[0] = 1
        labels[1 * 2 + 1] = 2

        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 2, height: 2, roles: roles(precipitate: [1, 2]),
            pixelSize: nil, pixelUnit: nil
        )
        let one = try firstObject(1, in: result)
        let two = try firstObject(2, in: result)
        XCTAssertEqual(one.pixelIndices, [0])
        XCTAssertEqual(two.pixelIndices, [3])
        XCTAssertEqual(one.area, 1)
        XCTAssertEqual(two.area, 1)
        XCTAssertEqual(try XCTUnwrap(result.classes.first { $0.label == 1 }).objects.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.classes.first { $0.label == 2 }).objects.count, 1)
    }

    // MARK: - 5. Density refusal boundary: pixelSize must be > 0 and finite

    // PrecipitateStatistics.swift:124: `if let pixelSize, pixelSize.isFinite,
    // pixelSize > 0, analysedPixels > 0`. Zero, negative, and non-finite
    // pixel sizes must all refuse exactly like nil; a genuinely positive one
    // must not.
    func testDensityRefusesForZeroNegativeAndNonFinitePixelSizeButNotForPositive() throws {
        var labels = [Int32](repeating: 0, count: 3 * 3)
        labels[1 * 3 + 1] = 1 // one interior precipitate pixel

        func density(_ pixelSize: Double?) throws -> PrecipitateStatistics.Density {
            let result = PrecipitateSegmentation.classObjects(
                labels: labels, width: 3, height: 3, roles: roles(precipitate: [1]),
                pixelSize: pixelSize, pixelUnit: pixelSize == nil ? nil : "nm"
            )
            return try XCTUnwrap(result.classes.first { $0.label == 1 }).density
        }

        XCTAssertNil(try density(nil).arealDensity)
        XCTAssertNil(try density(0).arealDensity, "zero pixel size is not a calibration")
        XCTAssertNil(try density(-2.5).arealDensity, "negative pixel size is not a calibration")
        XCTAssertNil(try density(.nan).arealDensity, "NaN pixel size is not a calibration")
        XCTAssertNil(try density(.infinity).arealDensity, "infinite pixel size is not a calibration")

        // Positive control: the refusal is specific to <= 0 / non-finite,
        // not a blanket nil.
        let px = 3.0
        let expected = 1.0 / (9.0 * px * px)
        XCTAssertEqual(try XCTUnwrap(try density(px).arealDensity), expected, accuracy: 1e-12)
    }

    // MARK: - 7a. Degenerate: an all-matrix map with a requested but absent precipitate class

    func testAllMatrixMapReportsRequestedClassEmptyNotMissing() throws {
        let labels = [Int32](repeating: 0, count: 3 * 3) // every position is matrix, label 0
        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 3, height: 3, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        XCTAssertEqual(result.matrixPixels, 9)
        XCTAssertEqual(result.notIndexedPixels, 0)
        XCTAssertEqual(result.otherPixels, 0)
        XCTAssertEqual(result.analysedPixels, 9)
        XCTAssertEqual(try XCTUnwrap(result.notIndexedFraction), 0)

        let cls = try XCTUnwrap(result.classes.first { $0.label == 1 })
        XCTAssertTrue(cls.objects.isEmpty)
        XCTAssertEqual(cls.pixelCount, 0)
        XCTAssertEqual(try XCTUnwrap(cls.areaFraction), 0)
        XCTAssertEqual(cls.density.acceptedCount, 0)
    }

    // MARK: - 7b. Degenerate: a single interior precipitate pixel

    // By hand: one member, so cxx = cyy = cxy = 0 (no deviation from its own
    // centroid). The cxy == 0 branch fires; cxx >= cyy (0 >= 0) so the axis
    // is +x, orientation 0. peak = 1, half = 0.5, the single member
    // qualifies, dx = dy = 0 -> u = v = 0 -> uMax == uMin and vMax == vMin,
    // so both ternaries (:430-431) take their "else" branch: length = width
    // = 1.
    func testSinglePixelPrecipitateIsAWellFormedDegenerateObject() throws {
        var labels = [Int32](repeating: 0, count: 5 * 5)
        labels[2 * 5 + 2] = 1
        let result = PrecipitateSegmentation.classObjects(
            labels: labels, width: 5, height: 5, roles: roles(precipitate: [1]),
            pixelSize: nil, pixelUnit: nil
        )
        let object = try firstObject(1, in: result)
        XCTAssertEqual(object.area, 1)
        XCTAssertEqual(object.pixelIndices, [12])
        XCTAssertEqual(object.centroidX, 2, accuracy: 1e-6)
        XCTAssertEqual(object.centroidY, 2, accuracy: 1e-6)
        XCTAssertEqual(object.orientationDegrees, 0, accuracy: 1e-6)
        XCTAssertEqual(object.lengthPx, 1, accuracy: 1e-6)
        XCTAssertEqual(object.widthPx, 1, accuracy: 1e-6)
        XCTAssertFalse(object.touchesEdge)
    }
}
