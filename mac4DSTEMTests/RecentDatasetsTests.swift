import XCTest
@testable import mac4DSTEM

/// Pins `RecentDatasets` — the recents list extracted from `AppState` as S3's
/// seam (docs/development-process.md §7).
///
/// Persistence is injected as a recorder: `WorkspaceRecoveryStore` is
/// `UserDefaults.standard` all the way down, and a test that wrote the user's
/// real recents would be worse than no test.
@MainActor
final class RecentDatasetsTests: XCTestCase {

    private final class PersistRecorder {
        var saved: [[RecentDataset]] = []
        var last: [RecentDataset]? { saved.last }
    }

    private func makeList(
        _ entries: [RecentDataset] = []
    ) -> (list: RecentDatasets, recorder: PersistRecorder) {
        let recorder = PersistRecorder()
        let list = RecentDatasets(entries: entries) { recorder.saved.append($0) }
        return (list, recorder)
    }

    private func entry(_ path: String, bookmark: Data = Data()) -> RecentDataset {
        RecentDataset(id: path, displayName: (path as NSString).lastPathComponent,
                      bookmark: bookmark, lastOpened: Date())
    }

    func testRememberInsertsAtTheFrontAndPersists() {
        let (list, recorder) = makeList([entry("/data/old.h5")])
        list.remember(entry("/data/new.h5"))
        XCTAssertEqual(list.entries.map(\.id), ["/data/new.h5", "/data/old.h5"])
        XCTAssertEqual(recorder.last?.map(\.id), ["/data/new.h5", "/data/old.h5"],
                       "The mutation must reach the store, or a relaunch forgets it")
    }

    func testRememberingAKnownPathMovesItRatherThanDuplicating() {
        let (list, _) = makeList([entry("/data/a.h5"), entry("/data/b.h5")])
        list.remember(entry("/data/b.h5"))
        XCTAssertEqual(list.entries.map(\.id), ["/data/b.h5", "/data/a.h5"],
                       "Re-opening a dataset must not grow the list")
    }

    func testTheListIsCappedAtCapacityDroppingTheOldest() {
        let (list, _) = makeList((0..<RecentDatasets.capacity).map { entry("/data/\($0).h5") })
        list.remember(entry("/data/newest.h5"))
        XCTAssertEqual(list.entries.count, RecentDatasets.capacity)
        XCTAssertEqual(list.entries.first?.id, "/data/newest.h5")
        XCTAssertFalse(list.entries.contains { $0.id == "/data/\(RecentDatasets.capacity - 1).h5" },
                       "The oldest entry is the one that goes")
    }

    func testRemoveDeletesExactlyThatEntryAndPersists() {
        let (list, recorder) = makeList([entry("/data/a.h5"), entry("/data/b.h5")])
        list.remove(id: "/data/a.h5")
        XCTAssertEqual(list.entries.map(\.id), ["/data/b.h5"])
        XCTAssertEqual(recorder.last?.map(\.id), ["/data/b.h5"])
    }

    func testUpdateBookmarkReplacesInPlaceAndAMissIsANoOp() {
        let (list, recorder) = makeList([entry("/data/a.h5", bookmark: Data([1]))])
        list.updateBookmark(Data([2]), forID: "/data/a.h5")
        XCTAssertEqual(list.entries.first?.bookmark, Data([2]))
        XCTAssertEqual(recorder.saved.count, 1, "The refresh must persist")

        list.updateBookmark(Data([3]), forID: "/data/gone.h5")
        XCTAssertEqual(list.entries.first?.bookmark, Data([2]),
                       "A miss must not touch any other entry")
        XCTAssertEqual(recorder.saved.count, 1, "A no-op must not persist")
    }

    func testLocationLabelsDistinguishSameNamedEntries() {
        // The Track B 2026-08-18 defect: one cube on a NAS and its copy on a
        // local SSD rendered as two identical rows.
        let (list, _) = makeList([
            entry("/Volumes/eXtendedGROUPS/inbox/cube.h5"),
            entry("/Volumes/PL_SSD_2TB/inbox/cube.h5"),
        ])
        let labels = list.locationLabels
        XCTAssertNotEqual(labels["/Volumes/eXtendedGROUPS/inbox/cube.h5"],
                          labels["/Volumes/PL_SSD_2TB/inbox/cube.h5"],
                          "Same-named entries must be told apart")
        XCTAssertEqual(labels["/Volumes/PL_SSD_2TB/inbox/cube.h5"], "PL_SSD_2TB")
    }

    func testLabelsAreRecomputedOnMutationNotOnRead() {
        // Two same-named entries force disambiguation; removing one must
        // simplify the survivor's label back to its volume. If the labels were
        // stamped once at init, this is the assertion that catches it.
        let (list, _) = makeList([
            entry("/Volumes/NAS/deep/path/cube.h5"),
            entry("/Volumes/NAS/other/route/cube.h5"),
        ])
        XCTAssertNotEqual(list.locationLabels["/Volumes/NAS/deep/path/cube.h5"], "NAS",
                          "precondition: the sibling forces a longer label")
        list.remove(id: "/Volumes/NAS/other/route/cube.h5")
        XCTAssertEqual(list.locationLabels["/Volumes/NAS/deep/path/cube.h5"], "NAS",
                       "The label must relax once the ambiguity is gone")
    }
}
