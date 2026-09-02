import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// P2 (Gate D, 2026-09-01): the three-way frame policy for adopting a session
/// sidecar's calibration. The geometry itself is `CalibrationReReference`'s,
/// already pinned; this pins WHEN it runs — the decision whose absence put a
/// full-frame aperture centre onto a 2× binned detector (the corner BF) and a
/// doubled-frame Q scale into strain.
final class SessionCalibrationFramePolicyTests: XCTestCase {

    private let reduced = LoadSpecification(
        detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 100, width: 100)
    )
    private let otherReduced = LoadSpecification(
        detectorCrop: AxisCrop(yOffset: 10, xOffset: 10, height: 80, width: 80)
    )

    func testSameViewAdoptsVerbatim() {
        XCTAssertEqual(
            SessionCalibrationFramePolicy.decide(session: reduced, loaded: reduced),
            .identity
        )
        XCTAssertEqual(
            SessionCalibrationFramePolicy.decide(session: .fullExtent, loaded: .fullExtent),
            .identity
        )
    }

    func testFullExtentSessionOntoReducedViewReReferences() {
        XCTAssertEqual(
            SessionCalibrationFramePolicy.decide(session: .fullExtent, loaded: reduced),
            .reReference,
            "the owner's case: sidecar recorded on the whole file, cube opened reduced"
        )
    }

    func testDifferentReducedViewsRefuseWithBothViewsNamed() {
        let policy = SessionCalibrationFramePolicy.decide(
            session: reduced, loaded: otherReduced
        )
        guard case .refuse(let reason) = policy else {
            return XCTFail("two different reduced views must refuse, got \(policy)")
        }
        XCTAssertTrue(reason.contains("recorded on a different view"),
                      "reason: \(reason)")
        XCTAssertTrue(reason.contains("reopen") || reason.contains("Reopen"),
                      "the reason states the remedy: \(reason)")
    }

    func testReducedSessionOntoFullExtentAlsoRefuses() {
        // Un-reducing is the same guess in the other direction: values
        // recorded on a crop cannot be promoted to the whole file.
        guard case .refuse = SessionCalibrationFramePolicy.decide(
            session: reduced, loaded: .fullExtent
        ) else {
            return XCTFail("a reduced-view session must not be promoted raw to full extent")
        }
    }
}
