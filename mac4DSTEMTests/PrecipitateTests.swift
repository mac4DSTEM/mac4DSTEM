//
//  PrecipitateTests.swift
//  Fixture-based tests for the precipitate chain's classical algorithms
//  (docs/ai-ml/precipitates.md): reflection finding, real-space
//  segmentation, and density. Everything is synthetic and deterministic —
//  a seeded linear congruential generator drives both the Box-Muller
//  Gaussian noise on the segmentation fixture and the tiny background noise
//  on the reflections fixture, so a failure here reproduces exactly.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class PrecipitateTests: XCTestCase {

    // MARK: - Deterministic PRNG (seeded LCG; Box-Muller for Gaussian noise)

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

        mutating func gaussian() -> Double {
            let u1 = Swift.max(uniform01(), 1e-12)
            let u2 = uniform01()
            return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
        }
    }

    private static func distance(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
        let dx = ax - bx, dy = ay - by
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func fold(_ angle: Float) -> Float {
        var a = angle
        while a <= -90 { a += 180 }
        while a > 90 { a -= 180 }
        return a
    }

    /// Smallest angle (degrees, 0...90) between two axis orientations (an
    /// axis and its 180-degree-rotated self are the same line).
    private static func angularDifference(_ a: Float, _ b: Float) -> Float {
        var d = abs(fold(a) - fold(b))
        if d > 90 { d = 180 - d }
        return d
    }

    // MARK: - Segmentation fixture geometry

    private struct NeedleSpec {
        let name: String
        let centerRow: Float
        let centerCol: Float
        let length: Float
        let width: Float
        let orientationDegrees: Float
        let expectsEdge: Bool
    }

    private struct ParticleSpec {
        let name: String
        let centerRow: Float
        let centerCol: Float
        let sigma: Float
    }

    // Four named orientations (37.2, 127.2, 0, 90) plus two others (60, -20),
    // per the fixture spec. Lengths are drawn from the top two-thirds of the
    // allowed 20-60 px band: the ridge filter's own smoothing (sigma 1.5)
    // shortens a rectangle's detected extent by a few px at each tip, which
    // partially cancels the 4*sqrt(eigenvalue) convention's own ~15% *over*-
    // estimate for a sharp-edged rectangle (that convention is exact for an
    // ellipse, not a rectangle) — the two effects roughly cancel across this
    // range but the cancellation has more headroom at larger L, hence the
    // choice to stay off the low end of the 20 px floor.
    private static let needleSpecs: [NeedleSpec] = [
        NeedleSpec(name: "A", centerRow: 45, centerCol: 45, length: 34, width: 3, orientationDegrees: 37.2, expectsEdge: false),
        NeedleSpec(name: "B", centerRow: 45, centerCol: 150, length: 42, width: 3, orientationDegrees: 127.2, expectsEdge: false),
        NeedleSpec(name: "C", centerRow: 150, centerCol: 45, length: 48, width: 3, orientationDegrees: 0, expectsEdge: false),
        NeedleSpec(name: "D", centerRow: 150, centerCol: 150, length: 54, width: 3, orientationDegrees: 90, expectsEdge: false),
        NeedleSpec(name: "E", centerRow: 1, centerCol: 95, length: 38, width: 3, orientationDegrees: 60, expectsEdge: true),
        NeedleSpec(name: "F", centerRow: 100, centerCol: 198, length: 46, width: 3, orientationDegrees: -20, expectsEdge: true),
    ]

    // Broad (sigma 10), round Gaussian blobs — deliberately wide relative to
    // the needle's width-3 cross-section. A round blob's Hessian eigenvalues
    // are governed by amplitude / sigma^2; making sigma large keeps the
    // particle's incidental curvature far below a needle's, since the
    // literal ridge measure (larger-magnitude negative eigenvalue) is not
    // itself elongation-selective — see the "could not honour" note in the
    // session report.
    private static let particleSpecs: [ParticleSpec] = [
        ParticleSpec(name: "P1", centerRow: 95, centerCol: 45, sigma: 10),
        ParticleSpec(name: "P2", centerRow: 55, centerCol: 100, sigma: 10),
        ParticleSpec(name: "P3", centerRow: 150, centerCol: 95, sigma: 10),
    ]

    private static let fixtureWidth = 200
    private static let fixtureHeight = 200

    private static func buildFixture() -> FloatImage {
        let width = fixtureWidth, height = fixtureHeight
        var pixels = [Float](repeating: 0, count: width * height)

        // Smooth gradient background (a linear ramp is exactly reproduced by
        // its own Gaussian blur, so background flattening removes it cleanly).
        for row in 0..<height {
            for col in 0..<width {
                pixels[row * width + col] = 50 + 0.02 * Float(row) + 0.01 * Float(col)
            }
        }

        // Seeded Gaussian noise.
        var rng = SeededLCG(seed: 0xC0FFEE_1234_5678)
        for i in 0..<pixels.count {
            pixels[i] += Float(rng.gaussian()) * 2.0
        }

        // Needles: filled rotated rectangles, sharp edges, orientation
        // convention identical to PrecipitateSegmentation.Object
        // (0 = +x/+col, counter-clockwise in row/col image coordinates).
        let needleAmplitude: Float = 200
        for spec in needleSpecs {
            let theta = spec.orientationDegrees * .pi / 180
            let cosT = cos(theta), sinT = sin(theta)
            let halfLength = spec.length / 2
            let halfWidth = spec.width / 2
            let reach = halfLength + halfWidth + 3
            let rowLo = Swift.max(0, Int((spec.centerRow - reach).rounded(.down)))
            let rowHi = Swift.min(height - 1, Int((spec.centerRow + reach).rounded(.up)))
            let colLo = Swift.max(0, Int((spec.centerCol - reach).rounded(.down)))
            let colHi = Swift.min(width - 1, Int((spec.centerCol + reach).rounded(.up)))
            guard rowLo <= rowHi, colLo <= colHi else { continue }
            for row in rowLo...rowHi {
                for col in colLo...colHi {
                    let dRow = Float(row) - spec.centerRow
                    let dCol = Float(col) - spec.centerCol
                    // Rotate into the needle's local (along-axis, cross-axis) frame.
                    let u = dCol * cosT + dRow * sinT
                    let v = -dCol * sinT + dRow * cosT
                    if abs(u) <= halfLength, abs(v) <= halfWidth {
                        pixels[row * width + col] += needleAmplitude
                    }
                }
            }
        }

        // Particles: round Gaussian blobs.
        let particleAmplitude: Float = 200
        for spec in particleSpecs {
            let reach = Int((4 * spec.sigma).rounded(.up))
            let rowLo = Swift.max(0, Int(spec.centerRow.rounded()) - reach)
            let rowHi = Swift.min(height - 1, Int(spec.centerRow.rounded()) + reach)
            let colLo = Swift.max(0, Int(spec.centerCol.rounded()) - reach)
            let colHi = Swift.min(width - 1, Int(spec.centerCol.rounded()) + reach)
            guard rowLo <= rowHi, colLo <= colHi else { continue }
            for row in rowLo...rowHi {
                for col in colLo...colHi {
                    let dRow = Float(row) - spec.centerRow
                    let dCol = Float(col) - spec.centerCol
                    let r2 = dRow * dRow + dCol * dCol
                    pixels[row * width + col] += particleAmplitude
                        * Float(exp(-Double(r2) / (2 * Double(spec.sigma * spec.sigma))))
                }
            }
        }

        return FloatImage(width: width, height: height, pixels: pixels)
    }

    private func nearest(_ objects: [PrecipitateSegmentation.Object], toRow row: Float, col: Float) -> PrecipitateSegmentation.Object? {
        objects.min(by: {
            Self.distance($0.centroidX, $0.centroidY, col, row) <
            Self.distance($1.centroidX, $1.centroidY, col, row)
        })
    }

    // MARK: - Needle segmentation

    /// Recall + measurement accuracy on every interior needle. Mutations that
    /// would break this, one at a time:
    /// - swap x/y in the centroid (`centroidX`/`centroidY` transposed) —
    ///   every needle not exactly on the row==col diagonal fails the
    ///   centroid check (all six are off-diagonal here).
    /// - drop the `4 *` factor in the length formula (report `sqrt(lambda1)`
    ///   alone) — every length assertion fails by a factor of ~4.
    /// - use `lambda2` (the smaller eigenvalue) for length instead of
    ///   `lambda1` — length comes out close to the width (~3 px) instead of
    ///   the drawn length, failing the 15% check on every needle.
    /// - flip the sign convention in `atan2(vy, vx)` to `atan2(vx, vy)` —
    ///   every orientation is off by (90 - true) instead of true, which is
    ///   only accidentally within 5 deg at 45 deg and fails elsewhere,
    ///   including needle A (37.2) and D (90).
    /// - fold orientation into (-90, 90] with `<` instead of `<=` at the
    ///   -90 boundary — invisible here (no fixture needle lands exactly at
    ///   -90) but would misclassify a needle drawn at exactly -90/90.
    private func needleSettings() -> PrecipitateSegmentation.Settings {
        var settings = PrecipitateSegmentation.Settings()
        settings.mode = .needles
        return settings
    }

    private func particleSettings() -> PrecipitateSegmentation.Settings {
        var settings = PrecipitateSegmentation.Settings()
        settings.mode = .particles
        return settings
    }

    func testNeedleModeFindsInteriorNeedlesWithinTolerance() {
        let image = Self.buildFixture()
        let objects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: needleSettings())

        for spec in Self.needleSpecs where !spec.expectsEdge {
            guard let match = nearest(objects, toRow: spec.centerRow, col: spec.centerCol) else {
                XCTFail("no object found for needle \(spec.name)")
                continue
            }

            let centroidError = Self.distance(match.centroidX, match.centroidY, spec.centerCol, spec.centerRow)
            XCTAssertLessThanOrEqual(centroidError, 1.5, "needle \(spec.name) centroid error \(centroidError)")

            let lengthError = abs(match.lengthPx - spec.length) / spec.length
            XCTAssertLessThanOrEqual(
                lengthError, 0.15,
                "needle \(spec.name) length \(match.lengthPx), expected ~\(spec.length)"
            )

            let orientationError = Self.angularDifference(match.orientationDegrees, spec.orientationDegrees)
            XCTAssertLessThanOrEqual(
                orientationError, 5,
                "needle \(spec.name) orientation \(match.orientationDegrees), expected ~\(Self.fold(spec.orientationDegrees))"
            )

            XCTAssertFalse(match.touchesEdge, "interior needle \(spec.name) incorrectly flagged touchesEdge")
        }
    }

    /// Mutation: drop the `touchesEdge` computation (always `false`) — this
    /// test fails on both E and F while the interior test above keeps passing,
    /// which is exactly the coverage gap a same-file omission would slip
    /// through if only interior needles were checked.
    func testNeedleModeFlagsEdgeNeedles() {
        let image = Self.buildFixture()
        let objects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: needleSettings())

        for spec in Self.needleSpecs where spec.expectsEdge {
            guard let match = nearest(objects, toRow: spec.centerRow, col: spec.centerCol) else {
                XCTFail("no object found for edge needle \(spec.name)")
                continue
            }
            XCTAssertTrue(match.touchesEdge, "edge needle \(spec.name) should be flagged touchesEdge")
        }
    }

    /// No needles-mode object should appear where nothing was drawn — the
    /// background gradient and noise alone must not fabricate an object.
    /// Radius 15 px allows for an edge needle's visible-pixel centroid
    /// shifting away from its nominal (partly off-canvas) center, and for
    /// mild interference between the crude (non-elongation-selective) ridge
    /// measure and a nearby particle (see the type's doc comment and the
    /// session report). Mutation: skip the `robustThreshold` computation and
    /// threshold at raw zero — noise alone then seeds hundreds of one-pixel
    /// "objects" scattered across the image, most farther than 15 px from
    /// every drawn center, and this test catches it where the recall tests
    /// above would not (they only look near the known centers).
    func testNeedleModeHasNoObjectWhereNothingWasDrawn() {
        let image = Self.buildFixture()
        let objects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: needleSettings())

        let drawnCenters: [(row: Float, col: Float)] =
            Self.needleSpecs.map { (row: $0.centerRow, col: $0.centerCol) } +
            Self.particleSpecs.map { (row: $0.centerRow, col: $0.centerCol) }

        for object in objects {
            let nearestDistance = drawnCenters
                .map { Self.distance(object.centroidX, object.centroidY, $0.col, $0.row) }
                .min() ?? .infinity
            XCTAssertLessThanOrEqual(
                nearestDistance, 15,
                "object at (\(object.centroidX), \(object.centroidY)) does not correspond to anything drawn"
            )
        }
    }

    // MARK: - Particle segmentation

    /// Mutation: use the ridge measure (needle path) unconditionally,
    /// ignoring `settings.mode` — the round, wide-sigma particles produce a
    /// far weaker ridge response than a needle by design (see
    /// `particleSpecs`'s comment), so this test would then find zero or
    /// badly-mislocated objects near the particle centers.
    func testParticleModeFindsTheThreeBlobs() {
        let image = Self.buildFixture()
        let objects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: particleSettings())

        for spec in Self.particleSpecs {
            guard let match = nearest(objects, toRow: spec.centerRow, col: spec.centerCol) else {
                XCTFail("no object found for particle \(spec.name)")
                continue
            }
            let centroidError = Self.distance(match.centroidX, match.centroidY, spec.centerCol, spec.centerRow)
            XCTAssertLessThanOrEqual(centroidError, 3, "particle \(spec.name) centroid error \(centroidError)")
            XCTAssertGreaterThanOrEqual(match.area, 20, "particle \(spec.name) area implausibly small: \(match.area)")
        }
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
            pixelSize: nil, pixelUnit: nil
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
            pixelSize: 0.01, pixelUnit: "nm"
        )
        XCTAssertEqual(density.acceptedCount, 2, "object 3 touches the edge and must not be counted")
        XCTAssertEqual(density.edgeCount, 1)
        let expected = 2.0 / (1000.0 * 0.01 * 0.01)
        XCTAssertNotNil(density.arealDensity)
        if let arealDensity = density.arealDensity {
            XCTAssertEqual(arealDensity, expected, accuracy: 1e-9)
        }
        XCTAssertEqual(density.meanLength ?? -1, 15.0, accuracy: 1e-6, "(10+20)/2, object 3 excluded")
        XCTAssertEqual(density.medianLength ?? -1, 15.0, accuracy: 1e-6)
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
