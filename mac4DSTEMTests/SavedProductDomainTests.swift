import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Clean-up audit row 4 (owner, 2026-09-28): a saved product without
/// `display_domain` (only sidecars from before v1.0) is refused, not placed
/// by guessing from its shape. Every product saved since records the key.
@MainActor
final class SavedProductDomainTests: XCTestCase {
    func testASavedProductWithoutADomainIsRefusedByName() {
        XCTAssertThrowsError(try AppState.savedDomain([:], displayName: "Strain εxx")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Strain εxx"), "\(error.localizedDescription)")
        }
    }

    func testASavedProductKeepsTheDomainItRecorded() throws {
        XCTAssertEqual(try AppState.savedDomain(["display_domain": "detector"], displayName: "map"), .detector)
        XCTAssertEqual(try AppState.savedDomain(["display_domain": "scan"], displayName: "map"), .scan)
    }
}
