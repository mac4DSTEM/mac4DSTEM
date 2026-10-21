import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The manual Q/R editor hides behind "Override" while a file's or a session's scale is in force, and shows open when
/// there is no value or the value is the person's own (design review 2026-10-21).
final class CalibrationOverrideDisclosureTests: XCTestCase {
    func testAScaleInForceFromTheFileOrASessionHidesItsEditorBehindOverride() {
        XCTAssertTrue(CalibrationReadinessRow.needsOverrideDisclosure(status: .ready(.importedFile)))
        XCTAssertTrue(CalibrationReadinessRow.needsOverrideDisclosure(status: .ready(.sessionSidecar)))
    }

    func testAMissingOrManualScaleShowsTheEditorOpen() {
        XCTAssertFalse(CalibrationReadinessRow.needsOverrideDisclosure(status: .ready(.manual)))
        XCTAssertFalse(CalibrationReadinessRow.needsOverrideDisclosure(status: .missing))
    }
}
