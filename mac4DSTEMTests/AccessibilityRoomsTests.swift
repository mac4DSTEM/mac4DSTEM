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

    // MARK: - Y3 one-phrase hints taken from long tooltips

    /// Mutation: return the whole tooltip, or keep the closing period -> red.
    func testBriefHintIsTheFirstSentenceWithoutItsPeriod() {
        XCTAssertEqual(RoomAccessibilityText.briefHint(
            from: "Sets the probe radius to the ring's outer edge. Nothing changes unless you click."),
                       "Sets the probe radius to the ring's outer edge")
        XCTAssertEqual(RoomAccessibilityText.briefHint(
            from: "Fills Defocus and the astigmatism from the parallax fit: defocus is minus the fit's C1."),
                       "Fills Defocus and the astigmatism from the parallax fit")
        XCTAssertEqual(RoomAccessibilityText.briefHint(from: "Compute Mean / Max; also computed by origin calibration."),
                       "Compute Mean / Max")
        XCTAssertEqual(RoomAccessibilityText.briefHint(from: "Remove saved result"), "Remove saved result")
        XCTAssertEqual(RoomAccessibilityText.briefHint(from: "Runs the reference engine."), "Runs the reference engine")
    }

    /// Mutation: drop the nil guard's empty result (a button without a tooltip would repeat its own title), or raise the
    /// limit so a long unbroken tooltip is spoken whole -> red.
    func testBriefHintIsEmptyWithoutATooltipOrWhenTheFirstSentenceIsLong() {
        XCTAssertEqual(RoomAccessibilityText.briefHint(from: nil), "")
        let long = String(repeating: "word ", count: 30) + "end."
        XCTAssertGreaterThan(long.count, RoomAccessibilityText.briefHintLimit)
        XCTAssertEqual(RoomAccessibilityText.briefHint(from: long), "")
        // The real Use Parallax Fit tooltip has no early sentence break; its explicit hint is passed instead.
        XCTAssertEqual(RoomAccessibilityText.briefHint(from: "  Short one.  "), "Short one")
    }

    // MARK: - Y4 announcements

    /// Mutation: announce the radius unrounded or in "px" -> red.
    func testRingProbeAnnouncementSpeaksTheRoundedRadiusInFull() {
        XCTAssertEqual(RoomAccessibilityText.ringProbe(outerRadius: 11.6), "Ring-shaped probe: its outer edge is at 12 pixels")
        XCTAssertEqual(RoomAccessibilityText.ringProbe(outerRadius: 1.2), "Ring-shaped probe: its outer edge is at 1 pixel")
    }

    /// Mutation: drop the stage title from the sentence -> red.
    func testStageCompleteAnnouncementNamesTheStage() {
        XCTAssertEqual(RoomAccessibilityText.stageComplete(title: "Align Bright-Field Images"), "Align Bright-Field Images complete")
    }

    /// Mutation: report a caption for an empty draft or for a valid one (-> red), or never report one.
    func testMalformedCaptionOnlyForANonEmptyUnparsableDraft() {
        let caption = RoomAccessibilityText.zoneAxisMalformed
        XCTAssertNil(RoomAccessibilityText.malformedCaption(draft: "", parses: false, caption: caption))
        XCTAssertNil(RoomAccessibilityText.malformedCaption(draft: "0 1 0", parses: true, caption: caption))
        XCTAssertEqual(RoomAccessibilityText.malformedCaption(draft: "0 1", parses: false, caption: caption), caption)
        // The real parsers agree with the rule.
        XCTAssertNotNil(PhaseMappingSlot.parseZoneAxis("0 1 0"))
        XCTAssertNil(PhaseMappingSlot.parseZoneAxis("0 1"))
    }

    /// The captions are drawn from these constants now: the on-screen wording must not have moved.
    /// Mutation: edit either constant -> red.
    func testPhaseCaptionsKeepTheirOnScreenWording() {
        XCTAssertEqual(RoomAccessibilityText.zoneAxisMalformed, "A zone axis is three integers, like 0 1 0.")
        XCTAssertEqual(RoomAccessibilityText.relationshipMalformed,
                       "A relationship is pairs like (002) ∥ (200); planes in parentheses, directions in square brackets.")
    }
}
