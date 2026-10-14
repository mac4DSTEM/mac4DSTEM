//
//  LazyAppStateTests.swift
//  UI audit 2026-10-13, finding 1 (tier 3): a dataset window's `AppState` is made on first use, once.
//
//  Mutation: `init` builds the state at once -> testNothingIsBuiltUntilAsked red.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class LazyAppStateTests: XCTestCase {

    func testNothingIsBuiltUntilAsked() {
        var made = 0
        let holder = LazyAppState { made += 1; return AppState() }
        XCTAssertEqual(made, 0, "a window whose content closure is evaluated again must not build a state graph")
        XCTAssertFalse(holder.isBuilt)
        _ = holder
        XCTAssertEqual(made, 0)
    }

    func testTheSameStateComesBackEveryTime() {
        var made = 0
        let holder = LazyAppState { made += 1; return AppState() }
        let first = holder.state
        let second = holder.state
        XCTAssertTrue(first === second)
        XCTAssertEqual(made, 1)
        XCTAssertTrue(holder.isBuilt)
    }
}
