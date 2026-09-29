//
//  PrecipitateTests.swift
//  Fixture-based tests for the precipitate chain's classical algorithms
//  (ml/disk-detector:docs/ai-ml/precipitates.md): reflection finding and
//  density. The class-map object measurement is in
//  `PrecipitateSegmentationAnalyticTests`. Everything is synthetic and
//  deterministic — a seeded linear congruential generator drives the tiny
//  background noise on the reflections fixture, so a failure here reproduces
//  exactly. (The image-domain `PrecipitateSegmentation.segment` and its
//  fixtures were retired 2026-09-30: unwired, four open defects.)
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PrecipitateTests: XCTestCase {

    // MARK: - Deterministic PRNG (seeded LCG)

    private struct SeededLCG {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func nextUInt64() -> UInt64 {
            // Knuth's MMIX constants.
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func uniform01() -> Double {
            Double(nextUInt64() >> 11) * (1.0 / 9_007_199_254_740_992.0) // 2^53
        }
    }

    private static func distance(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
        let dx = ax - bx, dy = ay - by
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Density

    /// Mutation: compute `arealDensity` as `acceptedCount / analysedPixels`
    /// (forgetting the pixel-size-squared factor, or forgetting to guard on
    /// `pixelSize` at all) — this test's `nil` check catches the guard bug,
    /// and `testDensityComputesWithPixelSize`'s exact-value check catches
    /// the missing-square-factor bug.
    func testDensityRefusesWithoutPixelSize() {
        let objects = [
            PrecipitateSegmentation.Object(id: 1, pixelIndices: [0], area: 10, centroidX: 1, centroidY: 1, lengthPx: 10, widthPx: 3, orientationDegrees: 0, touchesEdge: false, meanIntensity: 100),
            PrecipitateSegmentation.Object(id: 2, pixelIndices: [1], area: 12, centroidX: 2, centroidY: 2, lengthPx: 12, widthPx: 4, orientationDegrees: 10, touchesEdge: false, meanIntensity: 100),
        ]
        let density = PrecipitateStatistics.density(
            objects: objects, accepted: Set([1, 2]), analysedPixels: 40_000,
            frameWidth: 200, frameHeight: 200, pixelSize: nil, pixelUnit: nil
        )
        XCTAssertNil(density.arealDensity)
        XCTAssertEqual(density.acceptedCount, 2)
        XCTAssertEqual(density.edgeCount, 0)
    }

    /// Mutation: count edge-touching objects toward `acceptedCount` (ignore
    /// `touchesEdge` entirely) — `acceptedCount` would come out 3 instead of
    /// 2, and `meanLength`/`medianLength` would be pulled toward object 3's
    /// 15 px instead of the correct (10+20)/2 = 15... (a coincidence here;
    /// swap object 3's length to something further from 15, e.g. 100, to see
    /// the mutation actually diverge — left as 15 only because it keeps this
    /// comment's example simple, the `acceptedCount`/`edgeCount` checks below
    /// already catch the mutation independent of that coincidence).
    func testDensityComputesWithPixelSize() {
        let objects = [
            PrecipitateSegmentation.Object(id: 1, pixelIndices: [0], area: 10, centroidX: 1, centroidY: 1, lengthPx: 10, widthPx: 3, orientationDegrees: 0, touchesEdge: false, meanIntensity: 100),
            PrecipitateSegmentation.Object(id: 2, pixelIndices: [1], area: 12, centroidX: 2, centroidY: 2, lengthPx: 20, widthPx: 4, orientationDegrees: 10, touchesEdge: false, meanIntensity: 100),
            PrecipitateSegmentation.Object(id: 3, pixelIndices: [2], area: 8, centroidX: 3, centroidY: 3, lengthPx: 999, widthPx: 5, orientationDegrees: 90, touchesEdge: true, meanIntensity: 100),
        ]
        let density = PrecipitateStatistics.density(
            objects: objects, accepted: Set([1, 2, 3]), analysedPixels: 1000,
            frameWidth: 40, frameHeight: 25, pixelSize: 0.01, pixelUnit: "nm"
        )
        XCTAssertEqual(density.acceptedCount, 2, "object 3 touches the edge and must not be counted")
        XCTAssertEqual(density.edgeCount, 1)
        // Two 1 × 1 boxes in a 40 × 25 frame, each weighted by the edge
        // correction 1000 / ((40 − 2)(25 − 2)) (Gate D 2026-09-28).
        let expected = 2.0 * (1000.0 / (38.0 * 23.0)) / (1000.0 * 0.01 * 0.01)
        XCTAssertNotNil(density.arealDensity)
        if let arealDensity = density.arealDensity {
            XCTAssertEqual(arealDensity, expected, accuracy: 1e-9)
        }
        XCTAssertEqual(density.meanLength ?? -1, 15.0, accuracy: 1e-6, "(10+20)/2, object 3 excluded")
        XCTAssertEqual(density.medianLength ?? -1, 15.0, accuracy: 1e-6)
    }

    /// Miles–Lantuéjoul edge correction (Gate D 2026-09-28,
    /// `archive/v4/areal-edge-correction-gateD-2026-09-28.md`): each counted
    /// object weighs W·H / ((W − bx − 1)(H − by − 1)) for its pixel bounding
    /// box, over the ANALYSED area. 10 × 10 frame, 80 analysed pixels.
    /// A: one pixel at (row 5, col 5) → 100/(8·8) = 1.5625.
    /// B: rows 4–5, cols 3–6 (4 × 2 box) → 100/(5·7) = 2.857142857…
    /// Density = (1.5625 + 2.857142857) / 80 = 0.05524553571.
    /// The lengths are deliberately NOT the boxes (99, 1). Mutations, each a
    /// different number: the old count (2/80 = 0.025); lengthPx for the box;
    /// analysedPixels for W·H; the border "− 1" dropped (100/81 + 100/48).
    func testDensityWeightsEachCountedObjectByItsBoundingBox() throws {
        let a = PrecipitateSegmentation.Object(id: 1, pixelIndices: [55], area: 1, centroidX: 5, centroidY: 5, lengthPx: 99, widthPx: 1, orientationDegrees: 0, touchesEdge: false, meanIntensity: 1)
        let b = PrecipitateSegmentation.Object(id: 2, pixelIndices: [43, 44, 45, 46, 53, 54, 55, 56], area: 8, centroidX: 4.5, centroidY: 4.5, lengthPx: 1, widthPx: 1, orientationDegrees: 0, touchesEdge: false, meanIntensity: 1)
        let density = PrecipitateStatistics.density(
            objects: [a, b], accepted: [1, 2], analysedPixels: 80,
            frameWidth: 10, frameHeight: 10, pixelSize: 1, pixelUnit: "nm")
        XCTAssertEqual(density.acceptedCount, 2, "the count stays an integer")
        XCTAssertEqual(try XCTUnwrap(density.arealDensity), (100.0 / 64 + 100.0 / 35) / 80, accuracy: 1e-12)
    }

    /// An edge object is still not counted and adds no weight. Mutation: the
    /// weights summed over every accepted object, edge ones included.
    func testEdgeObjectsAddNoWeight() throws {
        let inside = PrecipitateSegmentation.Object(id: 1, pixelIndices: [55], area: 1, centroidX: 5, centroidY: 5, lengthPx: 1, widthPx: 1, orientationDegrees: 0, touchesEdge: false, meanIntensity: 1)
        let edge = PrecipitateSegmentation.Object(id: 2, pixelIndices: [0, 1], area: 2, centroidX: 0.5, centroidY: 0, lengthPx: 2, widthPx: 1, orientationDegrees: 0, touchesEdge: true, meanIntensity: 1)
        let density = PrecipitateStatistics.density(
            objects: [inside, edge], accepted: [1, 2], analysedPixels: 100,
            frameWidth: 10, frameHeight: 10, pixelSize: 1, pixelUnit: "nm")
        XCTAssertEqual(density.edgeCount, 1)
        XCTAssertEqual(try XCTUnwrap(density.arealDensity), (100.0 / 64) / 100, accuracy: 1e-12)
    }

    // MARK: - Reflections

    /// 64x64 MAX pattern: a beam, 8 matrix spots on a square lattice
    /// (g1=(0,9), g2=(9,0) — the 8 nearest lattice points to the beam), and
    /// 4 half-order "precipitate" spots at the midpoints of the 4 axis
    /// neighbours. Mutations that would break this, one at a time:
    /// - search only h,k in {-1,0,1} instead of +/-12 — still passes here
    ///   (all matrix spots used are within that smaller range), a gap this
    ///   fixture does NOT close; a wider synthetic lattice would be needed
    ///   to catch a narrowed search bound.
    /// - compare against the nearest lattice point's *squared* distance but
    ///   the tolerance unsquared (units bug) — `latticeTolerance` 1.5 vs a
    ///   true nearest-distance-squared of up to ~2.25 for a genuine matrix
    ///   spot's floating-point residual would spuriously fail; here matrix
    ///   spots sit exactly on integer lattice points (residual 0) so this
    ///   particular mutation would NOT be caught by this fixture — a residual
    ///   ellipse-distorted lattice would be needed.
    /// - set `latticeTolerance` effectively to 0 (e.g. use `<` 0 instead of
    ///   `<=` tolerance) — matrix spots at exact integer positions still
    ///   pass (distance 0 < any positive tolerance), so this test does NOT
    ///   distinguish `<=` from `<` at the boundary; it only tests gross
    ///   on/off-lattice separation (distance 0 vs distance >= ~4).
    /// - swap the on/off-lattice boolean (`onMatrixLattice: !onLattice`) —
    ///   every matrix/extra assertion below inverts and fails.
    /// - drop the beam-exclusion guard — the beam's own peak would appear as
    ///   a 13th candidate, failing the `candidates.count` check.
    func testReflectionsSeparatesMatrixFromPrecipitate() {
        let width = 64, height = 64
        var pixels = [Float](repeating: 0, count: width * height)
        var rng = SeededLCG(seed: 0xABCDEF)
        for i in 0..<pixels.count {
            pixels[i] = Float(rng.uniform01()) * 0.001
        }

        let beamX = 31, beamY = 32
        func addBump(x: Int, y: Int, amplitude: Float) {
            for dy in -3...3 {
                for dx in -3...3 {
                    let row = y + dy, col = x + dx
                    guard row >= 0, row < height, col >= 0, col < width else { continue }
                    let r2 = Float(dx * dx + dy * dy)
                    pixels[row * width + col] += amplitude * exp(-r2 / 2)
                }
            }
        }

        addBump(x: beamX, y: beamY, amplitude: 1000)

        let matrixOffsets: [(dx: Int, dy: Int)] = [
            (0, 9), (0, -9), (9, 0), (-9, 0), (9, 9), (-9, 9), (9, -9), (-9, -9),
        ]
        for offset in matrixOffsets {
            addBump(x: beamX + offset.dx, y: beamY + offset.dy, amplitude: 100)
        }

        let extraOffsets: [(dx: Int, dy: Int)] = [(0, 5), (5, 0), (0, -5), (-5, 0)]
        for offset in extraOffsets {
            addBump(x: beamX + offset.dx, y: beamY + offset.dy, amplitude: 50)
        }

        let maxPattern = FloatImage(width: width, height: height, pixels: pixels)
        let candidates = PrecipitateReflections.find(
            maxPattern: maxPattern,
            beamCentre: (x: Float(beamX), y: Float(beamY)),
            matrixBasis: (g1: (x: 0, y: 9), g2: (x: 9, y: 0)),
            settings: .init()
        )

        XCTAssertEqual(candidates.count, matrixOffsets.count + extraOffsets.count)

        func nearestCandidate(col: Int, row: Int) -> PrecipitateReflections.Candidate? {
            candidates.min(by: {
                Self.distance(Float($0.col), Float($0.row), Float(col), Float(row)) <
                Self.distance(Float($1.col), Float($1.row), Float(col), Float(row))
            })
        }

        for offset in matrixOffsets {
            let col = beamX + offset.dx, row = beamY + offset.dy
            guard let match = nearestCandidate(col: col, row: row) else {
                XCTFail("no candidate near matrix spot (\(col),\(row))")
                continue
            }
            XCTAssertEqual(match.col, col)
            XCTAssertEqual(match.row, row)
            XCTAssertTrue(match.onMatrixLattice, "matrix spot (\(col),\(row)) should be on-lattice")
        }

        for offset in extraOffsets {
            let col = beamX + offset.dx, row = beamY + offset.dy
            guard let match = nearestCandidate(col: col, row: row) else {
                XCTFail("no candidate near extra spot (\(col),\(row))")
                continue
            }
            XCTAssertEqual(match.col, col)
            XCTAssertEqual(match.row, row)
            XCTAssertFalse(match.onMatrixLattice, "extra spot (\(col),\(row)) should be off-lattice")
        }
    }

    /// Mutation: use `>=` instead of `>` when testing against the exclusion
    /// radius squared (or drop the guard entirely) — a beam-only pattern
    /// would then still surface the beam's own peak as a candidate, and this
    /// test's `isEmpty` assertion fails.
    func testReflectionsExcludesTheBeamItself() {
        let width = 64, height = 64
        var pixels = [Float](repeating: 0, count: width * height)
        let beamX = 31, beamY = 32
        for dy in -2...2 {
            for dx in -2...2 {
                let row = beamY + dy, col = beamX + dx
                pixels[row * width + col] = 1000 * exp(-Float(dx * dx + dy * dy) / 2)
            }
        }
        let maxPattern = FloatImage(width: width, height: height, pixels: pixels)
        let candidates = PrecipitateReflections.find(
            maxPattern: maxPattern,
            beamCentre: (x: Float(beamX), y: Float(beamY)),
            matrixBasis: nil,
            settings: .init()
        )
        XCTAssertTrue(candidates.isEmpty, "the beam itself must never be reported as a candidate")
    }
}
