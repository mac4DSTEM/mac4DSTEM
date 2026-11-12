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

    func testTheScaleIsAboutAThousandPixels() {
        XCTAssertEqual(AppState.agentScanMapScale(width: 400, height: 400), 2)
        XCTAssertEqual(AppState.agentScanMapScale(width: 64, height: 48), 16)
        XCTAssertEqual(AppState.agentScanMapScale(width: 2048, height: 10), 1)
    }
}
