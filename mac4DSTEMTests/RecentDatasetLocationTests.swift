//
//  RecentDatasetLocationTests.swift
//  The recents list must be able to show the difference between two datasets
//  that share a file name. Found by Track B on 2026-08-18 with the real pair
//  below: the same cube on a NAS and on a local SSD, rendering identically.
//

import XCTest
@testable import mac4DSTEM

final class RecentDatasetLocationTests: XCTestCase {

    // The exact paths from the defect, read out of the app's stored defaults.
    private let nas = "/Volumes/eXtendedGROUPS/IFWT/LMN/User-LMN/Lobpreis$/00_inbox/4DSTEM_Binned_Cubes/036_STEM_SI_preprocessed_filtered_bin_2_20240723.h5"
    private let localBackup = "/Volumes/PL_SSD_2TB/NAS_Backup/00_inbox/4DSTEM_Binned_Cubes/036_STEM_SI_preprocessed_filtered_bin_2_20240723.h5"

    func testTheTwoRowsThatLookedIdenticalNowDiffer() {
        let labels = RecentDatasetLocation.labels(for: [nas, localBackup])
        XCTAssertEqual(labels[0], "eXtendedGROUPS")
        XCTAssertEqual(labels[1], "PL_SSD_2TB")
        XCTAssertNotEqual(labels[0], labels[1])
    }

    func testTheParentDirectoryAloneWouldNotHaveDistinguishedThem() {
        // Both copies live in `00_inbox/4DSTEM_Binned_Cubes`. This is why the
        // label starts at the volume rather than at the parent folder — a fix
        // that showed the parent would have looked right and changed nothing.
        XCTAssertEqual((nas as NSString).deletingLastPathComponent.components(separatedBy: "/").last,
                       (localBackup as NSString).deletingLastPathComponent.components(separatedBy: "/").last)
    }

    func testAPathOutsideVolumesIsNamedRatherThanLeftBlank() {
        let label = RecentDatasetLocation.labels(
            for: ["/Users/someone/data/cube.h5"]
        )[0]
        XCTAssertEqual(label, "This Mac")
    }

    func testEntriesWithDifferentNamesGetTheirVolumeAndNoMore() {
        // No ambiguity to resolve, so the label stays short. A subtitle that
        // grew for no reason would be noise on every row.
        let labels = RecentDatasetLocation.labels(for: [
            "/Volumes/PL_SSD_2TB/a/one.h5",
            "/Volumes/PL_SSD_2TB/b/two.h5",
        ])
        XCTAssertEqual(labels, ["PL_SSD_2TB", "PL_SSD_2TB"])
    }

    func testTwoCopiesOnTheSameVolumeFallBackToTheDirectoryChain() {
        // Same name, same volume: the volume cannot separate them, so the label
        // extends by one directory — and only by one.
        let labels = RecentDatasetLocation.labels(for: [
            "/Volumes/PL_SSD_2TB/monday/cube.h5",
            "/Volumes/PL_SSD_2TB/tuesday/cube.h5",
        ])
        XCTAssertEqual(labels[0], "monday — PL_SSD_2TB")
        XCTAssertEqual(labels[1], "tuesday — PL_SSD_2TB")
    }

    func testItExtendsAsFarAsItMustAndNoFurther() {
        // Identical until two levels up.
        let labels = RecentDatasetLocation.labels(for: [
            "/Volumes/D/runs/january/session/cube.h5",
            "/Volumes/D/runs/february/session/cube.h5",
        ])
        XCTAssertEqual(labels[0], "january/session — D")
        XCTAssertEqual(labels[1], "february/session — D")
    }

    func testIdenticalPathsFallBackToTheFullPathRatherThanStayingAmbiguous() {
        // Cannot happen through `rememberOpenedDataset`, which de-duplicates on
        // exactly this string — but a label that is still ambiguous would be
        // worse than a long one, so the fallback is asserted rather than assumed.
        let labels = RecentDatasetLocation.labels(for: [nas, nas])
        XCTAssertEqual(labels[0], nas)
        XCTAssertEqual(labels[1], nas)
    }

    func testASingleEntryStillGetsALocation() {
        // The label is shown on every row, not only on ambiguous ones: a
        // subtitle that appears and disappears as other entries come and go is
        // harder to read than one that is always there.
        XCTAssertEqual(RecentDatasetLocation.labels(for: [nas]), ["eXtendedGROUPS"])
    }

    func testNoFileSystemAccessIsNeededForAnUnmountedVolume() {
        // Pure string work, deliberately: these volumes are routinely absent,
        // and asking the disk about a missing NAS while drawing the first screen
        // of the app would stall it.
        let label = RecentDatasetLocation.labels(
            for: ["/Volumes/A_Volume_That_Is_Not_Mounted/x/cube.h5"]
        )[0]
        XCTAssertEqual(label, "A_Volume_That_Is_Not_Mounted")
    }
}
