import XCTest
@testable import mac4DSTEM

/// Pins the promote control's wiring (v2 S3): `promoteToFullExtent()` reopens
/// the SAME source at `.fullExtent` — removing the specification, never
/// re-deriving from reduced data — and refuses to run when there is nothing to
/// promote.
///
/// Driven through the demo fixture opened at a scan crop, because the property
/// worth pinning is the path the app takes (`activate` with the identity
/// specification), not the pure fact that `.fullExtent.isFullExtent` is true —
/// the S1 lesson about testing the locator and not the call site.
@MainActor
final class PromoteToFullExtentTests: XCTestCase {

    private var croppedSpec: LoadSpecification {
        var spec = LoadSpecification()
        // The demo cube is [12, 12, 64, 64]; rows 2..<8, columns 3..<9.
        spec.scanCrop = AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6)
        return spec
    }

    func testPromoteReopensTheWholeSourceNotTheRehearsedView() async {
        let state = AppState()
        await state.openDemoFixture(specification: croppedSpec)
        XCTAssertFalse(state.loadedView.isFullExtent,
                       "precondition: the rehearsal view is reduced")
        XCTAssertEqual(state.descriptor?.ry, 6, "precondition: the crop loaded")

        await state.promoteToFullExtent()

        XCTAssertTrue(state.loadedView.isFullExtent,
                      "Promotion must remove the specification entirely")
        XCTAssertEqual(state.descriptor?.shape, state.datasets.first?.shape,
                       "The promoted view must be the source's own extent")
        XCTAssertTrue(state.hasDataset, "Promotion must end with a usable dataset")
        // The postconditions the first draft left unpinned (Gate A sweep):
        // without these, deleting promote's trailing finishDatasetLoading()
        // (loading card parked forever) or its runCurrentAnalysis() call
        // (empty result panes) left this suite green.
        XCTAssertFalse(state.isLoadingDataset,
                       "A finished promote must dismiss the loading card")
        XCTAssertNotNil(state.resultImage,
                        "The whole-cube pass must have run against the promoted view")
    }

    func testPromoteOnAFullExtentViewIsANoOp() async {
        let state = AppState()
        await state.openDemoFixture()
        // `hasDataset` too, not just `isFullExtent`: a fresh LoadedView is
        // already full-extent, so on an AppState whose demo open silently
        // failed the isFullExtent precondition still holds and this test
        // passes without the scenario it names ever existing (Gate A sweep).
        XCTAssertTrue(state.hasDataset, "precondition: the demo actually opened")
        XCTAssertTrue(state.loadedView.isFullExtent, "precondition")
        state.selectedScan = ScanPos(x: 3, y: 4)

        await state.promoteToFullExtent()

        // `activate` resets the selection to the origin on every reopen, so an
        // untouched selection is evidence the guard refused. The descriptor id
        // is NOT usable here: breaking the guard showed a full-extent
        // `LoadView` carries the source descriptor through unchanged, id and
        // all — the first draft of this test stayed green with the guard
        // deleted, which is exactly the assertion class this repo bans.
        XCTAssertEqual(state.selectedScan, ScanPos(x: 3, y: 4),
                       "Nothing to promote — the whole file is already loaded")
    }
}
