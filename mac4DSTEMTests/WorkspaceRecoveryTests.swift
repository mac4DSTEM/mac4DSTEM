import Foundation
import DSTEMCore
import DSTEMSession
import XCTest

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

    /// A dataset is remembered with a read-only security-scoped bookmark and nothing else is asked for: a read-write
    /// one makes the sandbox stamp quarantine and provenance attributes onto the data file (`._` files on exFAT, #321).
    func testBookmarkIsReadOnlyAndNeverAsksForReadWrite() throws {
        var asked: [URL.BookmarkCreationOptions] = []
        let data = try WorkspaceRecoveryStore.bookmark(for: URL(fileURLWithPath: "/Volumes/SSD/086_STEM SI.dm4")) { _, options in
            asked.append(options); return Data([7])
        }
        XCTAssertEqual(data, Data([7]))
        XCTAssertEqual(asked, [[.withSecurityScope, .securityScopeAllowOnlyReadAccess]])
    }

    /// Both refused (no access at all): the error still reaches the caller.
    func testBookmarkThrowsWhenNeitherScopeIsGranted() {
        XCTAssertThrowsError(try WorkspaceRecoveryStore.bookmark(for: URL(fileURLWithPath: "/x.h5")) { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        })
    }
}
