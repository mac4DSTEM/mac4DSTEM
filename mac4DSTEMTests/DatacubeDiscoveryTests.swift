//
//  DatacubeDiscoveryTests.swift
//  The pure half of H5Reader's discovery judgement (Gate D 2026-09-04, the
//  rank-3 class): `describe` promotes a rank-3 dataset to one scan row, so
//  `is4D` alone can never refuse a node. What CAN is what the file says about
//  itself — the pinned upstream names the dim of a stack axis `_labels_`, and
//  this app's sidecar writer names the channel axis `RGBA` and stamps `rgba8`.
//  The reader reads those into a `DatacubeCandidate`; the rule itself needs
//  no HDF5, so it is pinned here. Which node wins on a real file is
//  `tools/datacube-discovery-test`.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class DatacubeDiscoveryTests: XCTestCase {

    private func candidate(rank: Int, lastAxis: String?, units: String? = nil,
                           legacySliceLabels: Bool = false) -> H5Reader.DatacubeCandidate {
        H5Reader.DatacubeCandidate(path: "/x/data", storedRank: rank, lastAxisName: lastAxis, units: units,
                                   legacySliceLabels: legacySliceLabels)
    }

    func testALegacySliceStackIsRefusedByItsStringTypedLastDim() {
        // The real calibrationData_bullseyeProbe.h5 probe_template: 1-based dims,
        // dim1/dim2 named Q_x/Q_y, and a string-typed dim3 with no name at all.
        let reason = H5Reader.datacubeRejection(of: candidate(rank: 3, lastAxis: "Q_y", legacySliceLabels: true))
        XCTAssertNotNil(reason, "a string-typed dim{rank} is upstream's own slice-label test (read_v0_12.py:365)")
        XCTAssertTrue(reason?.contains("legacy") ?? false, "the reason names the legacy layout")
        XCTAssertNil(H5Reader.datacubeRejection(of: candidate(rank: 3, lastAxis: "Q_y", legacySliceLabels: false)),
                     "the same dims with a numeric dim3 are not refused — a numeric vector is an axis")
    }

    func testAStackedEMDArrayIsRefusedWhateverItsRank() {
        for rank in [3, 4] {
            let reason = H5Reader.datacubeRejection(of: candidate(rank: rank, lastAxis: "_labels_"))
            XCTAssertNotNil(reason, "rank \(rank): a `_labels_` last axis is slices, not a detector")
            XCTAssertTrue(reason?.contains("stack") ?? false, "rank \(rank): the reason names the stack")
        }
    }

    func testAnRGBAResultMapIsRefusedByEitherOfItsTwoStamps() {
        XCTAssertNotNil(H5Reader.datacubeRejection(of: candidate(rank: 3, lastAxis: "RGBA")),
                        "the writer's `RGBA` dim name alone refuses")
        XCTAssertNotNil(H5Reader.datacubeRejection(of: candidate(rank: 3, lastAxis: nil, units: "rgba8")),
                        "the writer's `rgba8` units alone refuse")
    }

    func testAPlainDetectorAxisIsNotRefused() {
        for rank in [3, 4] {
            for name in ["Qy", "Q_y", "kx", "dim2", nil] {
                for units in ["pixel intensity", nil] {
                    XCTAssertNil(H5Reader.datacubeRejection(of: candidate(rank: rank, lastAxis: name, units: units)),
                                 "rank \(rank), last axis \(name ?? "unnamed"), units \(units ?? "none"): nothing here says not-a-cube")
                }
            }
        }
    }

    func testTheDescriptorKeepsTheStoredRankAndDefaultsToTheShape() {
        let promoted = DatasetDescriptor(filePath: "f", datasetPath: "/d", shape: [1, 5, 6, 5],
                                         dtypeDescription: "float32", chunkShape: nil, storedRank: 3)
        XCTAssertEqual(promoted.storedRank, 3, "a promoted rank-3 array remembers it was rank 3")
        XCTAssertTrue(promoted.is4D, "and is still a 4D descriptor to every consumer — the padding is the contract")
        let plain = DatasetDescriptor(filePath: "f", datasetPath: "/d", shape: [3, 4, 6, 5],
                                      dtypeDescription: "float32", chunkShape: nil)
        XCTAssertEqual(plain.storedRank, 4, "every existing call site gets the shape's own rank")
    }
}
