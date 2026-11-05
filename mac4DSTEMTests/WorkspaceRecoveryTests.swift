import Foundation
import DSTEMCore
import DSTEMSession
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

    /// A file the sandbox lets the app read but not write (a pick on a read-only volume, a DEBUG `--open` file) refuses
    /// a read-write security-scoped bookmark with NSCocoaErrorDomain 256; the store then keeps a read-only one, so the
    /// open is remembered instead of reporting "recent-file access could not be remembered".
    func testBookmarkFallsBackToReadOnlyScopeWhenReadWriteIsRefused() throws {
        let url = URL(fileURLWithPath: "/Volumes/ReadOnly/scan.h5")
        var asked: [URL.BookmarkCreationOptions] = []
        let data = try WorkspaceRecoveryStore.bookmark(for: url) { _, options in
            asked.append(options)
            guard options.contains(.securityScopeAllowOnlyReadAccess) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
            }
            return Data([7])
        }
        XCTAssertEqual(data, Data([7]))
        XCTAssertEqual(asked, [[.withSecurityScope], [.withSecurityScope, .securityScopeAllowOnlyReadAccess]])
    }

    /// A writable file keeps its read-write grant: the read-only option is never asked for.
    func testBookmarkStaysReadWriteWhenAllowed() throws {
        var asked: [URL.BookmarkCreationOptions] = []
        _ = try WorkspaceRecoveryStore.bookmark(for: URL(fileURLWithPath: "/tmp/a.h5")) { _, options in
            asked.append(options); return Data([1])
        }
        XCTAssertEqual(asked, [[.withSecurityScope]])
    }

    /// Both refused (no access at all): the error still reaches the caller.
    func testBookmarkThrowsWhenNeitherScopeIsGranted() {
        XCTAssertThrowsError(try WorkspaceRecoveryStore.bookmark(for: URL(fileURLWithPath: "/x.h5")) { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        })
    }
}
