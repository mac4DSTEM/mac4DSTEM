import XCTest
import CuboCore
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The consumer side of the CuboKit 0.0.3 switch (C1 and C2, 2026-10-15, tier 1). The kit holds its own algorithms
/// against py4DSTEM; these tests hold what the APP does around them: which pixel is which (row and column), what an
/// empty selection answers, how a rectangle is clamped, the reference a centre of mass is taken against, the sign and
/// transpose of the rotation, and that the adapter serves the array's own pixels in order and stops when cancelled.
///
/// Every expectation is computed here, in Double, from the definition and the planted pixels, on a NON-SQUARE detector
/// (6 rows x 9 columns) and a non-square scan (5 rows x 4 columns) so that a swapped axis cannot cancel.
final class CuboSwitchTests: XCTestCase {

    private static let ry = 5, rx = 4, qy = 6, qx = 9

    /// A deterministic cube of half-integers (every Double sum below is exact), with two planted positions:
    /// scan (1, 2) carries a NEGATIVE pixel at detector (row 3, column 4), the way a dark-subtracted cube does, and
    /// scan (0, 0) is all zeros, the sum a centre of mass cannot divide by.
    private actor PlantedCube: FourDDataSource {
        static let descriptor = DatasetDescriptor(
            filePath: "/tmp/cubo-switch.h5", datasetPath: "/data",
            shape: [CuboSwitchTests.ry, CuboSwitchTests.rx, CuboSwitchTests.qy, CuboSwitchTests.qx],
            dtypeDescription: "float32", chunkShape: nil)
        let cube: [Float]
        init() {
            var all: [Float] = []
            for r in 0..<CuboSwitchTests.ry { for c in 0..<CuboSwitchTests.rx {
                for y in 0..<CuboSwitchTests.qy { for x in 0..<CuboSwitchTests.qx {
                    if r == 0 && c == 0 { all.append(0); continue }
                    var v = Float((r * 7 + c * 3 + y * 5 + x * 2 + (y * x) % 5) % 11) * 0.5
                    if r == 1 && c == 2 && y == 3 && x == 4 { v = -40 }
                    all.append(v)
                } }
            } }
            cube = all
        }
        func value(_ r: Int, _ c: Int, _ y: Int, _ x: Int) -> Double {
            Double(cube[((r * CuboSwitchTests.rx + c) * CuboSwitchTests.qy + y) * CuboSwitchTests.qx + x])
        }
        func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
        nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
        func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { view.pattern(fromFullCube: cube, ry: ry, rx: rx) }
        func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { view.scanRow(fromFullCube: cube, ry: ry) }
        func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
            view.scanTile(fromFullCube: cube, yRange: yRange)
        }
        func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
        func pixelCalibration() -> PixelCalibration? { nil }
    }

    private func planted() async throws -> (PlantedCube, FourDArray, DatasetDescriptor) {
        let source = PlantedCube()
        let d = try await source.discoverPrimaryDataset()
        return (source, FourDArray(reader: source, descriptor: d), d)
    }

    // MARK: - Selected-area diffraction (kit Metal path)

    /// The CBED of a real-space region is the SUM of its patterns, in Double from the planted pixels, held to relative
    /// 1e-5 (the kit's Metal tolerance). Forced one-row tiles, a rectangle that clips the scan, a circle with its partial rows.
    func testSelectedAreaDiffractionIsTheSumOfTheRegionsPatterns() async throws {
        let (source, data, d) = try await planted()
        let regions: [DetectorShape] = [
            .rectangle(xMin: 1, xMax: 4, yMin: 1, yMax: 4),
            .rectangle(xMin: -2, xMax: 2, yMin: 3, yMax: 9),
            .circle(centerX: 2, centerY: 2, radius: 1.5),
        ]
        for region in regions {
            let mask = VirtualDetector.makeMask(shape: region, qy: d.ry, qx: d.rx)
            var truth = [Double](repeating: 0, count: Self.qy * Self.qx)
            for r in 0..<Self.ry { for c in 0..<Self.rx where mask[r * Self.rx + c] != 0 {
                for y in 0..<Self.qy { for x in 0..<Self.qx { truth[y * Self.qx + x] += await source.value(r, c, y, x) } }
            } }
            for rows in [1, 2, nil] as [Int?] {
                let got = try await VirtualDetector.tiledDiffraction(data: data, descriptor: d, region: region, maximumTileRows: rows)
                XCTAssertEqual(got.pixels.count, truth.count)
                let scale = truth.map { abs($0) }.max() ?? 1
                for i in truth.indices {
                    XCTAssertEqual(Double(got.pixels[i]), truth[i], accuracy: 1e-5 * max(scale, 1), "\(region) rows \(String(describing: rows)) pixel \(i)")
                }
            }
        }
    }

    /// A region that selects no scan position gives the zero pattern, as the app's sum always did.
    func testSelectedAreaDiffractionOfAnEmptyRegionIsZero() async throws {
        let (_, data, d) = try await planted()
        let got = try await VirtualDetector.tiledDiffraction(data: data, descriptor: d, region: .rectangle(xMin: 50, xMax: 60, yMin: 50, yMax: 60))
        XCTAssertEqual(got.pixels, [Float](repeating: 0, count: Self.qy * Self.qx))
    }

    // MARK: - C1: virtual images

    /// The expected image of a mask predicate over detector (row y, column x): the Double sum, per scan position.
    private func expectedImage(_ source: PlantedCube, _ keep: (Int, Int) -> Bool) async -> [Float] {
        var out: [Float] = []
        for r in 0..<Self.ry { for c in 0..<Self.rx {
            var sum = 0.0
            for y in 0..<Self.qy { for x in 0..<Self.qx where keep(y, x) { sum += await source.value(r, c, y, x) } }
            out.append(Float(sum))
        } }
        return out
    }

    /// Mutation: swap the kit geometry's row and column (centerRow: cx) — every off-centre shape lands on the wrong
    /// pixels of a 6 x 9 detector. Mutation: drop the lower clamp of the rectangle — the kit refuses the negative bound
    /// and the call throws. Mutation: send the degenerate shapes to the kit instead of answering a zero image — it throws.
    func testVirtualImagesAreTheDefinitionOnANonSquareDetector() async throws {
        let (source, data, d) = try await planted()
        let cx: Float = 6.3, cy: Float = 1.7   // column, row: deliberately not the centre, and cx > cy
        let cases: [(String, DetectorShape, (Int, Int) -> Bool)] = [
            ("circle", .circle(centerX: cx, centerY: cy, radius: 3.2),
             { y, x in pow(Double(x) - Double(cx), 2) + pow(Double(y) - Double(cy), 2) < pow(Double(Float(3.2)), 2) }),
            ("annulus", .annulus(centerX: cx, centerY: cy, inner: 1.5, outer: 4.5),
             { y, x in
                 let r2 = pow(Double(x) - Double(cx), 2) + pow(Double(y) - Double(cy), 2)
                 return r2 > 1.5 * 1.5 && r2 < 4.5 * 4.5 }),
            // [xMin, xMax) x [yMin, yMax) half-open, clamped to the detector: columns 0..<5, rows 0..<4.
            ("rectangle clamped at 0", .rectangle(xMin: -4, xMax: 5, yMin: -2, yMax: 4), { y, x in x < 5 && y < 4 }),
            ("rectangle past the far edge", .rectangle(xMin: 6, xMax: 40, yMin: 4, yMax: 40), { y, x in x >= 6 && y >= 4 }),
            ("point", .point(x: 7, y: 2), { y, x in x == 7 && y == 2 }),
        ]
        for rows in [1, 3, 5] {
            for (name, shape, keep) in cases {
                let expected = await expectedImage(source, keep)
                XCTAssertTrue(expected.contains { $0 != 0 }, "\(name): an empty expectation proves nothing")
                let image = try await VirtualDetector.tiledImage(data: data, descriptor: d, shape: shape, maximumTileRows: rows)
                XCTAssertEqual(image.width, Self.rx); XCTAssertEqual(image.height, Self.ry)
                XCTAssertEqual(image.pixels, expected, "\(name), \(rows)-row tiles")
            }
        }
        // The dragged annulus is the same strict-inequality annulus, inner 0 included (the centre pixel is excluded).
        let aperture = Aperture(centerX: 4, centerY: 3, inner: 0, outer: 2.5)
        let run = try await VirtualDetector.tiledRun(data: data, descriptor: d, aperture: aperture, maximumTileRows: 2)
        let runExpected = await expectedImage(source) { y, x in
            let r2 = pow(Double(x) - 4, 2) + pow(Double(y) - 3, 2)
            return r2 > 0 && r2 < 2.5 * 2.5
        }
        XCTAssertEqual(run.pixels, runExpected)
        // The app answers a selection of nothing with a zero image and a completed progress, and never reaches the kit.
        let nothing: [DetectorShape] = [
            .point(x: 9, y: 0), .point(x: 0, y: 6), .point(x: -1, y: 0),
            .annulus(centerX: 4, centerY: 3, inner: 3, outer: 2), .annulus(centerX: 4, centerY: 3, inner: 2, outer: 2),
            .rectangle(xMin: -9, xMax: -1, yMin: 0, yMax: 3), .rectangle(xMin: 3, xMax: 3, yMin: 0, yMax: 3),
            .circle(centerX: 4, centerY: 3, radius: -2), .circle(centerX: .nan, centerY: 3, radius: 2),
        ]
        for shape in nothing {
            nonisolated(unsafe) var ticks: [Double] = []
            let image = try await VirtualDetector.tiledImage(data: data, descriptor: d, shape: shape,
                                                             progress: { ticks.append($0) })
            XCTAssertEqual(image.pixels, [Float](repeating: 0, count: Self.ry * Self.rx), "\(shape) selects nothing")
            XCTAssertEqual(ticks, [1], "\(shape): a finished run reports completion once")
        }
    }

    /// Mutation: take the mean over tiles as an unweighted average (the last tile is shorter) — wrong whenever the
    /// rows do not divide evenly. Mutation: the kit's max seeded at 0 — the planted negative pixel would read 0.
    func testMeanAndMaxPatternsAreTheDefinition() async throws {
        let (source, data, d) = try await planted()
        for rows in [nil, 2, 3] as [Int?] {
            let stats = try await VirtualDetector.tiledDPStatistics(data: data, descriptor: d, maximumTileRows: rows)
            XCTAssertEqual(stats.meanDP.count, Self.qy * Self.qx)
            for y in 0..<Self.qy { for x in 0..<Self.qx {
                var sum = 0.0, maximum = -Double.infinity
                for r in 0..<Self.ry { for c in 0..<Self.rx {
                    let v = await source.value(r, c, y, x); sum += v; maximum = max(maximum, v)
                } }
                XCTAssertEqual(stats.meanDP[y * Self.qx + x], Float(sum / Double(Self.ry * Self.rx)), accuracy: 1e-6,
                               "mean at row \(y), column \(x), tiles \(String(describing: rows))")
                XCTAssertEqual(stats.maxDP[y * Self.qx + x], Float(maximum), "max at row \(y), column \(x)")
            } }
        }
    }

    // MARK: - C2: centre of mass

    private func expectedCoM(_ source: PlantedCube, clamp: Bool) async -> [(x: Double, y: Double, sum: Double)] {
        var out: [(Double, Double, Double)] = []
        for r in 0..<Self.ry { for c in 0..<Self.rx {
            var s = 0.0, sx = 0.0, sy = 0.0
            for y in 0..<Self.qy { for x in 0..<Self.qx {
                var v = await source.value(r, c, y, x)
                if clamp { v = max(v, 0) }
                s += v; sx += v * Double(x); sy += v * Double(y)
            } }
            out.append((s == 0 ? .nan : sx / s, s == 0 ? .nan : sy / s, s))
        } }
        return out
    }

    /// The centre-of-mass SHIFT, interleaved [x (column), y (row)]: py4DSTEM's definition (a negative pixel counts), the
    /// reference subtracted, a zero sum answering 0. Mutation: swap the two output slots; skip the reference; clamp
    /// negatives (the Metal kernel's rule — the planted position then differs by far more than the tolerance).
    func testCentreOfMassShiftIsTheUnclampedDefinitionAgainstTheReference() async throws {
        let (source, data, d) = try await planted()
        let truth = await expectedCoM(source, clamp: false)
        let clamped = await expectedCoM(source, clamp: true)
        let planted = 1 * Self.rx + 2, zero = 0
        XCTAssertGreaterThan(abs(truth[planted].x - clamped[planted].x) + abs(truth[planted].y - clamped[planted].y), 0.05,
                             "the fixture must discriminate the clamp")
        XCTAssertTrue(truth[zero].x.isNaN, "scan (0, 0) is the zero-sum position")

        let centre: (x: Float, y: Float) = (3.25, 1.5)
        let origins: [Float] = (0..<(Self.ry * Self.rx)).flatMap { [Float(2) + Float($0 % 3) * 0.25, Float(1) + Float($0 % 4) * 0.5] }
        for rows in [1, 2, 5] {
            let shift = try await VirtualDetector.tiledCenterOfMass(data: data, descriptor: d, center: centre, maximumTileRows: rows)
            let shiftO = try await VirtualDetector.tiledCenterOfMass(data: data, descriptor: d, center: centre,
                                                                    origins: origins, maximumTileRows: rows)
            XCTAssertEqual(shift.count, Self.ry * Self.rx * 2)
            for i in 0..<(Self.ry * Self.rx) {
                let ex = i == zero ? 0 : truth[i].x - Double(centre.x), ey = i == zero ? 0 : truth[i].y - Double(centre.y)
                XCTAssertEqual(Double(shift[2 * i]), ex, accuracy: 1e-5, "x (column) at scan \(i), \(rows)-row tiles")
                XCTAssertEqual(Double(shift[2 * i + 1]), ey, accuracy: 1e-5, "y (row) at scan \(i)")
                let ox = i == zero ? 0 : truth[i].x - Double(origins[2 * i]), oy = i == zero ? 0 : truth[i].y - Double(origins[2 * i + 1])
                XCTAssertEqual(Double(shiftO[2 * i]), ox, accuracy: 1e-5, "x against the origin map at scan \(i)")
                XCTAssertEqual(Double(shiftO[2 * i + 1]), oy, accuracy: 1e-5, "y against the origin map at scan \(i)")
            }
        }
    }

    // MARK: - C2: rotation of the field

    /// `DPC.applyRotation` is x' = cos·a − sin·b, y' = sin·a + cos·b with (a, b) = (cx, cy), or (cy, cx) transposed — the
    /// app's own formula and angle — whatever the kit's convention is. Mutation: pass +θ to the kit (the sign
    /// convention is the negative); swap the two output slots; ignore the transpose.
    func testApplyRotationIsTheAppsFormulaOnANonSquareScan() {
        let width = 4, height = 5, n = width * height
        let com: [Float] = (0..<n).flatMap { i -> [Float] in
            let x = Double(i)
            let gx: Float = Float(sin(x * 0.9)) * 2 + 0.5
            let gy: Float = Float(cos(x * 0.4)) - 1.5
            return [gx, gy]
        }
        for transpose in [false, true] {
            for theta: Float in [0.7, -1.2, 0] {
                let out = DPC.applyRotation(com: com, width: width, height: height, rotationRad: theta, transpose: transpose)
                let c = Double(cos(theta)), s = Double(sin(theta))
                for i in 0..<n {
                    let a = Double(transpose ? com[2 * i + 1] : com[2 * i]), b = Double(transpose ? com[2 * i] : com[2 * i + 1])
                    XCTAssertEqual(Double(out[2 * i]), c * a - s * b, accuracy: 1e-5, "x' at \(i), θ \(theta), transpose \(transpose)")
                    XCTAssertEqual(Double(out[2 * i + 1]), s * a + c * b, accuracy: 1e-5, "y' at \(i)")
                }
            }
        }
        // A scan the kit will not rotate (under 3 x 3) is still rotated, by the same formula.
        let small: [Float] = [1, 2, 3, 4, -1, 0.5, 2, -3]
        let rotated = DPC.applyRotation(com: small, width: 2, height: 2, rotationRad: 0.5, transpose: true)
        XCTAssertEqual(Double(rotated[0]), cos(0.5) * 2 - sin(0.5) * 1, accuracy: 1e-5)
        XCTAssertEqual(Double(rotated[1]), sin(0.5) * 2 + cos(0.5) * 1, accuracy: 1e-5)
    }

    /// The curves come back indexed by the APP's angle list: the minimum of the winning curve sits at the angle the fit
    /// reports (to the refinement's ±1°), whichever way the kit's own sign runs. Mutation: hand the kit the app's angles
    /// un-negated — the kit's winner is then found at the right place for the wrong list, the reported angle stays
    /// right, and only this relation between `anglesDeg`, the curves and the angle breaks.
    func testTheRotationCurvesAreIndexedByTheAppsAngleList() throws {
        let width = 40, height = 40
        func potentialGradient(_ x: Double, _ y: Double) -> (Double, Double) {   // ∂φ/∂x, ∂φ/∂y of a sum of two smooth bumps
            func bump(_ cx: Double, _ cy: Double, _ s: Double, _ a: Double) -> (Double, Double) {
                let e = a * exp(-((x - cx) * (x - cx) + (y - cy) * (y - cy)) / (2 * s * s))
                return (-(x - cx) / (s * s) * e, -(y - cy) / (s * s) * e)
            }
            let p = bump(13, 11, 4.5, 1), q = bump(27, 29, 6, -0.8)
            return (p.0 + q.0, p.1 + q.1)
        }
        let planted = 0.5
        var com = [Float](repeating: 0, count: 2 * width * height)
        for y in 0..<height { for x in 0..<width {
            let g = potentialGradient(Double(x), Double(y))
            com[2 * (y * width + x)] = Float(cos(planted) * g.0 - sin(planted) * g.1)
            com[2 * (y * width + x) + 1] = Float(sin(planted) * g.0 + cos(planted) * g.1)
        } }
        let r = try XCTUnwrap(RotationCalibration.solve(com: com, width: width, height: height))
        XCTAssertEqual(r.anglesDeg.count, 180); XCTAssertEqual(r.anglesDeg.first, -89); XCTAssertEqual(r.anglesDeg.last, 90)
        XCTAssertEqual(r.objectiveCurve.count, 180); XCTAssertEqual(r.objectiveCurveTransposed.count, 180)
        let curve = r.transpose ? r.objectiveCurveTransposed : r.objectiveCurve
        let low = curve.indices.min { curve[$0] < curve[$1] }!
        let degrees = Double(r.rotationRad) * 180 / .pi
        XCTAssertEqual(Double(r.anglesDeg[low]), degrees, accuracy: 1.01,
                       "the winning curve's minimum (\(r.anglesDeg[low])°) must sit at the reported angle (\(degrees)°)")
        XCTAssertEqual(abs(degrees), planted * 180 / .pi, accuracy: 1.5, "the planted rotation is recovered in magnitude")
    }

    // MARK: - The adapter

    /// Mutation: serve a prefetched block without checking it is the block asked for (drop `pending.rows == rows`);
    /// the out-of-order read below then returns the wrong rows.
    func testTheAdapterServesTheArraysOwnPixelsInAnyReadOrder() async throws {
        let (_, data, d) = try await planted()
        let adapter = try CuboCubeSource(data, descriptor: d)
        let shape = adapter.shape
        XCTAssertEqual([shape.scanRows, shape.scanColumns, shape.detectorRows, shape.detectorColumns], [Self.ry, Self.rx, Self.qy, Self.qx])
        for rows in [0..<2, 2..<4, 4..<5, 1..<3, 0..<2, 3..<5] {   // sequential, then out of order
            let tile = try await adapter.readScanTile(rows: rows)
            let expected = try await data.scanTile(yRange: rows)
            XCTAssertEqual(tile.rows, rows)
            XCTAssertEqual(tile.values, expected.pixels, "rows \(rows)")
        }
        let pattern = try await adapter.readPattern(row: 3, column: 1)
        let expected = try await data.pattern(ry: 3, rx: 1)
        XCTAssertEqual(pattern.values, expected.pixels)
        XCTAssertEqual([pattern.detectorRows, pattern.detectorColumns], [Self.qy, Self.qx])
        do { _ = try await adapter.readPattern(row: 5, column: 0); XCTFail("a position off the scan must be refused") } catch {}
    }

    /// Mutation: drop the cancellation check — a cancelled operation keeps reading.
    func testACancelledOperationStopsAtItsNextRead() async throws {
        let (_, data, d) = try await planted()
        let token = AnalysisCancellationToken()
        let adapter = try CuboCubeSource(data, descriptor: d, cancellation: token)
        _ = try await adapter.readScanTile(rows: 0..<2)
        token.cancel()
        do { _ = try await adapter.readScanTile(rows: 2..<4); XCTFail("read after cancel") } catch is CancellationError {}
        do {
            _ = try await VirtualDetector.tiledImage(data: data, descriptor: d, shape: .point(x: 1, y: 1), cancellation: token)
            XCTFail("a cancelled image returned")
        } catch is CancellationError {}
    }
}
