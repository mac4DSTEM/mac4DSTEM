import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The bottom workspace (ADR 034): the Run tab's live-operation readout and
/// the tab-row default. `StatusBarMetricsTests` already pins the strip's own
/// elapsed/ETA line and its reserved width; this file pins the numbers the
/// Run tab adds on top of it, and the tab seam itself.
@MainActor
final class BottomWorkspaceTests: XCTestCase {

    // MARK: - unitsDone / totalUnits

    func testUnitsDoneAndTotalUnitsAreNilBeforeAnyOperationBegins() {
        let center = OperationCenter()
        XCTAssertNil(center.totalUnits)
        XCTAssertNil(center.unitsDone)
    }

    /// `begin` starts progress at zero (not nil — see `OperationCenter.begin`),
    /// so `unitsDone` is `0`, not absent, the instant a run starts; an
    /// `update` then advances it against the total the run declared.
    func testUnitsDoneTracksProgressAgainstTotalUnitsAfterBeginAndUpdate() {
        let center = OperationCenter()
        let token = center.begin(name: "Disk detection", totalUnits: 50)
        XCTAssertEqual(center.totalUnits, 50)
        XCTAssertEqual(center.unitsDone, 0, "begin starts progress at zero, not nil")

        center.update(token, progress: 0.4)
        XCTAssertEqual(center.unitsDone, 20)

        center.update(token, progress: 1.0)
        XCTAssertEqual(center.unitsDone, 50)
    }

    // MARK: - lastFinished

    func testLastFinishedIsAbsentUntilAnOperationFinishes() {
        let center = OperationCenter()
        XCTAssertNil(center.lastFinished)
    }

    /// Set by `finish`, and cleared by the NEXT `begin` — so the Run tab's
    /// idle "Last run" line never describes a run before the one before it.
    func testLastFinishedIsSetByFinishAndClearedByTheNextBegin() {
        let center = OperationCenter()
        let token = center.begin(name: "Virtual detector", totalUnits: 10)
        center.update(token, progress: 1.0)
        center.finish(token)

        XCTAssertEqual(center.lastFinished?.name, "Virtual detector")
        XCTAssertNotNil(center.lastFinished?.elapsed)
        XCTAssertGreaterThanOrEqual(center.lastFinished?.elapsed ?? -1, 0)

        _ = center.begin(name: "Disk detection", totalUnits: 5)
        XCTAssertNil(center.lastFinished, "a new run clears the previous one's readout")
    }

    /// A stale token (already superseded, or never current) must not finish
    /// the operation — and must not write a `lastFinished` for it either.
    func testAStaleTokenNeitherFinishesNorRecordsLastFinished() {
        let center = OperationCenter()
        let firstToken = center.begin(name: "First", totalUnits: 1)
        let secondToken = center.begin(name: "Second", totalUnits: 1)
        XCTAssertFalse(center.finish(firstToken), "the superseded token must not finish the current run")
        XCTAssertNil(center.lastFinished, "a refused finish must not publish a last-finished readout")

        center.finish(secondToken)
        XCTAssertEqual(center.lastFinished?.name, "Second")
    }

    // MARK: - bytesStreamed
    //
    // Split from the old `testBytesStreamedRoundTripsAndResetsWithTheOperation`
    // (Gate-B G6a): that test set `bytesStreamed` only AFTER `begin()`, so its
    // "begin starts with nothing streamed yet" assertion was vacuous — a
    // fresh `OperationCenter` is nil already, `begin` need not do anything for
    // it to pass. Each test below sets a non-nil value BEFORE the operation
    // that must clear it, so a mutation that deletes the clear maps to
    // exactly one red test.

    func testBeginClearsAStaleBytesStreamedFromTheOperationBeforeIt() {
        let center = OperationCenter()
        center.bytesStreamed = 4_000_000
        _ = center.begin(name: "Virtual detector", totalUnits: 10)
        XCTAssertNil(center.bytesStreamed, "begin must clear a stale streamed total left over from a previous run")
    }

    func testFinishClearsBytesStreamed() {
        let center = OperationCenter()
        let token = center.begin(name: "Virtual detector", totalUnits: 10)
        center.bytesStreamed = 4_000_000
        XCTAssertEqual(center.bytesStreamed, 4_000_000, "a plain write round-trips before finish clears it")
        center.finish(token)
        XCTAssertNil(center.bytesStreamed, "finishing clears the streamed total for the next run")
    }

    func testResetClearsBytesStreamed() {
        let center = OperationCenter()
        _ = center.begin(name: "Disk detection", totalUnits: 5)
        center.bytesStreamed = 900
        center.reset()
        XCTAssertNil(center.bytesStreamed, "a dataset-change reset clears it too")
    }

    /// G2 (Gate-B): `update(_:bytesStreamed:)` must apply the same
    /// current-operation-and-not-cancelled guard `update(_:progress:)`
    /// already uses, so Cancel freezes "Streamed" at the same instant it
    /// freezes progress — not one progress tick later.
    func testBytesStreamedUpdateIsIgnoredOnceTheTokenIsCancelled() {
        let center = OperationCenter()
        let token = center.begin(name: "Virtual detector", totalUnits: 10)

        XCTAssertTrue(center.update(token, bytesStreamed: 1_000))
        XCTAssertEqual(center.bytesStreamed, 1_000)

        _ = center.cancel()
        XCTAssertFalse(center.update(token, bytesStreamed: 2_000), "a cancelled token must not move bytesStreamed")
        XCTAssertEqual(center.bytesStreamed, 1_000, "the last accepted value survives the rejected update")
    }

    // MARK: - lastFinished outcome (G1)

    func testFinishRecordsACompletedOutcomeWhenTheTokenWasNeverCancelled() {
        let center = OperationCenter()
        let token = center.begin(name: "Virtual detector", totalUnits: 10)
        center.finish(token)
        XCTAssertEqual(center.lastFinished?.outcome, .completed)
    }

    func testFinishRecordsACancelledOutcomeWhenCancelWasCalledFirst() {
        let center = OperationCenter()
        let token = center.begin(name: "Virtual detector", totalUnits: 10)
        _ = center.cancel()
        center.finish(token)
        XCTAssertEqual(center.lastFinished?.outcome, .cancelled)
    }

    func testResetClearsLastFinished() {
        let center = OperationCenter()
        let token = center.begin(name: "Virtual detector", totalUnits: 10)
        center.finish(token)
        XCTAssertNotNil(center.lastFinished, "precondition: a finished run left a readout")
        center.reset()
        XCTAssertNil(center.lastFinished, "a dataset-change reset clears the last-run readout too")
    }

    // MARK: - The Run tab's "Last run" wording (G1)

    func testLastRunNamesThePlainDurationWhenTheRunCompleted() {
        XCTAssertEqual(
            OperationMetricsFormat.lastRun("Virtual detector", elapsed: 3, cancelled: false),
            "Virtual detector — 3 s")
    }

    func testLastRunNamesCancelledAfterTheDurationWhenTheRunWasCancelled() {
        XCTAssertEqual(
            OperationMetricsFormat.lastRun("Virtual detector", elapsed: 3, cancelled: true),
            "Virtual detector — cancelled after 3 s")
    }

    // MARK: - The two panes (owner, 2026-09-22 late, Xcode's debug area)

    func testOutputIsShownAndLineageHiddenByDefault() {
        let navigation = WorkspaceNavigation()
        XCTAssertTrue(navigation.showsOutputPane)
        XCTAssertFalse(navigation.showsLineagePane)
    }

    /// The two bar buttons never leave the area open and empty, or a pane
    /// chosen but unseen: hiding the last pane closes the area, showing a
    /// pane while the area is closed opens it, and opening the area with no
    /// pane chosen shows Output.
    func testHidingTheLastPaneClosesTheAreaAndShowingOneOpensIt() {
        let navigation = WorkspaceNavigation()
        navigation.showLogPane = true
        XCTAssertTrue(navigation.showLogPane)

        navigation.toggleProcessPane(.output)
        XCTAssertFalse(navigation.showsOutputPane)
        XCTAssertFalse(navigation.showLogPane, "hiding the last visible pane closes the area")

        navigation.toggleProcessPane(.lineage)
        XCTAssertTrue(navigation.showsLineagePane)
        XCTAssertTrue(navigation.showLogPane, "showing a pane while the area is closed opens it")

        navigation.toggleProcessPane(.lineage)
        XCTAssertFalse(navigation.showLogPane)
        navigation.showLogPane = true
        XCTAssertTrue(navigation.showsOutputPane, "opening the area with no pane chosen shows Output")
    }

    // MARK: - The status strip's memory/residency glance

    func testGlanceNamesResidentMemoryAboveOneGigabyteInGigabytes() {
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1433, residency: true), "1.4 GB · resident")
    }

    func testGlanceNamesStreamingMemoryBelowOneGigabyteInMegabytes() {
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 612, residency: false), "612 MB · streaming")
    }

    /// Pins the boundary choice: `residentMB >= 1024` switches to GB, not
    /// `>`, so a cube landing exactly on one gigabyte reads "1.0 GB" rather
    /// than "1024 MB".
    func testGlanceAtExactlyOneGigabyteUsesGBNotMB() {
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1024, residency: true), "1.0 GB · resident")
    }

    /// The GB-only formatter used to read a multi-terabyte cube as
    /// "2048.0 GB"; the TB branch (G6c) reads it in terabytes instead.
    func testGlanceNamesMultiTerabyteMemoryInTerabytes() {
        XCTAssertEqual(
            OperationMetricsFormat.glance(residentMB: 2 * 1024 * 1024, residency: true),
            "2.0 TB · resident")
    }
}
