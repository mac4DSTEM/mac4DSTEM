import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// mac4DSTEM#138: the origin from the Bragg peaks when a reflection is brighter than the direct beam (the Si/SiGe case),
/// where the brightest peak is the reflection and the centre of mass sits between the two. Planted peaks: a direct beam
/// on a small descan plane, a square lattice of reflections about it, the (1, 0) reflection three times as bright.
final class BraggPeakOriginTests: XCTestCase {
    private static let qy = 96, qx = 96, rows = 6, columns = 9

    private static func beam(_ r: Int, _ c: Int) -> (x: Float, y: Float) {
        (x: 47 + 0.10 * Float(c) - 0.05 * Float(r), y: 45 + 0.08 * Float(r) + 0.04 * Float(c))
    }

    private static func vectors(emptyAt empty: Int? = nil) -> BraggVectors {
        var peaks: [[BraggPeak]] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let k = r * columns + c
                guard k != empty else { peaks.append([]); continue }
                let o = beam(r, c)
                var list: [BraggPeak] = []
                for i in -2...2 {
                    for j in -2...2 {
                        let x = o.x + 14 * Float(i) + 1.5 * Float(j), y = o.y - 1.5 * Float(i) + 14 * Float(j)
                        let intensity: Float = (i, j) == (0, 0) ? 100 : (i, j) == (1, 0) ? 300 : 40 / Float(abs(i) + abs(j))
                        list.append(BraggPeak(x: x, y: y, intensity: intensity))
                    }
                }
                peaks.append(list.reversed())   // the beam neither first nor brightest
            }
        }
        return BraggVectors(scanWidth: columns, scanHeight: rows, peaks: peaks)
    }

    func testOriginFollowsTheDirectBeamUnderABrighterReflection() throws {
        let maps = try OriginCalibration.fromBraggPeaks(Self.vectors(), qy: Self.qy, qx: Self.qx, fitFunction: .plane)
        XCTAssertEqual(maps.width, Self.columns)
        XCTAssertEqual(maps.height, Self.rows)
        for r in 0..<Self.rows {
            for c in 0..<Self.columns {
                let k = r * Self.columns + c, want = Self.beam(r, c)
                XCTAssertEqual(maps.measuredX?[k] ?? .nan, want.x, accuracy: 1e-4)
                XCTAssertEqual(maps.measuredY?[k] ?? .nan, want.y, accuracy: 1e-4)
                XCTAssertEqual(maps.fittedX[k], want.x, accuracy: 1e-3)   // the beam walks a plane exactly
                XCTAssertEqual(maps.fittedY[k], want.y, accuracy: 1e-3)
            }
        }
        XCTAssertLessThan(maps.rmsResidual ?? .infinity, 1e-3)
        XCTAssertEqual(maps.measuredByFriedel, false)
    }

    func testAPositionWithoutPeaksStaysOutOfTheFit() throws {
        let maps = try OriginCalibration.fromBraggPeaks(Self.vectors(emptyAt: 20), qy: Self.qy, qx: Self.qx)
        let want = Self.beam(20 / Self.columns, 20 % Self.columns)
        XCTAssertEqual(maps.fittedX[20], want.x, accuracy: 1e-3)
        XCTAssertEqual(maps.fittedY[20], want.y, accuracy: 1e-3)
    }

    func testNoPeaksIsRefusedWithASentence() {
        let empty = BraggVectors(scanWidth: 2, scanHeight: 1, peaks: [[], []])
        XCTAssertThrowsError(try OriginCalibration.fromBraggPeaks(empty, qy: 32, qx: 32)) { error in
            XCTAssertEqual(error as? BraggPeakOriginError, .noPeaks)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }
    // MARK: mac4DSTEM#338: a patch without a detected direct beam

    /// A 12 × 16 scan of the same lattice in which a contiguous 3 × 4 patch (6 % of the positions, a precipitate's worth) has
    /// no direct beam among its peaks, so the distance score takes the nearest reflection there, 14 px off.
    private static let patchRows = 12, patchColumns = 16
    private static func inPatch(_ r: Int, _ c: Int) -> Bool { (2..<5).contains(r) && (10..<14).contains(c) }
    private static let lattice: [(i: Int, j: Int)] = (-2...2).flatMap { i in (-2...2).map { j in (i: i, j: j) } }
    private static func offset(_ i: Int, _ j: Int) -> (x: Float, y: Float) {
        (x: 14 * Float(i) + 1.5 * Float(j), y: -1.5 * Float(i) + 14 * Float(j))
    }

    private static func vectorsWithABeamlessPatch() -> BraggVectors {
        var peaks: [[BraggPeak]] = []
        for r in 0..<patchRows {
            for c in 0..<patchColumns {
                let o = beam(r, c)
                peaks.append(lattice.compactMap { n -> BraggPeak? in
                    let isBeam = n.i == 0 && n.j == 0
                    if isBeam, inPatch(r, c) { return nil }
                    let d = offset(n.i, n.j)
                    return BraggPeak(x: o.x + d.x, y: o.y + d.y, intensity: isBeam ? 100 : 40 / Float(abs(n.i) + abs(n.j)))
                })
            }
        }
        return BraggVectors(scanWidth: patchColumns, scanHeight: patchRows, peaks: peaks)
    }

    /// The fitted origin follows the beam everywhere, the patch included, and the fit left the patch out. An ordinary
    /// least-squares plane (the route before #338) is 3.1 px off at the patch and tilted under every other position.
    /// Mutation: the plain `BraggOrigin.fit` back in `fromBraggPeaks` -> red.
    func testAPatchWithoutTheDirectBeamDoesNotTiltTheOrigin() throws {
        let maps = try OriginCalibration.fromBraggPeaks(Self.vectorsWithABeamlessPatch(), qy: Self.qy, qx: Self.qx)
        let validity = try XCTUnwrap(maps.originValidity)
        for r in 0..<Self.patchRows {
            for c in 0..<Self.patchColumns {
                let k = r * Self.patchColumns + c, want = Self.beam(r, c)
                XCTAssertEqual(maps.fittedX[k], want.x, accuracy: 1e-3, "position (\(r), \(c))")
                XCTAssertEqual(maps.fittedY[k], want.y, accuracy: 1e-3, "position (\(r), \(c))")
                if Self.inPatch(r, c) { XCTAssertFalse(validity[k], "position (\(r), \(c)) was fitted") }
            }
        }
        // The patch is left out; the trim may also drop a rounding-level tail of the planted positions, never many.
        let excluded = try XCTUnwrap(maps.excludedFraction)
        XCTAssertGreaterThanOrEqual(excluded, 12 / 192 - 1e-6)
        XCTAssertLessThan(excluded, 0.1)
    }

    /// The hand-off to phase mapping: the vectors `calibratedBraggVectors` gives Phase mapping and Find Matrix Zone Axis
    /// (`BraggVectors.calibrated(with:referenceOrigin:)` on the origin maps, about their mean) are the planted lattice about
    /// the reference origin at every position, the same vectors a perfect centre-of-mass origin gives. Mutation: the plain
    /// least-squares fit -> the patch's lattice sits 3 px off -> red.
    func testPhaseMappingReceivesThePlantedLatticeWithTheBraggPeakOrigin() throws {
        let raw = Self.vectorsWithABeamlessPatch()
        var calibration = Calibration()
        calibration.origin = try OriginCalibration.fromBraggPeaks(raw, qy: Self.qy, qx: Self.qx)
        let reference = try XCTUnwrap(calibration.meanOrigin)
        let calibrated = raw.calibrated(with: calibration, referenceOrigin: reference)
        for r in 0..<Self.patchRows {
            for c in 0..<Self.patchColumns {
                let k = r * Self.patchColumns + c
                let want = Self.lattice.filter { !($0.i == 0 && $0.j == 0 && Self.inPatch(r, c)) }.map { Self.offset($0.i, $0.j) }
                let got = calibrated.peaks[k].map { (x: $0.x - reference.x, y: $0.y - reference.y) }
                XCTAssertEqual(got.count, want.count)
                for (g, w) in zip(got, want) {
                    XCTAssertEqual(g.x, w.x, accuracy: 2e-3, "position (\(r), \(c))")
                    XCTAssertEqual(g.y, w.y, accuracy: 2e-3, "position (\(r), \(c))")
                }
            }
        }
    }
}
