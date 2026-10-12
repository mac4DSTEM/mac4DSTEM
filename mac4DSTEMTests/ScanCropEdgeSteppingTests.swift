//
//  ScanCropEdgeSteppingTests.swift
//  The VoiceOver / keyboard route to the scan crop (ReductionSections, 2026-10-12
//  SwiftUI review residual). Each action moves one edge by one step through the
//  drag's own model call, so these pin the step, the clamp, the minimum and the
//  full-extent nil.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class ScanCropEdgeSteppingTests: XCTestCase {

    // 60 x 40 scan (ry 60, rx 40): non-square, so a y/x swap cannot pass.
    // Steps: 60/20 = 3 rows, 40/20 = 2 columns.
    private let source = DatasetDescriptor(
        filePath: "/tmp/source.h5", datasetPath: "/data",
        shape: [60, 40, 128, 96], dtypeDescription: "uint16", chunkShape: nil
    )

    private func moved(_ crop: AxisCrop?, _ move: ScanCropEdgeStepping.Move,
                       strideY: Int = 1, strideX: Int = 1) -> AxisCrop? {
        ScanCropEdgeStepping.moved(crop, move: move, source: source,
                                   strideY: strideY, strideX: strideX)
    }

    // MARK: - One step from the whole scan

    func testTopDownFromTheWholeScanMovesTheTopEdgeByOneStep() {
        XCTAssertEqual(moved(nil, .topDown),
                       AxisCrop(yOffset: 3, xOffset: 0, height: 57, width: 40))
    }

    func testBottomUpFromTheWholeScanMovesTheBottomEdgeByOneStep() {
        XCTAssertEqual(moved(nil, .bottomUp),
                       AxisCrop(yOffset: 0, xOffset: 0, height: 57, width: 40))
    }

    func testLeftRightAndRightLeftUseTheColumnStep() {
        XCTAssertEqual(moved(nil, .leftRight),
                       AxisCrop(yOffset: 0, xOffset: 2, height: 60, width: 38))
        XCTAssertEqual(moved(nil, .rightLeft),
                       AxisCrop(yOffset: 0, xOffset: 0, height: 60, width: 38))
    }

    // MARK: - Edges that cannot move past the scan

    func testMovingAnEdgeOutwardPastTheScanEdgeIsTheWholeScanNotACrop() {
        // Outward from the whole scan is nothing: the drag's own "covers everything is no crop" rule.
        XCTAssertNil(moved(nil, .topUp))
        XCTAssertNil(moved(nil, .bottomDown))
        XCTAssertNil(moved(nil, .leftLeft))
        XCTAssertNil(moved(nil, .rightRight))
    }

    func testAnEdgeStopsAtTheScanEdgeWhenTheStepWouldOvershoot() {
        // Top at 2 rows, step 3: clamps to 0, and with the other edges whole that is the whole scan.
        XCTAssertNil(moved(AxisCrop(yOffset: 2, xOffset: 0, height: 58, width: 40), .topUp))
        // Bottom at 58 of 60 rows, step 3: clamps to 60, the whole scan.
        XCTAssertNil(moved(AxisCrop(yOffset: 0, xOffset: 0, height: 58, width: 40), .bottomDown))
    }

    // MARK: - The minimum: one preview sample (stride) per edge, as a drag allows

    func testAnEdgeNeverClosesBelowOneStrideOfScanPositions() {
        // Height 6 at stride 3: top down one step leaves height 3, not 0; a second step stays at 3.
        let crop = AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 40)
        let once = moved(crop, .topDown, strideY: 3)
        XCTAssertEqual(once, AxisCrop(yOffset: 3, xOffset: 0, height: 3, width: 40))
        XCTAssertEqual(moved(once, .topDown, strideY: 3), once)
    }

    func testBottomUpStopsAtTheMinimumHeight() {
        let crop = AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 40)
        XCTAssertEqual(moved(crop, .bottomUp, strideY: 3),
                       AxisCrop(yOffset: 0, xOffset: 0, height: 3, width: 40))
    }

    func testAnEdgeAlreadyPastTheMinimumIsNotMovedTheWrongWay() {
        // A sub-stride sliver at the bottom of the scan: "bottom up" must not push the bottom DOWN.
        let sliver = AxisCrop(yOffset: 58, xOffset: 0, height: 2, width: 40)
        XCTAssertEqual(moved(sliver, .bottomUp, strideY: 3), sliver)
    }

    // MARK: - Steps are a twentieth of the scan, at least one position

    func testTheStepIsOneTwentiethOfTheScanDimensionAtLeastOne() {
        // A 10-row scan steps 1 row (10/20 rounds to 0, floored at 1).
        let tiny = DatasetDescriptor(
            filePath: "/tmp/tiny.h5", datasetPath: "/data",
            shape: [10, 10, 8, 8], dtypeDescription: "uint16", chunkShape: nil
        )
        XCTAssertEqual(
            ScanCropEdgeStepping.moved(nil, move: .topDown, source: tiny, strideY: 1, strideX: 1),
            AxisCrop(yOffset: 1, xOffset: 0, height: 9, width: 10)
        )
    }

    // MARK: - The spoken value

    func testTheSpokenValueNamesTheInclusiveScanRange() {
        XCTAssertEqual(
            ScanCropEdgeStepping.spokenValue(AxisCrop(yOffset: 10, xOffset: 5, height: 86, width: 123)),
            "Crop x 5–127, y 10–95"
        )
    }

    func testTheSpokenValueOfTheWholeScanSaysSo() {
        XCTAssertEqual(ScanCropEdgeStepping.spokenValue(nil), "Crop: whole scan")
    }

    // MARK: - Every move has a distinct name

    func testEveryMoveHasADistinctName() {
        let names = ScanCropEdgeStepping.Move.allCases.map(\.name)
        XCTAssertEqual(Set(names).count, ScanCropEdgeStepping.Move.allCases.count)
    }
}
