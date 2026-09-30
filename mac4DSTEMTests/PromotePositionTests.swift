//
//  PromotePositionTests.swift
//  S18 (b): Promote keeps the user's scan position.
//
//  BEFORE: promote reopened through `activate`, which resets the selection to
//  (0, 0) on every reopen, and promote never put it back — the rehearsal's
//  position was lost at exactly the moment the user moved from a crop to the
//  whole cube (open-items S5 "promote lands at (0,0)?", answered by reading
//  `activate` and confirmed by the first test below going red).
//
//  A scan crop is a subset of the source, so the same scene position in the
//  whole cube is the view position plus the crop's offset; a detector crop or
//  bin moves no scan index.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PromotePositionTests: XCTestCase {

    /// Demo cube [12, 12, 64, 64]: rows 2..<8, columns 3..<9.
    private var croppedSpec: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        return spec
    }

    /// Mutation it catches: promote passes no position (lands at the origin),
    /// or carries it without the crop offset.
    func testPromoteCarriesTheScanPositionIntoTheFullExtent() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        state.selectedScan = ScanPos(x: 4, y: 1)
        await state.loadCurrentPattern()
        let before = state.currentPattern
        XCTAssertNotNil(before, "precondition: a pattern at the rehearsal position")

        await state.promoteToFullExtent()

        XCTAssertTrue(state.loadedView.isFullExtent)
        XCTAssertEqual(state.selectedScan, ScanPos(x: 4 + 3, y: 1 + 2),
                       "view (4, 1) is source (7, 3) — not (0, 0), not the uncorrected (4, 1)")
    }

    /// The point of carrying the position: the pattern on screen is the same
    /// scene point. The demo generates patterns at SOURCE coordinates, so a
    /// crop is a subset and the two patterns must be identical pixels.
    /// Mutation it catches: the position is carried but the displayed pattern
    /// is left at the origin's (the reload is skipped).
    func testThePatternShownAfterPromoteIsTheSameScenePoint() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        state.selectedScan = ScanPos(x: 4, y: 1)
        await state.loadCurrentPattern()
        let before = try XCTUnwrap(state.currentPattern)

        await state.promoteToFullExtent()

        let after = try XCTUnwrap(state.currentPattern)
        XCTAssertEqual(after.pixels, before.pixels,
                       "the scan crop is a subset of the source: same scene point, same pattern")
        let origin = try await XCTUnwrap(state.datasetSession.fourD).pattern(ry: 0, rx: 0)
        XCTAssertNotEqual(after.pixels, origin.pixels,
                          "precondition of the comparison: the origin's pattern differs")
    }

    /// A view that moved no scan index promotes to the same position.
    /// Mutation it catches: the crop offset applied when there is no scan crop.
    func testADetectorOnlyViewPromotesToTheSamePosition() async {
        let state = AppState()
        await state.openDemoFixture(specification: LoadSpecification(detectorBin: 2))
        state.selectedScan = ScanPos(x: 5, y: 7)

        await state.promoteToFullExtent()

        XCTAssertTrue(state.loadedView.isFullExtent)
        XCTAssertEqual(state.selectedScan, ScanPos(x: 5, y: 7))
    }
}
