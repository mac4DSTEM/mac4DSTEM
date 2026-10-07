import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane F of the SwiftUI review fixes (2026-10-07): image-pane redraw cost,
/// the result-version salt, the scan navigator's normalised pixels and the
/// zoom actions. Each test pins a rule a pane body leans on.
@MainActor
final class SwiftUIReviewFTests: XCTestCase {

    // MARK: F1 - the origin-trim overlay is computed per input change, not per tick

    private func maps(validity: [Bool]?, width: Int = 5, height: Int = 4) -> OriginMaps {
        let n = width * height
        return OriginMaps(width: width, height: height, measuredX: nil, measuredY: nil,
                          fittedX: [Float](repeating: 16, count: n),
                          fittedY: [Float](repeating: 16, count: n),
                          originValidity: validity)
    }

    private func keptMask(excluding: [Int]) -> [Bool] {
        var kept = [Bool](repeating: true, count: 20)
        for i in excluding { kept[i] = false }
        return kept
    }

    func testTheOriginTrimCacheComputesOnceForUnchangedInputs() throws {
        let cache = OriginTrimOverlayCache()
        let origins = maps(validity: keptMask(excluding: [3, 7]))
        let first = try XCTUnwrap(cache.overlay(origins: origins, scanWidth: 5, scanHeight: 4))
        for _ in 0..<50 {   // a zoom drag's worth of body evaluations
            XCTAssertEqual(cache.overlay(origins: origins, scanWidth: 5, scanHeight: 4), first)
        }
        XCTAssertEqual(cache.computeCount, 1, "50 reads of unchanged inputs must not walk the mask again")
    }

    func testTheOriginTrimCacheRecomputesWhenTheMaskOrScanChanges() throws {
        let cache = OriginTrimOverlayCache()
        let a = maps(validity: keptMask(excluding: [3]))
        let b = maps(validity: keptMask(excluding: [3, 11]))
        XCTAssertEqual(try XCTUnwrap(cache.overlay(origins: a, scanWidth: 5, scanHeight: 4)).excluded, 1)
        XCTAssertEqual(try XCTUnwrap(cache.overlay(origins: b, scanWidth: 5, scanHeight: 4)).excluded, 2,
                       "a refit's new mask must replace the remembered overlay")
        XCTAssertEqual(cache.computeCount, 2)
        // Same mask, other scan shape: the origin maps no longer match the scan.
        XCTAssertNil(cache.overlay(origins: b, scanWidth: 4, scanHeight: 5))
        XCTAssertEqual(cache.computeCount, 3)
        // No origin maps at all.
        XCTAssertNil(cache.overlay(origins: nil, scanWidth: 5, scanHeight: 4))
        XCTAssertEqual(cache.computeCount, 4)
    }

    func testTheCachedOverlayEqualsTheCoreOverlay() {
        let origins = maps(validity: keptMask(excluding: [0, 1, 2, 19]))
        XCTAssertEqual(
            OriginTrimOverlayCache().overlay(origins: origins, scanWidth: 5, scanHeight: 4),
            FitOverlays.originTrimOverlay(origins: origins, scanWidth: 5, scanHeight: 4))
    }

    private func preparedState(validity: [Bool]) -> AppState {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/f1.h5", datasetPath: "/data",
            shape: [4, 5, 32, 32], dtypeDescription: "float32", chunkShape: nil)
        state.navigation.workspaceArea = .prepare
        state.showFitOverlay = true
        state.calibrationSession.calibration.origin = maps(validity: validity)
        return state
    }

    func testAppStateServesTheSameOverlayAsFitOverlaysAndComputesItOnce() throws {
        let state = preparedState(validity: keptMask(excluding: [4, 5]))
        let expected = try XCTUnwrap(state.fitOverlays.originTrim)
        for _ in 0..<20 { XCTAssertEqual(state.originTrimOverlay, expected) }
        XCTAssertEqual(state.originTrimCache.computeCount, 1)

        // The gate is unchanged: toggle off or leave Prepare and nothing is drawn.
        state.showFitOverlay = false
        XCTAssertNil(state.originTrimOverlay)
        XCTAssertNil(state.fitOverlays.originTrim)
        state.showFitOverlay = true
        state.navigation.workspaceArea = .map
        XCTAssertNil(state.originTrimOverlay)
        XCTAssertEqual(state.originTrimCache.computeCount, 1, "a closed gate never reaches the cache")

        // A refit replaces the mask: the next read follows it.
        state.navigation.workspaceArea = .prepare
        state.calibrationSession.calibration.origin = maps(validity: keptMask(excluding: [4, 5, 6]))
        XCTAssertEqual(try XCTUnwrap(state.originTrimOverlay).excluded, 3)
        XCTAssertEqual(state.originTrimCache.computeCount, 2)
    }

    func testTheHighlightOutlineIsEmptyAndFreeWithoutAClassificationRun() {
        let state = AppState()
        let selection = PrecipitateTableSelection()
        selection.select([1, 2], of: UUID())
        XCTAssertTrue(state.cachedPrecipitateHighlightOutline(for: selection).isEmpty)
        XCTAssertEqual(state.highlightOutlineComputeCount, 0)
    }

    func testTheLastValueCacheKeepsOneEntryPerKey() {
        let cache = LastValueCache<Set<Int>, Int>()
        var runs = 0
        func get(_ key: Set<Int>) -> Int { cache.value(for: key) { runs += 1; return key.reduce(0, +) } }
        XCTAssertEqual(get([1, 2]), 3)
        XCTAssertEqual(get([1, 2]), 3)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(get([4]), 4)
        XCTAssertEqual(get([1, 2]), 3, "the old key was replaced, so it recomputes")
        XCTAssertEqual(runs, 3)
        XCTAssertEqual(cache.computeCount, 3)
    }
}
