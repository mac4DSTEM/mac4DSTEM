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
    /// mac4DSTEM#338, the hand-off: the vectors Phase mapping and Find Matrix Zone Axis receive
    /// (`BraggVectors.calibrated(with:referenceOrigin:)` on these maps, about their mean, as `calibratedBraggVectors` does)
    /// are the planted lattice about the reference origin at every position, as a perfect centre-of-mass origin gives.
    func testPhaseMappingReceivesThePlantedLatticeWithTheBraggPeakOrigin() throws {
        let raw = Self.vectors()
        var calibration = Calibration()
        calibration.origin = try OriginCalibration.fromBraggPeaks(raw, qy: Self.qy, qx: Self.qx)
        let reference = try XCTUnwrap(calibration.meanOrigin)
        let calibrated = raw.calibrated(with: calibration, referenceOrigin: reference)
        for r in 0..<Self.rows {
            for c in 0..<Self.columns {
                let k = r * Self.columns + c, beam = Self.beam(r, c)
                XCTAssertEqual(calibrated.peaks[k].count, raw.peaks[k].count)
                for (got, planted) in zip(calibrated.peaks[k], raw.peaks[k]) {
                    XCTAssertEqual(got.x - reference.x, planted.x - beam.x, accuracy: 2e-3, "position (\(r), \(c))")
                    XCTAssertEqual(got.y - reference.y, planted.y - beam.y, accuracy: 2e-3, "position (\(r), \(c))")
                }
            }
        }
    }
}
