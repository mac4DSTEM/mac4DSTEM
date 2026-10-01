import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Review 2026-09-30 row 2: `setManualQPixelUnits` set the units and the
/// `.manual` provenance but recorded no `calibration_q` lineage node, while
/// `setManualQPixelSize` did. Staleness is judged by the ACTIVE
/// `calibration_q` node (`lineageCalibrationSignatures`), so nm⁻¹ → Å⁻¹ —
/// ten times the physical Q every phase-map tolerance reads — left the phase
/// map "current" and the lineage's `q_units` wrong.
@MainActor
final class QUnitsRow2LineageTests: XCTestCase {

    private func activeQNode(_ state: AppState) -> SessionLineage.Node? {
        state.replay.lineage.activeNodes().first { $0.kind == "calibration_q" }
    }

    /// Mutation it catches: the units setter not calling
    /// `recordQCalibrationRun` (the active node keeps `q_units` nm⁻¹).
    func testChangingTheQUnitsRecordsANewCalibrationNodeWithThoseUnits() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        XCTAssertNil(state.calibrationSession.calibration.qPixelSize, "the uncalibrated demo arrives without a Q")

        state.setManualQPixelSize(0.12)     // typed beside the picker's default unit, nm⁻¹
        let typed = try XCTUnwrap(activeQNode(state), "the typed size is a node (ADR 047)")
        XCTAssertEqual(typed.parameters["q_units"], "nm⁻¹")

        state.setManualQPixelUnits("Å⁻¹")
        // Two calibration runs with no product between them collapse into one
        // node (R3), so the id may stay; what the active node SAYS must change.
        let changed = try XCTUnwrap(activeQNode(state))
        XCTAssertEqual(changed.parameters["q_units"], "Å⁻¹", "the active Q node still reads the old units")
        XCTAssertEqual(changed.parameters["q_pixel_size"], String(0.12))
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .manual)
    }

    /// Without a size there is no scale to record: the units alone are not a
    /// calibration, and `recordQCalibrationRun` itself refuses them.
    func testUnitsWithoutASizeRecordNothing() async {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.setManualQPixelUnits("Å⁻¹")
        XCTAssertNil(activeQNode(state))
        XCTAssertNil(state.calibrationSession.provenance.qScale)
    }
}
