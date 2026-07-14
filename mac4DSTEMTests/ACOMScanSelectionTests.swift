import XCTest
@testable import mac4DSTEM

final class ACOMScanSelectionTests: XCTestCase {
    func testPreviewBoundsWorkAndExpandsCoarseBlocks() {
        let selection = ACOMScanSelection.preview(maxDimension: 4)
        XCTAssertEqual(
            selection.sourceIndices(width: 10, height: 6),
            [0, 3, 6, 9, 30, 33, 36, 39]
        )

        var map = OrientationMap(width: 10, height: 6)
        for source in selection.sourceIndices(width: 10, height: 6) {
            map.results[source] = OrientationResult(
                templateIndex: source,
                euler: .zero,
                score: Float(source + 1),
                secondScore: 0,
                phaseID: 0
            )
        }
        let expanded = selection.expandedPreview(map)
        XCTAssertEqual(expanded[2, 2].templateIndex, 0)
        XCTAssertEqual(expanded[5, 1].templateIndex, 3)
        XCTAssertEqual(expanded[9, 5].templateIndex, 39)
    }

    func testSelectedRegionClipsAtDatasetEdges() {
        let selection = ACOMScanSelection.square(centerX: 0, centerY: 1, radius: 2)
        XCTAssertEqual(
            selection.sourceIndices(width: 5, height: 4),
            [0, 1, 2, 5, 6, 7, 10, 11, 12, 15, 16, 17]
        )
        XCTAssertEqual(selection.positionCount(width: 5, height: 4), 12)
    }

    func testQualityPresetsExposeIncreasingTemplateBudgets() {
        XCTAssertEqual(ACOMQualityPreset.fast.templateCount, 96)
        XCTAssertEqual(ACOMQualityPreset.balanced.templateCount, 200)
        XCTAssertEqual(ACOMQualityPreset.best.templateCount, 400)
    }
}
