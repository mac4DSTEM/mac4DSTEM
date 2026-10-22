import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Known-crystal Q calibration on the planted Al [001] case of the calibration design (2026-10-22, section 6): on that zone axis
/// {111} is not in the zone, so the innermost visible ring is {200}. The estimator used to take the first observed ring for the
/// crystal's first shell ({111}) and read Δq 13.4 % low. Planted: Δq = 0.0320 Å⁻¹/px (the design's 0.0100 scaled so all three rings fit the
/// demo detector's 64 px), rings {200}, {220}, {400} at 15.4, 21.8 and 30.9 px, four peaks each, 25 identical positions.
@MainActor
final class ShellAssignmentEndToEndTests: XCTestCase {
    static let deltaQ = 0.0320
    static let a = 4.0495

    private func plantedState(radii: [Double]) async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.navigation.analysisMode = .disks
        await state.runDiskDetection()
        let scan = state.descriptor.map { max($0.rx, $0.ry) } ?? 12
        let centre = Float(state.descriptor.map { $0.qx } ?? 64) / 2
        let count = scan * scan
        let signs = (0..<count).map { Float($0 % 2 == 0 ? 1 : -1) }
        state.calibrationSession.calibration.originProvenance = .fitted
        state.calibrationSession.calibration.probeRadius = 4.5
        state.calibrationSession.calibration.origin = OriginMaps(
            width: scan, height: scan,
            measuredX: signs.map { centre + $0 * 4.5 * 0.2 },
            measuredY: [Float](repeating: centre, count: count),
            fittedX: [Float](repeating: centre, count: count),
            fittedY: [Float](repeating: centre, count: count))
        PlantedQCalibration.setRings(radiiPixels: radii, on: state)
        return state
    }

    /// Fails on the old estimator: it reads the {200} ring as {111} and writes 0.0277 instead of 0.0320.
    func testTheFirstVisibleRingOfAl001IsRecognisedAsTwoHundred() async throws {
        let g200 = 2 / Self.a, g220 = sqrt(8.0) / Self.a, g400 = 4 / Self.a
        let state = try await plantedState(radii: [g200 / Self.deltaQ, g220 / Self.deltaQ, g400 / Self.deltaQ])
        state.acomSession.modelSelection = .library("al_fcc")
        XCTAssertNotNil(state.resolvedACOMModel)

        await state.calibrateQFromCrystal()

        let q = try XCTUnwrap(state.calibrationSession.calibration.qPixelSize, "no Q written: \(state.statusText)")
        XCTAssertEqual(q, Self.deltaQ, accuracy: 1e-6 * Self.deltaQ, "Q \(q), status: \(state.statusText)")
        XCTAssertTrue(state.statusText.contains("assigned to {200}"), state.statusText)
    }
}
