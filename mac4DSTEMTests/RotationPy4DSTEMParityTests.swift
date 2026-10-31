import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Calibration numbers against py4DSTEM f050d207 (0.14.19). The fields and patterns in `Fixtures/Calibration/` were
/// written by the scripts beside them; the public Al-Mg-Si demo is `AlMgSi_demo.h5` (100 x 100 x 128 x 128, uint16).
///
/// The R-Q rotation: py4DSTEM's curl objective (`_solve_for_center_of_mass_relative_rotation`), transcribed in float64.
/// The app's 0.1 degree refinement chooses between angles whose objectives can differ by less than Float32 resolves.
/// It once scored them in Float and kept the first of two Float-equal values; py4DSTEM keeps the float64 minimum.
final class RotationPy4DSTEMParityTests: XCTestCase {

    private func floats(_ name: String, count: Int) throws -> [Float] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Calibration/\(name)")
        let data = try Data(contentsOf: url)
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(values.count, count)
        return values
    }

    /// `float-tie-40x40.f32` (`rotation_float_tie.py`): a planted gradient field with noise, the planted angle chosen
    /// so the two best fine angles, 41.1 and 41.2 degrees in py4DSTEM's sign, differ by 7.3e-9 (7.6e-8 relative) and
    /// read equal in Float32. py4DSTEM's float64 minimum is 41.1 on its own 0.1 degree grid; the Float rule kept 41.2.
    func testRefinementPicksTheFloat64MinimumBelowFloat32Resolution() throws {
        let com = try floats("float-tie-40x40.f32", count: 40 * 40 * 2)
        let result = try XCTUnwrap(RotationCalibration.solve(com: com, width: 40, height: 40))
        XCTAssertFalse(result.transpose)
        let shown = RQRotationConvention.displayDegrees(fromApp: result.rotationRad)
        XCTAssertEqual(shown, 41.1, accuracy: 0.01, "py4DSTEM float64 picks 41.1; the old Float refinement 41.2")
    }

    /// The demo's full-pattern centre of mass less the origin plane py4DSTEM fits to `get_origin`
    /// (`almgsi_demo_reference.py`). py4DSTEM gives 68.0 degrees on its default 1 degree grid (DPC.preprocess, float32),
    /// 68.1 on a 0.1 degree grid and in float64, transpose false. The demo plants no rotation: the curl curve is 1.3 %
    /// deep over the half circle, so the angle is the minimum of a nearly flat curve. py4DSTEM reports it anyway; the
    /// app matches the angle and its null refuses to write it.
    func testAlMgSiDemoAngleMatchesPy4DSTEMAndIsRefused() throws {
        let com = try floats("almgsi-demo-com-100x100.f32", count: 100 * 100 * 2)
        let result = try XCTUnwrap(RotationCalibration.solve(com: com, width: 100, height: 100))
        XCTAssertFalse(result.transpose)
        let shown = RQRotationConvention.displayDegrees(fromApp: result.rotationRad)
        XCTAssertEqual(shown, 68.1, accuracy: 0.01)
        XCTAssertFalse(result.carriesRotation, "depth \(result.depth), surrogates \(result.shuffledDepths)")
    }

    /// The probe size: the calibration's radius is py4DSTEM's `DataCube.get_probe_size`, whose default pattern is
    /// `dp_mean`; the origin window's radius is `get_origin`'s, on `dp_max`. On the demo (`almgsi_demo_patterns.py`):
    /// mean 2.984912471263921 px at (63.50003243, 63.50002732), max 2.9437920812107796 px. Tolerance 1e-6 px: the kit
    /// is a float64 port and the patterns are the float64 ones rounded to Float32 (py4DSTEM on the rounded mean moves
    /// the centre by 7e-9 px and the radius not at all).
    func testDemoProbeSizeOnTheMeanAndMaxPatternsMatchesPy4DSTEM() throws {
        let mean = try floats("almgsi-demo-mean-128x128.f32", count: 128 * 128)
        let maxDP = try floats("almgsi-demo-max-128x128.f32", count: 128 * 128)
        let m = try XCTUnwrap(OriginCalibration.probeSize(dp: mean, qy: 128, qx: 128))
        XCTAssertEqual(Double(m.r), 2.984912471263921, accuracy: 1e-6)
        // The centre is too symmetric to pin the axis order (the two differ by 5e-6 px); NoisyOriginTests pins it.
        XCTAssertEqual(Double(m.x0), 63.50002732, accuracy: 1e-5)
        XCTAssertEqual(Double(m.y0), 63.50003243, accuracy: 1e-5)
        let x = try XCTUnwrap(OriginCalibration.probeSize(dp: maxDP, qy: 128, qx: 128))
        XCTAssertEqual(Double(x.r), 2.9437920812107796, accuracy: 1e-6)
    }
}
