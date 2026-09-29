import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// D021 — the parallax whole-stack mean summed in Float32 and froze at 2^24.
/// D079 — parallax/ptychography took the aperture centre as the diffraction
/// origin instead of `Calibration.referenceOrigin`.
/// (Gate D pre-registrations: session scratchpad `a/d021-prereg.md`,
/// `a/d079-prereg.md`.)
final class ParallaxStackMeanTests: XCTestCase {

    /// The refuting observation, kept as a test: 17 M ones. A Float32 running
    /// sum stops at 16 777 216, so the old mean read 16777216 / 17000000 =
    /// 0.98689. Double accumulation reads exactly 1.
    func testMeanOfOnesPastTheFloatStallIsOne() {
        let stack = [Float](repeating: 1, count: 17_000_000)
        XCTAssertEqual(stack.reduce(0, +), 16_777_216,
                       "the premise: a Float32 sum of 17 M ones stalls at 2^24")
        XCTAssertEqual(ParallaxPreprocessor.stackMean(stack), 1, accuracy: 1e-7)
    }

    /// Below the stall the helper is the mean, to Float rounding.
    func testMeanOfASmallStackMatchesTheDoubleReference() {
        var state: UInt64 = 0x9E3779B97F4A7C15
        var stack = [Float](repeating: 0, count: 46_080)
        var reference = 0.0
        for index in stack.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Float(0.6 + 0.8 * Double(state >> 40) / Double(1 << 24))
            stack[index] = value
            reference += Double(value)
        }
        reference /= Double(stack.count)
        XCTAssertEqual(ParallaxPreprocessor.stackMean(stack), Float(reference))
    }
}

@MainActor
final class ParallaxDiffractionOriginTests: XCTestCase {

    private func maps(x: Float, y: Float) -> OriginMaps {
        let count = 4
        return OriginMaps(
            width: 2, height: 2,
            measuredX: [Float](repeating: x, count: count),
            measuredY: [Float](repeating: y, count: count),
            fittedX: [Float](repeating: x, count: count),
            fittedY: [Float](repeating: y, count: count))
    }

    private func calibrated(_ calibration: inout Calibration) {
        calibration.rotationRad = 0.1
        calibration.rPixelSize = 0.2
        calibration.rPixelUnits = "nm"
        calibration.qPixelSize = 0.5
        calibration.qPixelUnits = "1/nm"
    }

    private func resolved(_ calibration: Calibration, aperture: Aperture) throws -> ParallaxPhysicalCalibration {
        try ParallaxPhysicalCalibration.resolve(
            calibration: calibration, apertureCenterX: aperture.centerX,
            apertureCenterY: aperture.centerY, acceleratingVoltageKV: 200)
    }

    /// App x is the detector column (py4DSTEM qy), app y the row (qx).
    func testFittedMeanBeatsADivergedAperture() throws {
        var calibration = Calibration()
        calibration.origin = maps(x: 100, y: 90)
        calibration.originProvenance = .fitted
        calibrated(&calibration)
        let origin = ParallaxPhysicalCalibration.diffractionOrigin(
            calibration: calibration, apertureCentre: (x: 105, y: 90))
        XCTAssertEqual(origin.qy, 100)
        XCTAssertEqual(origin.qx, 90)
        let physical = try resolved(calibration, aperture: Aperture(centerX: 105, centerY: 90))
        XCTAssertEqual(physical.originQY, 100, "the fitted column, not the aperture's 105")
        XCTAssertEqual(physical.originQX, 90)
    }

    func testRecordedMeanBeatsADivergedAperture() throws {
        var calibration = Calibration()
        calibration.recordedOriginX = 60.5
        calibration.recordedOriginY = 61.5
        calibration.originProvenance = .fileMean
        calibrated(&calibration)
        let physical = try resolved(calibration, aperture: Aperture(centerX: 70, centerY: 70))
        XCTAssertEqual(physical.originQY, 60.5)
        XCTAssertEqual(physical.originQX, 61.5)
    }

    /// With no measured origin the aperture the user placed IS the origin — the
    /// `tools/parallax-preprocessing-test` axis-convention case, unchanged.
    func testManualOriginFallsBackToTheAperture() throws {
        var calibration = Calibration()
        calibration.originProvenance = .manual
        calibrated(&calibration)
        let physical = try resolved(calibration, aperture: Aperture(centerX: 3.65, centerY: 2.35))
        XCTAssertEqual(physical.originQX, 2.35, accuracy: 1e-6)
        XCTAssertEqual(physical.originQY, 3.65, accuracy: 1e-6)
    }

    // MARK: - AppState wiring

    private func fittedState() -> AppState {
        let state = AppState()
        var calibration = Calibration()
        calibration.origin = maps(x: 100, y: 90)
        calibration.originProvenance = .fitted
        calibrated(&calibration)
        state.calibrationSession.calibration = calibration
        state.aperture = Aperture(centerX: 100, centerY: 90, inner: 0, outer: 20)
        return state
    }

    private func originUsed(_ state: AppState) throws -> (qx: Double, qy: Double) {
        let physical = try resolved(state.calibrationSession.calibration, aperture: state.aperture)
        return (physical.originQX, physical.originQY)
    }

    /// What the UI does on a 5 px centre drag: `updateAperture` sets the fit
    /// aside and the aperture becomes the (manual) origin — by design, so the
    /// origin parallax uses follows the drag, and Restore Fitted Origin
    /// returns it. Held green before and after the D079 fix (the register's
    /// "drag overrides the fit" symptom is this documented behaviour).
    func testACentreDragMakesTheDraggedCentreTheManualOriginAndRestoreReturnsTheFit() throws {
        let state = fittedState()
        var dragged = state.aperture
        dragged.centerX += 5
        state.updateAperture(dragged)
        XCTAssertEqual(state.calibrationSession.calibration.originProvenance, .manual)
        let afterDrag = try originUsed(state)
        XCTAssertEqual(afterDrag.qy, 105)
        XCTAssertEqual(afterDrag.qx, 90)
        state.restoreFittedOrigin()
        let restored = try originUsed(state)
        XCTAssertEqual(restored.qy, 100)
        XCTAssertEqual(restored.qx, 90)
    }

    /// The real divergence: replay and lineage restore assign `aperture`
    /// directly (`AppState+Replay.swift`, `AppState+Lineage.swift`), so the
    /// calibration keeps its fitted origin. The origin parallax uses must stay
    /// the fitted one, as DPC, strain and ACOM's already do.
    func testAnApertureAssignedBehindUpdateApertureDoesNotMoveTheOriginUsed() throws {
        let state = fittedState()
        let before = try originUsed(state)
        state.aperture.centerX += 5     // what a replayed/restored aperture does
        let after = try originUsed(state)
        XCTAssertEqual(after.qy, before.qy)
        XCTAssertEqual(after.qx, before.qx)
        XCTAssertEqual(after.qy, 100)
    }
}
