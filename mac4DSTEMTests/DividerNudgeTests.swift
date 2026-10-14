//
//  DividerNudgeTests.swift
//  UI audit 2026-10-14, G4: the two dividers (the science panes' and the status strip) move from the keyboard and
//  from VoiceOver by the same arithmetic. Pure functions; the views only call them.
//
//  Mutations these were broken against (each must turn a test red):
//   1. `paneFraction` drops the clamp                                            -> testPaneNudgeStaysInsideTheFloor
//   2. `processFraction` treats "taller" as "shorter" (sign flipped)             -> testStripTallerOpensAndGrows
//   3. a shut area ignores `last` and stays shut on "taller"                     -> testStripTallerOpensAndGrows
//   4. an open area is never allowed to close on "shorter"                       -> testStripShorterClosesAtTheFloorAndStaysShut
//

import XCTest
@testable import mac4DSTEM

final class DividerNudgeTests: XCTestCase {

    func testPaneNudgeMovesByTheStepAndStaysInsideTheFloor() {
        let usable: CGFloat = 1000, smallest: CGFloat = 0.2
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.5, by: DividerNudge.step, usable: usable, smallest: smallest),
                       0.5 + DividerNudge.step / usable, accuracy: 1e-9)
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.5, by: -DividerNudge.step, usable: usable, smallest: smallest),
                       0.5 - DividerNudge.step / usable, accuracy: 1e-9)
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.8, by: 1000, usable: usable, smallest: smallest), 0.8,
                       accuracy: 1e-9, "the trailing pane keeps its floor")
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.2, by: -1000, usable: usable, smallest: smallest), 0.2,
                       accuracy: 1e-9, "the leading pane keeps its floor")
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.05, by: 0, usable: usable, smallest: smallest), 0.2,
                       accuracy: 1e-9, "a stored fraction outside the floor is brought inside it")
        XCTAssertEqual(DividerNudge.paneFraction(from: 0.5, by: 24, usable: 0, smallest: smallest), 0.5,
                       "no width, no move")
    }

    func testPaneNudgeStaysInsideTheFloor() {
        // Many presses never leave [smallest, 1 - smallest].
        var fraction: CGFloat = 0.5
        for _ in 0..<200 {
            fraction = DividerNudge.paneFraction(from: fraction, by: DividerNudge.step, usable: 600, smallest: 0.3)
        }
        XCTAssertEqual(fraction, 0.7, accuracy: 1e-9)
    }

    func testStripTallerOpensAndGrows() {
        let available: CGFloat = 800
        let last = LayoutPolicy.processAreaIdealFraction
        XCTAssertEqual(DividerNudge.processFraction(from: 0, taller: true, last: last, available: available), last,
                       "a shut area opens to where it was last open")
        let open = 0.3
        let taller = DividerNudge.processFraction(from: open, taller: true, last: last, available: available)
        XCTAssertGreaterThan(taller, open, "taller grows the area")
        XCTAssertEqual(taller, Double((CGFloat(open) * available + DividerNudge.step) / available), accuracy: 1e-9)
    }

    func testStripShorterClosesAtTheFloorAndStaysShut() throws {
        let available: CGFloat = 800
        let last = LayoutPolicy.processAreaIdealFraction
        let open = 0.3
        let shorter = DividerNudge.processFraction(from: open, taller: false, last: last, available: available)
        XCTAssertLessThan(shorter, open)
        XCTAssertGreaterThan(shorter, 0)
        // Held down it shrinks to the floor (140 pt), the next press closes it, and a further press leaves it shut.
        var fraction = open
        var floorHeight: CGFloat?
        for _ in 0..<100 {
            fraction = DividerNudge.processFraction(from: fraction, taller: false, last: last, available: available)
            if fraction > 0 { floorHeight = ProcessAreaLayout.height(fraction: fraction, available: available) }
        }
        XCTAssertEqual(fraction, 0, "a mouse closes it by dragging past the floor; the keyboard closes it from the floor")
        XCTAssertEqual(try XCTUnwrap(floorHeight), LayoutPolicy.processAreaMinimumHeight, accuracy: 0.001,
                       "the last open height is the floor")
        XCTAssertEqual(DividerNudge.processFraction(from: 0, taller: false, last: last, available: available), 0)
        // And held up, it ends at the column's full height, no more.
        var up = open
        for _ in 0..<200 { up = DividerNudge.processFraction(from: up, taller: true, last: last, available: available) }
        XCTAssertEqual(up, 1, accuracy: 1e-9)
    }
}
