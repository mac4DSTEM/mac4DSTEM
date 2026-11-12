//
//  AgentDoorScanMapTests.swift
//  The scan map an agent picks positions on (App/AgentDoor/AgentDoorScanMap.swift, issue #206): scan position (x, y) is the
//  block whose top-left pixel is (x·k, y·k), and the selected position is outlined around its block.
//

import XCTest
@testable import mac4DSTEM

final class AgentDoorScanMapTests: XCTestCase {

    /// A 3 × 2 map whose red channel is 10·x + y: every picture pixel must carry its own position's value.
    /// Mutation: rows and columns swapped, or the block size off by one - red.
    func testEachPositionIsAKByKBlockAtXKYK() {
        let width = 3, height = 2, k = 4
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width { rgba[(y * width + x) * 4] = UInt8(10 * x + y) } }
        let picture = AppState.agentScanMapPicture(rgba, width: width, height: height, scale: k, outline: nil)
        XCTAssertEqual(picture.count, width * k * height * k * 4)
        for py in 0..<(height * k) {
            for px in 0..<(width * k) {
                XCTAssertEqual(picture[(py * width * k + px) * 4], UInt8(10 * (px / k) + py / k), "pixel \(px), \(py)")
            }
        }
    }

    func testTheSelectedPositionIsOutlinedAroundItsBlockAndNotOverIt() {
        let width = 4, height = 4, k = 3
        let rgba = [UInt8](repeating: 0, count: width * height * 4)
        let picture = AppState.agentScanMapPicture(rgba, width: width, height: height, scale: k, outline: (x: 1, y: 2))
        func isMagenta(_ px: Int, _ py: Int) -> Bool {
            let i = (py * width * k + px) * 4
            return picture[i] == 255 && picture[i + 1] == 0 && picture[i + 2] == 255
        }
        // The block of (1, 2) is pixels 3...5 × 6...8; its frame is 2...6 × 5...9.
        XCTAssertTrue(isMagenta(2, 5))
        XCTAssertTrue(isMagenta(6, 9))
        XCTAssertTrue(isMagenta(4, 5))
        XCTAssertFalse(isMagenta(4, 7), "the block itself keeps its colour")
        XCTAssertFalse(isMagenta(0, 0))
    }

    /// Issue #237: the frame is easy to find. Mutation: back to one pixel, no black edge, or no outer frame - red.
    func testTheFrameIsThickEdgedAndRepeatedFurtherOut() {
        let width = 40, height = 40, k = 2
        let rgba = [UInt8](repeating: 128, count: width * height * 4)   // a grey map, so the black edge shows
        let picture = AppState.agentScanMapPicture(rgba, width: width, height: height, scale: k, outline: (x: 20, y: 20))
        func colour(_ px: Int, _ py: Int) -> [UInt8] {
            let i = (py * width * k + px) * 4
            return Array(picture[i..<(i + 3)])
        }
        // The block of (20, 20) is pixels 40...41; frames at 1 and 2 pixels out, black at 3; the outer frame at max(8, 2k) = 8.
        XCTAssertEqual(colour(39, 40), [255, 0, 255])
        XCTAssertEqual(colour(38, 40), [255, 0, 255], "two pixels thick")
        XCTAssertEqual(colour(40, 37), [0, 0, 0], "edged in black")
        XCTAssertEqual(colour(32, 40), [255, 0, 255], "the outer frame")
        XCTAssertEqual(colour(40, 40), [128, 128, 128], "the block keeps its colour")
    }

    func testTheScaleIsAboutAThousandPixels() {
        XCTAssertEqual(AppState.agentScanMapScale(width: 400, height: 400), 2)
        XCTAssertEqual(AppState.agentScanMapScale(width: 64, height: 48), 16)
        XCTAssertEqual(AppState.agentScanMapScale(width: 2048, height: 10), 1)
    }
}
