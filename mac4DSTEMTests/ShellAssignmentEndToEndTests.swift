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

    /// mac4DSTEM#110. Two rings of Al [001], {200} and {220}, fit {220}, {400} at the same ratio, so the rings cannot say which shell
    /// is first. With no pixel size from the file the scale is not guessed: nothing is written and the sentence names both shells.
    /// Mutation: taking the kit's lowest shell silently - a scale is written and this is red.
    func testTwoRingsThatFitTwoShellsWriteNoScaleWithoutAPixelSize() async throws {
        let g200 = 2 / Self.a, g220 = sqrt(8.0) / Self.a
        let state = try await plantedState(radii: [g200 / Self.deltaQ, g220 / Self.deltaQ])
        state.acomSession.modelSelection = .library("al_fcc")
        XCTAssertNil(state.calibrationSession.calibration.qPixelSize, "precondition: the fixture states no reciprocal pixel size")

        await state.calibrateQFromCrystal()

        XCTAssertNil(state.calibrationSession.calibration.qPixelSize, "no scale is guessed: \(state.statusText)")
        XCTAssertNil(state.qCalibration.estimate)
        let refusal = try XCTUnwrap(state.qCalibration.refusal, state.statusText)
        XCTAssertTrue(refusal.contains("{200} or {220}") && refusal.contains("no scale was written"), refusal)
        // mac4DSTEM#169: the way on is the existing field, said in the refusal. Mutation: the old "Type the reciprocal pixel size" - red.
        XCTAssertTrue(refusal.contains("Enter an approximate Q pixel size (Prepare, within 10 % is enough) and calibrate again"), refusal)

        // And it is the way on: an approximate value, 4 % off, typed into that field decides; the rings measure the exact scale.
        state.calibrationSession.calibration.qPixelSize = Self.deltaQ * 1.04
        state.calibrationSession.calibration.qPixelUnits = "Å⁻¹"
        state.calibrationSession.provenance.qScale = .manual
        await state.calibrateQFromCrystal()
        let q = try XCTUnwrap(state.calibrationSession.calibration.qPixelSize, state.statusText)
        XCTAssertEqual(q, Self.deltaQ, accuracy: 1e-6 * Self.deltaQ, state.statusText)
        XCTAssertTrue(state.statusText.contains("assigned to {200} by the pixel size already set"), state.statusText)
    }

    /// The same two rings with a pixel size already set (the file's or a typed one): the shell whose scale is nearest to it is taken, the
    /// measured scale is written, and the status line says what decided and which shell fits equally. A size near the {220} reading
    /// picks {220}; a size that fits neither writes nothing. Mutation: ignoring the pixel size (always the lowest shell) - the second
    /// case is red.
    func testAPixelSizeAlreadySetDecidesBetweenTwoEquallyFittingShells() async throws {
        let g200 = 2 / Self.a, g220 = sqrt(8.0) / Self.a
        for (set, label, other, expected) in [(0.0315, "{200}", "{220}", Self.deltaQ), (0.0460, "{220}", "{200}", Self.deltaQ * g220 / g200)] {
            let state = try await plantedState(radii: [g200 / Self.deltaQ, g220 / Self.deltaQ])
            state.acomSession.modelSelection = .library("al_fcc")
            state.calibrationSession.calibration.qPixelSize = set
            state.calibrationSession.calibration.qPixelUnits = "Å⁻¹"
            state.calibrationSession.provenance.qScale = .manual

            await state.calibrateQFromCrystal()

            let q = try XCTUnwrap(state.calibrationSession.calibration.qPixelSize, state.statusText)
            XCTAssertEqual(q, expected, accuracy: 1e-6 * expected, "set \(set): \(state.statusText)")
            XCTAssertEqual(state.qCalibration.estimate?.assignment?.label, label)
            XCTAssertTrue(state.statusText.contains("assigned to \(label) by the pixel size already set (\(other) fits the rings equally)"), state.statusText)
        }
        let state = try await plantedState(radii: [g200 / Self.deltaQ, g220 / Self.deltaQ])
        state.acomSession.modelSelection = .library("al_fcc")
        state.calibrationSession.calibration.qPixelSize = 0.0100
        state.calibrationSession.calibration.qPixelUnits = "Å⁻¹"
        state.calibrationSession.provenance.qScale = .manual
        await state.calibrateQFromCrystal()
        XCTAssertEqual(state.calibrationSession.calibration.qPixelSize, 0.0100, "a size that fits neither shell is left as it was")
        XCTAssertTrue(try XCTUnwrap(state.qCalibration.refusal).contains("agrees with none of them"))
    }

    /// mac4DSTEM#169. Two Al rings at 1 : 1.645 fit {111}, {220} (1.633) and {200}, {311} (1.658): two first rings with DIFFERENT
    /// predictions, which the kit refuses and names. A pixel size already set decides when exactly one of the two scales lies within
    /// 10 % of it; the measured scale is written and the line says what decided. Near neither, near both, or with no pixel size, the
    /// kit's refusal stands and nothing is written. Mutation: taking the nearer candidate without the "exactly one" rule - the
    /// near-both case writes a scale and is red; ignoring the pixel size - the first two cases are red.
    func testAPixelSizeAlreadySetDecidesBetweenTwoFirstRingsThatPredictDifferentScales() async throws {
        let g111 = sqrt(3.0) / Self.a, g200 = 2 / Self.a
        let r1 = g111 / Self.deltaQ                       // read as {111} the scale is 0.0320; read as {200} it is 0.03695
        func run(pixelSize: Double?) async throws -> AppState {
            let state = try await plantedState(radii: [r1, 1.645 * r1])
            state.acomSession.modelSelection = .library("al_fcc")
            if let pixelSize {
                state.calibrationSession.calibration.qPixelSize = pixelSize
                state.calibrationSession.calibration.qPixelUnits = "Å⁻¹"
                state.calibrationSession.provenance.qScale = .manual
            }
            await state.calibrateQFromCrystal()
            return state
        }
        for (set, label, other, expected) in [(0.0315, "{111}", "{200}", Self.deltaQ), (0.0375, "{200}", "{111}", Self.deltaQ * g200 / g111)] {
            let state = try await run(pixelSize: set)
            let q = try XCTUnwrap(state.calibrationSession.calibration.qPixelSize, state.statusText)
            XCTAssertEqual(q, expected, accuracy: 1e-6 * expected, "set \(set): \(state.statusText)")
            XCTAssertEqual(state.qCalibration.estimate?.assignment?.label, label)
            XCTAssertTrue(state.statusText.contains("assigned to \(label) by the pixel size already set (\(other) fits the rings too, at another scale)"),
                          state.statusText)
            XCTAssertTrue(state.statusText.contains("shell ratio unchecked"), state.statusText)
            // The Q row and the Q shell check row say why it is unchecked. Mutation: the estimator's own reason kept ("this crystal
            // has only one allowed shell within range", not true here) - both are red.
            let note = "Shell ratio unchecked — the first ring, \(label), was chosen by the pixel size already set"
            XCTAssertEqual(state.calibrationSession.provenance.qShellCaveat?.text, note)
            XCTAssertEqual(state.qCalibration.selfCheckSummary, note)
        }
        // 0.0345 is 7.2 % from the {111} scale and 6.6 % from the {200} scale: both within reach, so it does not decide.
        for set in [0.0345, 0.0100] {
            let state = try await run(pixelSize: set)
            XCTAssertEqual(state.calibrationSession.calibration.qPixelSize, set, "left as it was: \(state.statusText)")
            let refusal = try XCTUnwrap(state.qCalibration.refusal)
            XCTAssertTrue(refusal.contains("Two assignments fit equally well ({111} and {200} first)"))
            XCTAssertTrue(refusal.contains("The Q pixel size already set does not decide") && refusal.contains("no scale was written"), refusal)
            XCTAssertFalse(refusal.contains("crystal's list"), refusal)
        }
        let none = try await run(pixelSize: nil)
        XCTAssertNil(none.calibrationSession.calibration.qPixelSize)
        let refusal = try XCTUnwrap(none.qCalibration.refusal)
        XCTAssertTrue(refusal.contains("Two assignments fit equally well ({111} and {200} first)"))
        // mac4DSTEM#169: no list to pick from exists in the app; the refusal points at the Q pixel size field instead.
        XCTAssertTrue(refusal.contains("Enter an approximate Q pixel size (Prepare, within 10 % is enough) and calibrate again"), refusal)
        XCTAssertFalse(refusal.contains("crystal's list"), refusal)
        // Both candidate scales are named, so the reader can judge them against the pattern.
        XCTAssertTrue(refusal.contains("The two scales: {111} gives ") && refusal.contains("{200} gives "), refusal)
    }
}
