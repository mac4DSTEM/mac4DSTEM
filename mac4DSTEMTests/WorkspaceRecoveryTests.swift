import Foundation
import XCTest
@testable import mac4DSTEM

final class WorkspaceRecoveryTests: XCTestCase {
    func testRecoveryRecordCodableRoundTrip() throws {
        let value = DatasetRecoveryRecord(
            datasetID: "/tmp/example.h5", bookmark: Data([1, 2, 3]),
            selectedX: 7, selectedY: 9, analysisMode: "Strain",
            updated: Date(timeIntervalSince1970: 12)
        )
        let decoded = try JSONDecoder().decode(
            DatasetRecoveryRecord.self, from: JSONEncoder().encode(value)
        )
        XCTAssertEqual(decoded, value)
    }

    func testRecentDatasetIdentityIsStableAcrossDisplayChanges() {
        let first = RecentDataset(id: "/tmp/a.h5", displayName: "a.h5",
                                  bookmark: Data([1]), lastOpened: .distantPast)
        let renamed = RecentDataset(id: "/tmp/a.h5", displayName: "renamed.h5",
                                    bookmark: Data([2]), lastOpened: .now)
        XCTAssertEqual(first.id, renamed.id)
        XCTAssertNotEqual(first, renamed)
    }
}
