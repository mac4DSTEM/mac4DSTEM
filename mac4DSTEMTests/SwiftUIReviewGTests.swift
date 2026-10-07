import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane G of the 2026-10-07 SwiftUI review fixes.
@MainActor
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

    // MARK: - G2 ring-hint task key

    private func pattern(_ qy: Int, _ qx: Int, fill: (Int) -> Float) -> DiffractionPattern {
        DiffractionPattern(qy: qy, qx: qx, pixels: (0..<(qy * qx)).map(fill))
    }

    /// The key follows the mean pattern and the descriptor shape, and nothing
    /// else. Mutation: the digest ignores the pixels (hasher.combine of
    /// bitPattern removed) -> the changed-pixel assertion goes red.
    func testRingHintKeyFollowsThePatternAndNotTheDisplaySettings() {
        let a = pattern(64, 64) { Float($0 % 97) }
        let same = pattern(64, 64) { Float($0 % 97) }
        let keyA = ProbeRingHintKey.make(mean: a, descriptorQy: 64, descriptorQx: 64)
        XCTAssertNotNil(keyA)
        XCTAssertEqual(keyA, ProbeRingHintKey.make(mean: same, descriptorQy: 64, descriptorQx: 64),
                       "an identical recomputed mean keeps the key")

        let other = pattern(64, 64) { Float(($0 * 7) % 89) }
        XCTAssertNotEqual(keyA, ProbeRingHintKey.make(mean: other, descriptorQy: 64, descriptorQx: 64),
                          "a different mean pattern moves the key")

        // The last pixel is always sampled, so a change there is seen.
        var lastChanged = a.pixels
        lastChanged[lastChanged.count - 1] += 1
        XCTAssertNotEqual(keyA, ProbeRingHintKey.make(
            mean: DiffractionPattern(qy: 64, qx: 64, pixels: lastChanged), descriptorQy: 64, descriptorQx: 64))
    }

    /// Mutation: drop the `mean.qy == descriptorQy` shape guard -> red.
    func testRingHintKeyIsNilWhenTheHintCannotBeComputed() {
        let a = pattern(8, 8) { Float($0) }
        XCTAssertNil(ProbeRingHintKey.make(mean: nil, descriptorQy: 8, descriptorQx: 8))
        XCTAssertNil(ProbeRingHintKey.make(mean: a, descriptorQy: nil, descriptorQx: nil))
        XCTAssertNil(ProbeRingHintKey.make(mean: a, descriptorQy: 8, descriptorQx: 16),
                     "a shape disagreement is the task's own early-out")
    }

    /// The premise of the fix: display toggles bump `patternVersion` (what the
    /// task used to key on) while the new key does not move.
    func testDisplayTogglesBumpPatternVersionButNotTheRingHintKey() {
        let state = AppState()
        state.meanPattern = pattern(8, 8) { Float($0) }
        let key = ProbeRingHintKey.make(mean: state.meanPattern, descriptorQy: 8, descriptorQx: 8)
        let version = state.patternVersion
        state.logScale.toggle()
        state.patternColormap = .inferno
        XCTAssertNotEqual(state.patternVersion, version, "the old key moved on a display toggle")
        XCTAssertEqual(key, ProbeRingHintKey.make(mean: state.meanPattern, descriptorQy: 8, descriptorQx: 8))
    }
}
