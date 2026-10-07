import XCTest
@testable import mac4DSTEM

/// Lane G of the 2026-10-07 SwiftUI review fixes.
final class SwiftUIReviewGTests: XCTestCase {

    // MARK: - G1 activity log identity

    /// At capacity a new line must still produce a new newest id (the strip
    /// scrolls on it; the count no longer moves), ids must be unique, and a
    /// surviving line keeps the id it had. Mutation: `Line.id` taken from the
    /// position (index) instead of the monotonic counter -> red.
    func testActivityLogIdsStayUniqueAndStableAtCapacity() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        for i in 0..<ActivityLog.capacity { log.record("line \(i)") }
        XCTAssertEqual(log.lines.count, ActivityLog.capacity)

        let before = log.lines
        let lastBefore = before.last?.id
        let survivor = before[ActivityLog.capacity / 2]

        log.record("one more")
        XCTAssertEqual(log.lines.count, ActivityLog.capacity, "still at the cap")
        XCTAssertNotEqual(log.lines.last?.id, lastBefore, "a new line yields a new newest id")
        XCTAssertEqual(Set(log.lines.map(\.id)).count, ActivityLog.capacity, "ids are unique")
        XCTAssertTrue(log.lines.contains(survivor), "a surviving line keeps its id and text")

        log.clear()
        log.record("after clear")
        XCTAssertFalse(before.map(\.id).contains(log.lines[0].id), "ids are not reused after clear")
    }
}
