import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Slot 4½ lane B2: Crystal Maps / Bragg Disks wording and the Mirrored readout.
@MainActor
final class PolishB2Tests: XCTestCase {

    private func result(mirrored: Bool) -> OrientationResult {
        OrientationResult(templateIndex: 0, euler: EulerAngles(phi1: 0.1, Phi: 0.2, phi2: 0.3),
                          score: 1, secondScore: 0.5, phaseID: 0, mirrored: mirrored)
    }

    func testMirroredReadoutShowsTheFlag() {
        let state = AppState()
        var map = OrientationMap(width: 2, height: 1, symmetry: .cubic)
        map.results = [result(mirrored: true), result(mirrored: false)]
        state.acomSession.orientationMap = map
        state.selectedScan = ScanPos(x: 0, y: 0)
        XCTAssertEqual(state.selectedMirroredText, "Yes")
        state.selectedScan = ScanPos(x: 1, y: 0)
        XCTAssertEqual(state.selectedMirroredText, "No")
        state.selectedScan = ScanPos(x: 5, y: 0)
        XCTAssertNil(state.selectedMirroredText, "outside the map: no row")
    }

    func testRerunVerbOnlyForAFullScanAtTheCurrentQuality() {
        let s = ACOMSession()
        s.scope = .fullScan
        XCTAssertEqual(s.primaryActionTitle, "Run Full Orientation Map")
        s.hasOrientationMap = true
        s.lastRunScope = .fullScan
        s.lastRunQuality = s.quality
        XCTAssertEqual(s.primaryActionTitle, "Re-run Full Orientation Map")
        s.lastRunScope = .preview
        XCTAssertEqual(s.primaryActionTitle, "Run Full Orientation Map",
                       "a preview map is not a full-scan map")
    }

    func testPositionCountSingular() {
        XCTAssertEqual(AppState.positionCountText(1), "1 position")
        XCTAssertEqual(AppState.positionCountText(12), "12 positions")
    }

    func testSidebarHintsFitOneLine() {
        let ready = ProductWorkflowReadiness(hasBraggVectors: true)
        let none = ProductWorkflowReadiness()
        let hints = [
            ProductWorkflow.nextStepHint(for: .prepare, readiness: none, calibrationReady: true),
            ProductWorkflow.nextStepHint(for: .image, readiness: none, calibrationReady: true),
            ProductWorkflow.nextStepHint(for: .braggDisks, readiness: ready, calibrationReady: true),
            ProductWorkflow.nextStepHint(for: .map, readiness: ready, calibrationReady: true),
        ]
        for hint in hints {
            XCTAssertLessThanOrEqual(try XCTUnwrap(hint).count, 30)
        }
    }

    func testACOMRequirementPointsAtBelowNotToolsPanel() throws {
        let items = ProductWorkflow.prerequisiteItems(
            for: .acom, readiness: ProductWorkflowReadiness(hasBraggVectors: true))
        let item = try XCTUnwrap(items.first { $0.id == "acomMaterial" })
        guard case .taskPanel(let hint) = item.resolution else { return XCTFail("taskPanel") }
        XCTAssertFalse(hint.contains("tools panel"))
        XCTAssertTrue(hint.contains("Import CIF"))
    }
}
