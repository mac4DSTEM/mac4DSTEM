import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// core-data-05 (S22a ride-along): the inspector's excluded-fraction
/// disclosure and the readiness/refusal paths must share ONE policy floor.
/// The retired 0.5% threshold disclosed fractions Gate B measured as inside
/// the robust trim's own false-positive range on clean data.
@MainActor
final class CalibrationDisclosureTests: XCTestCase {

    func testExcludedFractionDisclosureUsesTheSharedPolicyFloor() {
        // 1% sits between the retired 0.5% and the shared 2%: the old
        // threshold disclosed it; the policy says stay quiet.
        XCTAssertFalse(CalibrationDetailsView.disclosesExcludedFraction(0.01))
        // Exactly at the floor: quiet — the policy is strictly-greater,
        // matching Calibration's own readiness use of the constant.
        XCTAssertFalse(CalibrationDetailsView.disclosesExcludedFraction(
            Calibration.excludedFractionDisclosureFloor))
        // Above the floor: disclosed.
        XCTAssertTrue(CalibrationDetailsView.disclosesExcludedFraction(0.03))
    }
}
