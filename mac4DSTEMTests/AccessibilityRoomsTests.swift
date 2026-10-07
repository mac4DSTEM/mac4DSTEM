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

    // MARK: - Y2 values spoken for symbols, abbreviations and prompts

    /// Mutation: drop the singular branch (-> "1 pixels"), or speak the unit as "px" -> red.
    func testPixelsAreSpokenInFullAndSingular() {
        XCTAssertEqual(RoomAccessibilityText.pixels(1), "1 pixel")
        XCTAssertEqual(RoomAccessibilityText.pixels(12), "12 pixels")
        XCTAssertEqual(RoomAccessibilityText.pixels(0), "0 pixels")
        XCTAssertEqual(RoomAccessibilityText.pixels(2.5), "2.5 pixels")
    }

    /// Mutation: speak the stored zero-based index (-> "peak 0") -> red.
    func testReferencePeakIsOneBasedLikeTheStepperShowsIt() {
        XCTAssertEqual(RoomAccessibilityText.referencePeak(zeroBasedIndex: 0), "peak 1")
        XCTAssertEqual(RoomAccessibilityText.referencePeak(zeroBasedIndex: 4), "peak 5")
        XCTAssertEqual(RoomAccessibilityText.upsampleFactor(16), "16 times")
    }

    /// Mutation: ignore `status` (the stage never reaches the header), or drop the expansion state -> red.
    func testSectionHeaderValueCarriesStatusThenExpansion() {
        XCTAssertEqual(RoomAccessibilityText.sectionHeaderValue(status: nil, expanded: true), "Expanded")
        XCTAssertEqual(RoomAccessibilityText.sectionHeaderValue(status: nil, expanded: false), "Collapsed")
        XCTAssertEqual(RoomAccessibilityText.sectionHeaderValue(status: "Complete", expanded: false), "Complete, Collapsed")
    }

    /// Mutation: swap the Current/Pending branches or let `complete` lose to `active` -> red.
    func testStageStatusPrefersCompleteOverCurrent() {
        XCTAssertEqual(RoomAccessibilityText.stageStatus(complete: true, active: true), "Complete")
        XCTAssertEqual(RoomAccessibilityText.stageStatus(complete: true, active: false), "Complete")
        XCTAssertEqual(RoomAccessibilityText.stageStatus(complete: false, active: true), "Current step")
        XCTAssertEqual(RoomAccessibilityText.stageStatus(complete: false, active: false), "Pending")
    }

    /// Mutation: ignore `isEmpty`, or leave the global value out of the sentence -> red.
    func testGlobalFallbackHintNamesTheValueInBothStates() {
        let empty = RoomAccessibilityText.globalFallbackHint(isEmpty: true, globalText: "0.300", unit: "per ångström")
        XCTAssertEqual(empty, "Empty: using the global value 0.300 per ångström")
        let set = RoomAccessibilityText.globalFallbackHint(isEmpty: false, globalText: "0.300", unit: "per ångström")
        XCTAssertEqual(set, "Clear the field to use the global value 0.300 per ångström")
    }

    /// Mutation: always return the raw text (a value spoken even when the display is already exact) -> red.
    func testExactProvenanceValueOnlyWhenTheDisplayRoundsIt() {
        let raw = "0.123456789"
        let shown = ProvenanceValueText.display(raw)
        XCTAssertNotEqual(shown, raw, "the fixture must be a value the display rounds")
        XCTAssertEqual(RoomAccessibilityText.exactValue(raw: raw, displayed: shown), raw)
        XCTAssertNil(RoomAccessibilityText.exactValue(raw: "friedel", displayed: ProvenanceValueText.display("friedel")))
    }

    /// Mutation: say "Shown" for every row, or never -> red.
    func testShownValueMarksOnlyTheCurrentProduct() {
        XCTAssertEqual(RoomAccessibilityText.shownValue(isCurrent: true), "Shown")
        XCTAssertEqual(RoomAccessibilityText.shownValue(isCurrent: false), "")
    }
}
