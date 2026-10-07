import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane Y of the 2026-10-07 SwiftUI review fixes: the pure helpers behind the room audit's no-new-surface accessibility
/// fixes (docs/archive/v5/a11y-rooms-apple-docs-audit-2026-10-07.md). The modifiers themselves are checked by a drive.
@MainActor
final class AccessibilityRoomsTests: XCTestCase {

    // MARK: - Y1 (7.4) the run graph's spoken summary

    private func lineage(runs: [(String, [String: String])]) -> SessionLineage {
        var lineage = SessionLineage()
        for (kind, parameters) in runs {
            lineage.recordRun(kind: kind, parameters: parameters, frame: SessionLineage.Frame())
        }
        return lineage
    }

    /// Mutation: drop the `stale` clause, or count `.branch` nodes as stale (-> "6 steps, 1 stale" without the branches
    /// clause, or the wrong numbers) -> red.
    func testRunGraphSummaryCountsStepsStaleAndBranches() {
        let branched = lineage(runs: [
            ("calibration_origin", ["method": "friedel"]), ("calibration_ellipse", ["a_px": "1.0"]),
            ("calibration_q", ["q_pixel_size": "0.01"]),
            ("disk_detection", ["floor": "0.50", "spacing": "20"]), ("strain", ["basis": "consensus"]),
            ("disk_detection", ["floor": "0.15", "spacing": "20"]),
        ])
        XCTAssertEqual(LineageGraphModel(lineage: branched).accessibilitySummary,
                       "6 steps, 2 on another branch")
        let stale = LineageGraphModel(lineage: branched, productKind: "bragg_vector_map", productStep: "s4")
        XCTAssertEqual(stale.accessibilitySummary, "6 steps, 1 stale, 2 on another branch")
    }

    /// Mutation: always pluralise ("1 steps") -> red.
    func testRunGraphSummarySingularAndEmpty() {
        let one = lineage(runs: [("calibration_origin", ["method": "friedel"])])
        XCTAssertEqual(LineageGraphModel(lineage: one).accessibilitySummary, "1 step")
        XCTAssertEqual(LineageGraphModel(lineage: SessionLineage()).accessibilitySummary, "0 steps")
    }
}
