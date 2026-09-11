//
//  PrecipitateTests.swift
//  Fixture-based tests for the precipitate chain's classical algorithms
//  (ml/disk-detector:docs/ai-ml/precipitates.md): reflection finding, real-space
//  segmentation, and density. Everything is synthetic and deterministic —
//  a seeded linear congruential generator drives both the Box-Muller
//  Gaussian noise on the segmentation fixture and the tiny background noise
//  on the reflections fixture, so a failure here reproduces exactly.
//

import XCTest
import DSTEMCore
import DSTEMSession
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
        // convention identical to PrecipitateSegmentation.Object: 0 = +x/+col
        // and the angle increases from +x toward +y (increasing row), which is
        // CLOCKWISE on screen because the row axis points down.
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
    /// - measure the extents on the filter response (`filtered`) instead of
    ///   the flattened image — the ridge response spreads past each tip, so
    ///   every length reads long.
    /// - drop the half-maximum test (`flattened[i] >= half`) and take the
    ///   extents over every member pixel — length grows to the full mask,
    ///   which runs ~2x the drawn bar.
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

    // MARK: - Noise-free needle: the extents and the mask footprint (Gate B, M8/M11)

    /// A single sharp-edged bar on an empty field, so the truth is exact and
    /// the 15 %/5-degree tolerances of the noisy fixture above are not doing
    /// the work. `widthPx` and `area` had NO assertion anywhere before this
    /// test, which is why mutations M8 (measure the extents on the ridge
    /// RESPONSE instead of the flattened image — the thing the code comment
    /// forbids) and M11 (a one-third-maximum footprint instead of the
    /// half-maximum one) both survived the 2026-09-06 Gate B run.
    ///
    /// The numbers pinned here are the MEASURED ones, and two of them are
    /// not the drawn ones — see `docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md`:
    ///   * `widthPx` reads ~4 for a drawn 3 because the extents are
    ///     centre-to-centre spans plus 1, and that +1 is exact only when the
    ///     object's axis is axis-aligned. The assertion below proves that is
    ///     the cause by measuring the DRAWN bar's own pixel-centre span.
    ///   * `area` is the thresholded mask footprint, ~2x the drawn bar.
    /// Both are open questions recorded for the owner, not silently blessed.
    func testNoiseFreeNeedleMeasuresItsDrawnExtents() throws {
        let width = 120, height = 120
        let drawnLength: Float = 34, drawnWidth: Float = 3
        let drawnAngle: Float = 37.2      // neither axis-aligned nor 45 deg: sign-discriminating
        let centre: Float = 60
        let theta = drawnAngle * .pi / 180
        let cosT = cos(theta), sinT = sin(theta)

        var pixels = [Float](repeating: 0, count: width * height)
        var drawnCount = 0
        var acrossMin = Float.greatestFiniteMagnitude, acrossMax = -Float.greatestFiniteMagnitude
        for row in 0..<height {
            for col in 0..<width {
                let dCol = Float(col) - centre, dRow = Float(row) - centre
                let along = dCol * cosT + dRow * sinT
                let across = -dCol * sinT + dRow * cosT
                guard abs(along) <= drawnLength / 2, abs(across) <= drawnWidth / 2 else { continue }
                pixels[row * width + col] = 200
                drawnCount += 1
                acrossMin = Swift.min(acrossMin, across); acrossMax = Swift.max(acrossMax, across)
            }
        }
        let drawnCentreSpan = acrossMax - acrossMin

        let objects = PrecipitateSegmentation.segment(
            image: FloatImage(width: width, height: height, pixels: pixels),
            validity: nil, settings: needleSettings()
        )
        XCTAssertEqual(objects.count, 1, "one bar on an empty field must segment as one object")
        let needle = try XCTUnwrap(objects.first)

        XCTAssertEqual(needle.centroidX, centre, accuracy: 1, "centroid x \(needle.centroidX)")
        XCTAssertEqual(needle.centroidY, centre, accuracy: 1, "centroid y \(needle.centroidY)")
        XCTAssertEqual(
            needle.orientationDegrees, drawnAngle, accuracy: 2,
            "orientation \(needle.orientationDegrees), drawn \(drawnAngle)"
        )
        XCTAssertEqual(
            needle.lengthPx, drawnLength, accuracy: 1.5,
            "length \(needle.lengthPx), drawn \(drawnLength)"
        )

        // The +1 convention, demonstrated rather than asserted from memory:
        // the measured width is the DRAWN bar's own pixel-centre span across
        // the axis, plus 1. On this diagonal that span is already ~3.0, so
        // the measurement reads ~4.0 for a bar drawn 3.0 wide.
        XCTAssertEqual(
            needle.widthPx, drawnCentreSpan + 1, accuracy: 0.35,
            "width \(needle.widthPx) is not the drawn bar's pixel-centre span "
            + "(\(drawnCentreSpan)) plus the end-to-end +1 — the cause established in "
            + "docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md §width no longer explains it"
        )
        // OPEN QUESTION (docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md §width): recorded, not endorsed.
        XCTAssertGreaterThan(
            needle.widthPx, drawnWidth,
            "width \(needle.widthPx) against a drawn \(drawnWidth) — read "
            + "docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md §width before changing this"
        )
        XCTAssertLessThan(needle.widthPx, drawnWidth + 1.2, "width \(needle.widthPx)")

        // `area` is the mask footprint, not the drawn area (see Object.area).
        // No ratio is pinned here: on a perfectly empty field the robust
        // threshold degenerates (median 0, MAD 0, so it collapses to "any
        // positive ridge response") and the mask runs ~47x the drawn bar — an
        // artefact of the fixture, recorded in docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md §threshold.
        // The realistic ratio is pinned by
        // `testNeedleMaskFootprintExceedsTheDrawnBar`.
        XCTAssertEqual(needle.area, needle.pixelIndices.count, "area must be the object's own pixel count")
        XCTAssertGreaterThan(
            needle.area, drawnCount,
            "the detection mask is never smaller than the bar that produced it"
        )
    }

    /// The extents are defined as the HALF-maximum footprint of the flattened
    /// image (`PrecipitateSegmentation.segment`'s own comment). The
    /// sharp-edged bar above cannot test that definition: it has no pixel
    /// between one third and one half of its peak, so a third-maximum
    /// footprint measures exactly the same pixels (mutation M11 survives it —
    /// measured 2026-09-06). This fixture gives the bar a GAUSSIAN
    /// cross-section whose full width at half maximum is 3 px, which puts
    /// pixels at every level and separates the two definitions:
    ///
    ///   half-maximum footprint  -> widthPx 3.72   (this assertion)
    ///   third-maximum footprint -> widthPx 4.43   (the M11 mutation run)
    ///
    /// The measured 3.72 sits ~0.26 below the drawn image's own half-maximum
    /// footprint plus 1 (2.975 + 1 = 3.975) because background flattening
    /// lowers the profile before the half-maximum is taken.
    func testNeedleWidthFollowsTheHalfMaximumFootprint() throws {
        let width = 120, height = 120
        let drawnLength: Float = 34, drawnFWHM: Float = 3
        let drawnAngle: Float = 37.2
        let centre: Float = 60
        let sigma = drawnFWHM / (2 * (2 * Float(log(2.0))).squareRoot())
        let theta = drawnAngle * .pi / 180
        let cosT = cos(theta), sinT = sin(theta)

        var pixels = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for col in 0..<width {
                let dCol = Float(col) - centre, dRow = Float(row) - centre
                let along = dCol * cosT + dRow * sinT
                let across = -dCol * sinT + dRow * cosT
                guard abs(along) <= drawnLength / 2, abs(across) <= 4 * sigma else { continue }
                pixels[row * width + col] = 200 * exp(-across * across / (2 * sigma * sigma))
            }
        }

        let objects = PrecipitateSegmentation.segment(
            image: FloatImage(width: width, height: height, pixels: pixels),
            validity: nil, settings: needleSettings()
        )
        XCTAssertEqual(objects.count, 1)
        let needle = try XCTUnwrap(objects.first)

        XCTAssertEqual(
            needle.widthPx, 3.72, accuracy: 0.3,
            "width \(needle.widthPx): a third-maximum footprint reads 4.43 on this "
            + "fixture and a half-maximum one reads 3.72 — see the doc comment"
        )
        XCTAssertEqual(
            needle.lengthPx, 34.18, accuracy: 1.5,
            "length \(needle.lengthPx)"
        )
        XCTAssertEqual(needle.orientationDegrees, drawnAngle, accuracy: 2)
    }

    /// `Object.area` had NO assertion anywhere. It is the thresholded mask's
    /// pixel count, and on the realistic (noisy, background-bearing) fixture
    /// it runs well above the drawn bar because the ridge response spreads
    /// past the object's edges. This pins the band so the number cannot drift
    /// unnoticed, and names the open question rather than blessing it —
    /// `docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md` §area, and `Object.area`'s doc comment.
    func testNeedleMaskFootprintExceedsTheDrawnBar() {
        let image = Self.buildFixture()
        let objects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: needleSettings())

        for spec in Self.needleSpecs where !spec.expectsEdge {
            guard let match = nearest(objects, toRow: spec.centerRow, col: spec.centerCol) else {
                XCTFail("no object found for needle \(spec.name)")
                continue
            }
            XCTAssertEqual(match.area, match.pixelIndices.count, "needle \(spec.name): area must be its own pixel count")
            let drawn = Self.rasterisedPixelCount(spec)
            let ratio = Float(match.area) / Float(drawn)
            XCTAssertGreaterThan(
                ratio, 1.3,
                "needle \(spec.name): mask \(match.area) px vs drawn \(drawn) px, ratio \(ratio) "
                + "— OPEN QUESTION (docs/archive/v3/precipitate-gateD-2026-09-06/gateD-C3.md §area): `area` is the mask footprint, "
                + "not the object's drawn area"
            )
            XCTAssertLessThan(
                ratio, 2.9,
                "needle \(spec.name): mask/drawn ratio \(ratio) has drifted above the band "
                + "measured on 2026-09-06 (1.59-2.37)"
            )
        }
    }

    /// The number of fixture pixels `buildFixture` actually paints for `spec`
    /// — the rasterised count, not the nominal `length * width`.
    private static func rasterisedPixelCount(_ spec: NeedleSpec) -> Int {
        let theta = spec.orientationDegrees * .pi / 180
        let cosT = cos(theta), sinT = sin(theta)
        var count = 0
        for row in 0..<fixtureHeight {
            for col in 0..<fixtureWidth {
                let dRow = Float(row) - spec.centerRow, dCol = Float(col) - spec.centerCol
                let u = dCol * cosT + dRow * sinT
                let v = -dCol * sinT + dRow * cosT
                if abs(u) <= spec.length / 2, abs(v) <= spec.width / 2 { count += 1 }
            }
        }
        return count
    }

    // MARK: - touchesEdge agrees with the object's own pixels (Gate B, M9)

    /// `touchesEdge` decides which objects the density count excludes
    /// (`PrecipitateStatistics`), so an off-by-one in its rule silently moves
    /// a published number. Mutation M9 — `row == 1 || row == height - 2 ||
    /// col == 1 || col == width - 2` — survived the 2026-09-06 Gate B run,
    /// because every object in the noisy fixture that reaches row 1 also
    /// reaches row 0, so the two rules agree there.
    ///
    /// This fixture separates them by construction: `validity` withholds row
    /// 0 under the right-hand blob only, so that object's topmost pixel is
    /// row 1 and the true rule says "interior" while an off-by-one says
    /// "edge". The left-hand blob keeps row 0 and must be flagged. The test
    /// asserts BOTH the property (every object's flag matches its own pixel
    /// list) and the preconditions that make the fixture discriminating, so
    /// it cannot silently stop testing anything.
    func testTouchesEdgeMatchesTheObjectsOwnPixels() throws {
        let width = 80, height = 80
        var pixels = [Float](repeating: 0, count: width * height)
        func addBlob(row: Float, col: Float, sigma: Float, amplitude: Float) {
            for r in 0..<height {
                for c in 0..<width {
                    let dr = Float(r) - row, dc = Float(c) - col
                    pixels[r * width + c] += amplitude
                        * Float(exp(-Double(dr * dr + dc * dc) / (2 * Double(sigma * sigma))))
                }
            }
        }
        addBlob(row: 2, col: 20, sigma: 2.5, amplitude: 300)   // keeps row 0
        addBlob(row: 2, col: 60, sigma: 2.5, amplitude: 300)   // row 0 withheld below

        var validity = [Bool](repeating: true, count: width * height)
        for c in 40..<width { validity[c] = false }            // row 0, right half only

        let objects = PrecipitateSegmentation.segment(
            image: FloatImage(width: width, height: height, pixels: pixels),
            validity: validity, settings: particleSettings()
        )
        XCTAssertEqual(objects.count, 2, "the fixture draws exactly two separated blobs")

        for object in objects {
            let touches = object.pixelIndices.contains {
                $0 / width == 0 || $0 / width == height - 1
                    || $0 % width == 0 || $0 % width == width - 1
            }
            XCTAssertEqual(
                object.touchesEdge, touches,
                "object #\(object.id) at (\(object.centroidY), \(object.centroidX)): "
                + "touchesEdge is \(object.touchesEdge) but its own pixel list says \(touches)"
            )
        }

        let atRowZero = try XCTUnwrap(nearest(objects, toRow: 2, col: 20))
        let atRowOne = try XCTUnwrap(nearest(objects, toRow: 2, col: 60))
        XCTAssertTrue(
            atRowZero.pixelIndices.contains { $0 / width == 0 },
            "fixture precondition: the left blob must own a row-0 pixel"
        )
        XCTAssertTrue(atRowZero.touchesEdge)
        XCTAssertFalse(
            atRowOne.pixelIndices.contains { $0 / width == 0 },
            "fixture precondition: `validity` must have kept row 0 out of the right blob"
        )
        XCTAssertTrue(
            atRowOne.pixelIndices.contains { $0 / width == 1 },
            "fixture precondition: the right blob must REACH row 1 — otherwise this "
            + "test cannot discriminate a row==1 off-by-one"
        )
        XCTAssertFalse(
            atRowOne.touchesEdge,
            "an object whose topmost pixel is row 1 is interior, not an edge object"
        )
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

    // MARK: - Non-finite input (Gate D, 2026-09-11)

    /// A scan-domain scalar product may legitimately carry `Float.nan`: main
    /// writes it at invalid scan positions (`Core/Analysis/StrainMapping.swift`
    /// :77,:81 and `StrainFrame.swift`:113), which is why `DisplayedProduct`
    /// derives `validityMask` from `.isFinite` at all. Two things broke on such
    /// an image before the guard, and this fixture pins both:
    ///   1. `gaussianBlur` spreads one NaN across its whole 3-sigma support.
    ///   2. `robustThreshold` sorts, and Float comparison with NaN is not a
    ///      strict weak ordering, so median and MAD are undefined.
    /// Measured before the fix: six needles with no NaN gave 6 objects; a
    /// SINGLE NaN pixel gave 1 object ~8x too long. A plausible wrong answer,
    /// not a refusal — which is why this is a fixture and not a comment.
    ///
    /// Mutations that must break this: remove the imputation loop (count
    /// collapses to 1); impute with 0 instead of the finite median (the hole
    /// becomes a dark disc the background blur sees, and the needles nearest
    /// it change length); drop `valid[i] = false` (the imputed pixels become
    /// eligible to join an object).
    func testNonFiniteInputLeavesEveryFiniteObjectWhereItWas() {
        let settings = nanFixtureSettings()
        let base = PrecipitateSegmentation.segment(
            image: nanFixture(nanCount: 0), validity: nil, settings: settings
        )
        XCTAssertEqual(base.count, 6, "the fixture draws six needles")

        // Swept over the SENTINEL, not the dose. Gate B measured that doses 1,
        // 3 and 10 give the same six objects with areas differing by at most
        // one pixel, so the dose axis could not fail. The sentinel axis can:
        // `.isFinite` is the predicate the guard uses, and narrowing it to
        // `.isNaN` — which looks like a tidy-up — leaves the infinity arms
        // unguarded. That mutation is invisible to a NaN-only fixture.
        for sentinel in [Float.nan, .infinity, -.infinity] {
            let objects = PrecipitateSegmentation.segment(
                image: nanFixture(nanCount: 10, sentinel: sentinel), validity: nil,
                settings: settings
            )
            XCTAssertEqual(
                objects.count, base.count,
                "sentinel \(sentinel) in the background changed the object count"
            )
            // Matched by position, never by index: objects come back sorted by
            // area, and the sub-pixel perturbation below can flip two of them.
            for expected in base {
                let match = objects.min {
                    hypot($0.centroidX - expected.centroidX, $0.centroidY - expected.centroidY)
                        < hypot($1.centroidX - expected.centroidX, $1.centroidY - expected.centroidY)
                }
                guard let match else { return XCTFail("no object near \(expected.centroidX)") }
                XCTAssertEqual(match.centroidX, expected.centroidX, accuracy: 0.1,
                               "sentinel \(sentinel) moved a centroid")
                XCTAssertEqual(match.centroidY, expected.centroidY, accuracy: 0.1)
                XCTAssertEqual(match.lengthPx, expected.lengthPx, accuracy: 0.05,
                               "sentinel \(sentinel) moved a measured length")
                XCTAssertEqual(match.orientationDegrees, expected.orientationDegrees, accuracy: 1.0)
            }
        }
    }

    /// Why the tolerances above are not zero, established 2026-09-11 by
    /// measurement rather than assumed: `robustThreshold` takes its median and
    /// MAD over the WHOLE image, so replacing a single pixel's value shifts the
    /// global threshold by a hair, and a pixel sitting exactly on that boundary
    /// can flip anywhere in the frame. Observed on this fixture: the needle at
    /// (20.06, 20.14) reads area 191 with no NaN present and 192 with one
    /// imputed pixel 44 px away, which also reorders the area-sorted result.
    /// That is a property of imputing at all, not of imputing the median, and
    /// it is sub-pixel: centroids move <= 0.04 px and lengths <= 0.01 px.
    /// The claim this file makes is that the object SET is stable, never that
    /// the arithmetic is bit-identical. The strictly-identical case is the one
    /// that matters for regression and it is covered above: with no non-finite
    /// pixel the guard does not fire at all.

    /// The imputed pixels must never join an object.
    ///
    /// The fixture is deliberately not the flat one above: with a flat
    /// background the imputed median flattens to ~0 and falls below the
    /// threshold anyway, so the assertion holds whether or not the code clears
    /// `valid[i]` — it was vacuous, and deleting the line it tests did not
    /// break it (measured 2026-09-11). Here the NaN sits inside a DARK patch
    /// while the global median is the bright background, so imputing drops a
    /// bright spot into a dark region: the one case where an imputed pixel can
    /// pass the threshold. Deleting `valid[i] = false` fails this test.
    func testNonFinitePixelsNeverJoinAnObject() {
        let nanCount = 8
        let objects = PrecipitateSegmentation.segment(
            image: darkPatchFixture(nanCount: nanCount), validity: nil,
            settings: nanFixtureSettings()
        )
        let imputed = Set((0..<nanCount).map { 104 * 128 + 100 + $0 })
        for object in objects {
            XCTAssertTrue(
                imputed.isDisjoint(with: Set(object.pixelIndices)),
                "an imputed non-finite pixel joined an object"
            )
        }
    }

    /// An image that is entirely non-finite has no finite median to impute
    /// from. It must return cleanly, not trap and not invent objects.
    ///
    /// No value-mutation breaks this — an all-constant image has zero MAD, so
    /// nothing clears the threshold either way. What it does catch is a trap:
    /// writing the fill as `finite.last!` instead of `medianOf(finite)` crashes
    /// here (measured 2026-09-11). It is a crash guard, and that is the whole
    /// of its claim.
    func testAllNonFiniteImageReturnsNoObjects() {
        let all = FloatImage(width: 32, height: 32,
                             pixels: [Float](repeating: .nan, count: 32 * 32))
        XCTAssertTrue(
            PrecipitateSegmentation.segment(
                image: all, validity: nil, settings: nanFixtureSettings()
            ).isEmpty
        )
    }

    // MARK: - The pre-registered baseline (step 4, 2026-09-11)

    /// `ml/disk-detector:docs/ai-ml/precipitates.md` §6 pre-registered a
    /// baseline — "threshold + connected components without the ridge filter" —
    /// that the ridge filter "must beat ... or it does not ship". It was never
    /// written. It needs no new engine code: `.particles` mode IS that baseline
    /// (background flatten, Gaussian smooth, threshold, connected components),
    /// and `.needles` is the same pipeline with `ridgeMeasure` inserted.
    ///
    /// The owner's criterion (`docs/decisions.md`, 2026-09-11, second round):
    /// recall and precision decide, and a TIE PASSES.
    ///
    /// The fixture's truth is six drawn needles. It also draws three round
    /// particles, which a needle counter must REJECT — so recall is where the
    /// arms tie and precision is where they can separate.
    ///
    /// This test pins only what the fixture can decide. The real-data half of
    /// the pre-registration — the Al-Si-Mg hand count — does not exist, so the
    /// ship gate as a whole is UNMET and precipitates are not wired. The full
    /// measured table is committed at
    /// `docs/archive/v3/precipitate-baseline-2026-09-11.md`.
    func testRidgeFilterVersusThePreRegisteredBaseline() {
        let image = Self.buildFixture()
        var ridge = PrecipitateSegmentation.Settings(); ridge.mode = .needles
        var baseline = PrecipitateSegmentation.Settings(); baseline.mode = .particles
        let ridgeObjects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: ridge)
        let baselineObjects = PrecipitateSegmentation.segment(image: image, validity: nil, settings: baseline)

        /// Nearest-object match. The tolerance is 15 px, not 6, because E and F
        /// are drawn deliberately clipped by the frame edge (centreRow 1 and
        /// centreCol 198), so their detected centroids sit 10-13 px inside the
        /// drawn centre. A 6 px window scores them MISSED and reports a false
        /// 4/6 recall for both arms — measured 2026-09-11, and it was this
        /// test's own first bug, not the engine's.
        func needlesFound(_ objects: [PrecipitateSegmentation.Object]) -> Int {
            var used = Set<Int>(), found = 0
            for spec in Self.needleSpecs {
                var best: (Int, Float)?
                for (k, o) in objects.enumerated() where !used.contains(k) {
                    let d = hypot(o.centroidX - spec.centerCol, o.centroidY - spec.centerRow)
                    if best == nil || d < best!.1 { best = (k, d) }
                }
                if let best, best.1 < 15 { used.insert(best.0); found += 1 }
            }
            return found
        }
        let rNeedles = needlesFound(ridgeObjects), bNeedles = needlesFound(baselineObjects)

        // Recall: both arms must find every drawn needle.
        XCTAssertEqual(rNeedles, Self.needleSpecs.count, "the ridge filter lost a drawn needle")
        XCTAssertEqual(bNeedles, Self.needleSpecs.count, "the baseline lost a drawn needle")

        // Precision: the fixture also draws three ROUND particles that a needle
        // counter should reject. Measured 2026-09-11: BOTH arms report all
        // three, so precision ties at 6/9 and the ridge filter demonstrates no
        // elongation selectivity on this fixture. That is a tie, and the
        // owner's criterion passes a tie (docs/decisions.md, 2026-09-11) — but
        // it means the fixture cannot show the ridge filter earning its place.
        // Pinned so that a change which makes either arm WORSE goes red.
        XCTAssertEqual(ridgeObjects.count, 9, "ridge arm object count moved")
        XCTAssertEqual(baselineObjects.count, 9, "baseline arm object count moved")
        XCTAssertLessThanOrEqual(
            ridgeObjects.count - rNeedles, baselineObjects.count - bNeedles,
            "the ridge filter reported more non-needle objects than the plain-threshold "
            + "baseline — it loses the half of its own pre-registered gate this fixture can score"
        )
    }

    // MARK: - Non-square scan (Gate B, 2026-09-11)

    /// Every other segmentation fixture in this file is SQUARE — 200x200,
    /// 120x120, 80x80, 64x64, 32x32, 128x128 — so the engine's scan-index
    /// arithmetic (`let row = i / width, col = i % width`, three sites in
    /// `segment()`) is unconstrained: transposing it to `i / height, i % height`
    /// changes nothing any of them can see. Gate B applied that transposition
    /// and measured it turning three correctly located bars into ZERO objects
    /// on a 160x100 image while the whole suite stayed green.
    ///
    /// Rectangular scan grids are ordinary, and `segment()` documents its input
    /// as any scan-domain scalar image, so this is a real class of bug the
    /// suite could not see. One non-square fixture closes it.
    func testNonSquareScanLocatesObjectsAtTheirDrawnPositions() {
        let w = 160, h = 100
        var pixels = [Float](repeating: 0, count: w * h)
        var seed: UInt64 = 11
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 10000) / 10000
        }
        for i in 0..<pixels.count { pixels[i] = 100 + 2 * (rnd() - 0.5) }
        // Deliberately off-diagonal and at distinct x and y: a transposition
        // must move them somewhere the assertions notice.
        let drawn = [(40, 30), (75, 50), (110, 60)]
        for (cx, cy) in drawn {
            for t in -13...13 {
                let x = cx + Int((Float(t) * 0.866).rounded())
                let y = cy + Int((Float(t) * 0.5).rounded())
                if x >= 0, x < w, y >= 0, y < h { pixels[y * w + x] += 200 }
            }
        }
        var settings = PrecipitateSegmentation.Settings()
        settings.mode = .needles
        let objects = PrecipitateSegmentation.segment(
            image: FloatImage(width: w, height: h, pixels: pixels),
            validity: nil, settings: settings
        )
        XCTAssertEqual(objects.count, drawn.count,
                       "three bars were drawn on a 160x100 scan")
        for (cx, cy) in drawn {
            let near = objects.contains {
                abs($0.centroidX - Float(cx)) < 2 && abs($0.centroidY - Float(cy)) < 2
            }
            XCTAssertTrue(near, "no object within 2 px of the bar drawn at (\(cx), \(cy))")
        }
    }

    /// Bright background, a dark patch, and `nanCount` NaN pixels inside it.
    private func darkPatchFixture(nanCount: Int) -> FloatImage {
        let w = 128, h = 128
        var pixels = [Float](repeating: 0, count: w * h)
        var seed: UInt64 = 7
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 10000) / 10000
        }
        for i in 0..<pixels.count { pixels[i] = 100 + 2 * (rnd() - 0.5) }
        for y in 90..<120 { for x in 90..<120 { pixels[y * w + x] = 20 + 2 * (rnd() - 0.5) } }
        for k in 0..<nanCount { pixels[104 * w + 100 + k] = .nan }
        return FloatImage(width: w, height: h, pixels: pixels)
    }

    private func nanFixtureSettings() -> PrecipitateSegmentation.Settings {
        var settings = PrecipitateSegmentation.Settings()
        settings.mode = .needles
        return settings
    }

    /// Flat background plus noise, six needles, and `nanCount` NaN pixels
    /// placed in the flat background well away from every needle.
    private func nanFixture(nanCount: Int, sentinel: Float = .nan) -> FloatImage {
        let w = 128, h = 128
        var pixels = [Float](repeating: 0, count: w * h)
        var seed: UInt64 = 42
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 10000) / 10000
        }
        for i in 0..<pixels.count { pixels[i] = 100 + 2 * (rnd() - 0.5) }
        for n in 0..<6 {
            let cx = 20 + (n % 3) * 40, cy = 20 + (n / 3) * 60
            for t in -10...10 {
                let x = cx + Int((Float(t) * 0.866).rounded())
                let y = cy + Int((Float(t) * 0.5).rounded())
                if x >= 0, x < w, y >= 0, y < h { pixels[y * w + x] += 200 }
            }
        }
        for k in 0..<nanCount { pixels[64 * w + 10 + k] = sentinel }
        return FloatImage(width: w, height: h, pixels: pixels)
    }
}

