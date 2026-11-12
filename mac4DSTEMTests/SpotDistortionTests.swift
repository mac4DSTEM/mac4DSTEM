import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoCore
import DiffractoOrientation
@testable import mac4DSTEM

/// mac4DSTEM#210: the distortion fitted on the matrix's spots, turned into the values Prepare's ellipse correction and Q pixel
/// scale take. The fit itself is DiffractoKit's and is tested there (`MatrixSpotDistortionTests`); what is tested here is
/// the conversion: the ellipse the app is given must make the stretched pattern round again, in the app's own correction
/// (`Calibration.ellipseCorrectedOffset`, py4DSTEM's a, b, theta in its row-first frame), at the Q scale the fit names.
final class SpotDistortionTests: XCTestCase {

    /// A stretch of `ratio` along the direction `axisDegrees` from x (columns) towards y (rows), times `scale`.
    private func stretched(_ g: SIMD2<Double>, ratio: Double, axisDegrees: Double, scale: Double) -> SIMD2<Double> {
        let a = axisDegrees * .pi / 180, c = cos(a), s = sin(a)
        let along = g.x * c + g.y * s, across = -g.x * s + g.y * c
        return SIMD2(scale * (ratio * along * c - across * s), scale * (ratio * along * s + across * c))
    }

    /// Al on [001], turned 12 degrees: the four 200 and four 220 spots, stretched by 1.0506 at 166.3 degrees and 0.6 % too
    /// large (the numbers of the SPED scan of Zenodo 10.5281/zenodo.2652906), as pixels on a 66 px detector at 0.026 1/Å.
    func testTheFittedEllipseMakesTheStretchedPatternRoundAtTheFittedScale() throws {
        let q = 0.026, ratio = 1.0506, axis = 166.3, scale = 1.0064 / ratio.squareRoot()
        let first = 2 / 4.0495
        var ideal: [SIMD2<Double>] = []
        for k in 0..<4 {
            let angle = (12 + 90 * Double(k)) * .pi / 180
            ideal.append(SIMD2(first * cos(angle), first * sin(angle)))
            ideal.append(SIMD2(first * 2.0.squareRoot() * cos(angle + .pi / 4), first * 2.0.squareRoot() * sin(angle + .pi / 4)))
        }
        let measured = ideal.map { stretched($0, ratio: ratio, axisDegrees: axis, scale: scale) }
        // The kit's fit of exactly this pattern, eight positions of it.
        let origin: Float = 33
        let peaks = ([SIMD2<Double>(0, 0)] + measured).map { SIMD2(Double(origin) + $0.x / q, Double(origin) + $0.y / q) }
        let m = ZoneAxisFrame.matrix(detectorBasis: ZoneAxisFrame.detectorBasis(zoneAxis: SIMD3(0, 0, 1)), inPlaneAngle: Float(12 * Double.pi / 180))
        let al = try PhaseOrientationCandidate(name: "Al", crystal: CrystalPresets.aluminum, kMax: 0.83)
        let field = MatrixOrientationField(width: 8, height: 1, results: [OrientationResult](repeating: .empty, count: 8),
                                           orientations: Array(repeating: m, count: 8))
        let kit = try XCTUnwrap(PhaseVectorMatcher.matrixSpotDistortion(scan: [[SIMD2<Double>]](repeating: peaks, count: 8), field: field,
                                                                        reflections: al.reflections, originX: origin, originY: origin,
                                                                        invAngstromPerPixel: q, maximumVectorInvAngstrom: 0.83))
        let fit = try XCTUnwrap(SpotDistortionFit(kit, invAngstromPerPixel: q, firstShellInvAngstrom: first, positionCount: 8))
        XCTAssertEqual(fit.stretchRatio, ratio, accuracy: 0.0005)
        XCTAssertEqual(fit.axisDegrees, axis, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(fit.ellipseA, fit.ellipseB)
        XCTAssertEqual(fit.ellipseA / fit.ellipseB, ratio, accuracy: 0.0005)
        XCTAssertLessThan(fit.residualPixels, 0.001)
        XCTAssertGreaterThan(fit.residualWithoutStretchPixels, 0.3)
        XCTAssertTrue(fit.isCredible)

        // Spots that do not lie on one stretched lattice: half the positions stretched along x, half along y, by 8 %. The
        // fit leaves more than half a pixel over, and such a fit is not offered.
        let alongX = ([SIMD2<Double>(0, 0)] + ideal.map { stretched($0, ratio: 1.08, axisDegrees: 0, scale: 1) }).map { SIMD2(Double(origin) + $0.x / q, Double(origin) + $0.y / q) }
        let alongY = ([SIMD2<Double>(0, 0)] + ideal.map { stretched($0, ratio: 1.08, axisDegrees: 90, scale: 1) }).map { SIMD2(Double(origin) + $0.x / q, Double(origin) + $0.y / q) }
        let mixedScan = [[SIMD2<Double>]](repeating: alongX, count: 4) + [[SIMD2<Double>]](repeating: alongY, count: 4)
        let mixedKit = try XCTUnwrap(PhaseVectorMatcher.matrixSpotDistortion(scan: mixedScan, field: field, reflections: al.reflections, originX: origin, originY: origin,
                                                                             invAngstromPerPixel: q, maximumVectorInvAngstrom: 0.83))
        let mixed = try XCTUnwrap(SpotDistortionFit(mixedKit, invAngstromPerPixel: q, firstShellInvAngstrom: first, positionCount: 8))
        XCTAssertGreaterThan(mixed.residualPixels, SpotDistortionFit.largestResidualOfferedPixels, "fixture: the mixed pattern must not fit one stretch")
        XCTAssertFalse(mixed.isCredible)

        // The app's own correction with these values: every spot comes back to its true length at the fitted scale.
        var calibration = Calibration()
        calibration.ellipseA = fit.ellipseA
        calibration.ellipseB = fit.ellipseB
        calibration.ellipseTheta = fit.ellipseThetaDegrees * .pi / 180
        XCTAssertTrue(calibration.hasEllipse)
        for (g, u) in zip(ideal, measured) {
            let corrected = calibration.ellipseCorrectedOffset(dx: Float(u.x / q), dy: Float(u.y / q))
            let length = (Double(corrected.x) * Double(corrected.x) + Double(corrected.y) * Double(corrected.y)).squareRoot() * fit.invAngstromPerPixel
            XCTAssertEqual(length, (g.x * g.x + g.y * g.y).squareRoot(), accuracy: 0.0006,
                           "a spot of the corrected pattern is not at its true length (ellipse a \(fit.ellipseA), b \(fit.ellipseB), theta \(fit.ellipseThetaDegrees))")
        }
        // The session takes the values as a typed ellipse would be taken.
        XCTAssertNil(CalibrationSession().applyManualEllipse(a: fit.ellipseA, b: fit.ellipseB, thetaDegrees: fit.ellipseThetaDegrees))
    }

    /// Without disks, a crystal or a Q scale the action says why, and holds nothing.
    @MainActor
    func testWithoutItsInputsTheFitSaysWhatIsMissing() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        XCTAssertEqual(state.spotDistortionBlocker, "Needs Detect All Disks first.")
        await state.fitDistortionFromSpots()
        XCTAssertNil(state.spotDistortion.pending)
        XCTAssertTrue(state.statusText.contains("Detect All Disks"), state.statusText)
    }
}
