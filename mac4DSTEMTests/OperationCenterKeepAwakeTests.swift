//
//  OperationCenterKeepAwakeTests.swift
//  Finding B (adversarial review, 2026-09-21): `OperationCenter.isBusy`'s
//  `didSet` (`Session/OperationCenter.swift`) begins/ends the keep-awake
//  assertion, guarded by `oldValue != isBusy` — the injectable
//  `beginKeepAwake`/`endKeepAwake` closures exist precisely so this is
//  testable, the same shape as `ReplayRunTests`' `ActivityCounter`, but
//  nothing exercised it. Pins: begin/end fire exactly once per busy edge, not
//  on a repeated value; the SAME token issued by begin is the one handed to
//  end; `reset()` while busy still ends the token; and the
//  `begin(name:totalUnits:)`/`finish` cycle stays balanced.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class OperationCenterKeepAwakeTests: XCTestCase {

    /// Same shape as `ReplayRunTests.ActivityCounter`: a single shared token
    /// object, so `endKeepAwake` can assert identity against exactly what
    /// `beginKeepAwake` issued.
    private final class ActivityCounter {
        var begins = 0
        var ends = 0
        let token = NSObject()
    }

    private func makeCenter(_ counter: ActivityCounter) -> OperationCenter {
        OperationCenter(
            beginKeepAwake: { counter.begins += 1; return counter.token },
            endKeepAwake: { ended in
                XCTAssertTrue(ended === counter.token,
                              "must end the SAME token begin issued")
                counter.ends += 1
            }
        )
    }

    // MARK: 1 — begin fires once per busy edge

    func testBeginKeepAwakeFiresOnceWhenBusyBecomesTrueNotOnARepeatedTrue() {
        let counter = ActivityCounter()
        let center = makeCenter(counter)

        center.setBusy(true)
        XCTAssertEqual(counter.begins, 1)
        XCTAssertEqual(counter.ends, 0)

        center.setBusy(true)
        XCTAssertEqual(counter.begins, 1, "a repeated true must not begin a second assertion")
    }

    // MARK: 2 — end fires once per idle edge, with the same token

    func testEndKeepAwakeFiresOnceWhenBusyBecomesFalseNotOnARepeatedFalse() {
        let counter = ActivityCounter()
        let center = makeCenter(counter)

        center.setBusy(true)
        center.setBusy(false)
        XCTAssertEqual(counter.begins, 1)
        XCTAssertEqual(counter.ends, 1)

        center.setBusy(false)
        XCTAssertEqual(counter.ends, 1, "a repeated false must not end a second time")
    }

    // MARK: 3 — reset() while busy ends the token

    func testResetWhileBusyEndsTheKeepAwakeToken() {
        let counter = ActivityCounter()
        let center = makeCenter(counter)

        center.setBusy(true)
        XCTAssertEqual(counter.begins, 1)
        XCTAssertEqual(counter.ends, 0, "precondition: still busy, token still held")

        center.reset()
        XCTAssertFalse(center.isBusy, "reset() must leave the center idle")
        XCTAssertEqual(counter.ends, 1,
                       "reset() must end the keep-awake token it is holding, not leave it dangling")
    }

    // MARK: 4 — the begin(name:totalUnits:)/finish cycle stays balanced

    func testBeginFinishCycleKeepsTheKeepAwakeAssertionBalanced() {
        let counter = ActivityCounter()
        let center = makeCenter(counter)

        let token = center.begin(name: "test operation", totalUnits: nil)
        XCTAssertEqual(counter.begins, 1)
        XCTAssertEqual(counter.ends, 0)

        XCTAssertTrue(center.finish(token))
        XCTAssertEqual(counter.ends, 1)
        XCTAssertFalse(center.isBusy)
    }
}
