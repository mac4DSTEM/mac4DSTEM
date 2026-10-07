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

    // MARK: F2 - the aperture overlay compares on its values, not its closures

    private func overlay(_ aperture: Aperture = Aperture(centerX: 64, centerY: 64, inner: 5, outer: 20),
                         shape: VirtualShapeMode = .annulus,
                         width: Int = 128, height: Int = 128,
                         onEdited: @escaping (Aperture) -> Void = { _ in }) -> ApertureOverlay {
        ApertureOverlay(aperture: aperture, shape: shape, patternWidth: width, patternHeight: height,
                        onEdited: onEdited, onCommit: {})
    }

    func testTheApertureOverlayIgnoresFreshClosuresButNotItsValues() {
        var sink = 0
        // Two separately built closures: the pane builds new ones every body.
        XCTAssertEqual(overlay(onEdited: { _ in sink += 1 }), overlay(onEdited: { _ in sink += 2 }))
        let base = Aperture(centerX: 64, centerY: 64, inner: 5, outer: 20)
        for changed in [Aperture(centerX: 65, centerY: 64, inner: 5, outer: 20),
                        Aperture(centerX: 64, centerY: 65, inner: 5, outer: 20),
                        Aperture(centerX: 64, centerY: 64, inner: 6, outer: 20),
                        Aperture(centerX: 64, centerY: 64, inner: 5, outer: 21)] {
            XCTAssertNotEqual(overlay(base), overlay(changed), "\(changed) must redraw the overlay")
        }
        XCTAssertNotEqual(overlay(shape: .annulus), overlay(shape: .circle))
        XCTAssertNotEqual(overlay(width: 128), overlay(width: 256))
        XCTAssertNotEqual(overlay(height: 128), overlay(height: 256))
        XCTAssertEqual(sink, 0)
    }

    // MARK: F3 - the region reference and the result never share a version

    func testTheRegionReferenceAndTheResultNeverShareAVersion() {
        for counter in [0, 1, 2, 7, 1_000, 65_535] {
            let result = AppState.displayedResultVersion(
                regionReference: false, scanNavigation: counter, result: counter)
            let reference = AppState.displayedResultVersion(
                regionReference: true, scanNavigation: counter, result: counter)
            XCTAssertNotEqual(result, reference,
                              "equal counters (\(counter)) must not let the viewer skip the texture upload")
            // The quality-field mode adds 0x4000_0000 to whichever it shows.
            XCTAssertNotEqual(result &+ 0x4000_0000, reference &+ 0x4000_0000)
        }
    }

    func testTheDisplayedVersionStillFollowsItsOwnCounter() {
        XCTAssertEqual(AppState.displayedResultVersion(regionReference: false, scanNavigation: 9, result: 4), 4)
        let a = AppState.displayedResultVersion(regionReference: true, scanNavigation: 9, result: 4)
        let b = AppState.displayedResultVersion(regionReference: true, scanNavigation: 10, result: 4)
        XCTAssertNotEqual(a, b, "a new region-reference image still bumps the version")
    }
}
