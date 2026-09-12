import XCTest
@testable import mac4DSTEM

/// The output strip's log, and the one thing about it that fails silently.
final class ActivityLogTests: XCTestCase {

    // MARK: - The seam is observed, or the strip quietly stops

    /// **The reason this extraction is worth doing, and the only mutation that
    /// matters.** `WorkspaceView`'s output strip reads
    /// `appState.activityLog.messages` and scrolls on its count. If
    /// `ActivityLog` is not `@Observable`, every other test here still passes,
    /// the app still builds, and the strip simply never updates again — the
    /// exact shape of silent failure this repo keeps paying for.
    ///
    /// So this asserts the whole chain a view depends on, in a pure XCTest
    /// with no UI and no Metal: writing `AppState.statusText` must notify an
    /// observer of `activityLog.messages`. Break it by deleting `@Observable`
    /// from `ActivityLog`.
    @MainActor
    func testWritingStatusTextNotifiesAnObserverOfTheLog() {
        let state = AppState()
        // A nonisolated reference box, not a captured `var`: `onChange` runs
        // outside this actor, and mutating main-actor state there is an error
        // under the Swift 6 language mode.
        let flag = ObservationFlag()
        withObservationTracking {
            _ = state.activityLog.messages
        } onChange: {
            flag.fired = true
        }

        state.statusText = "a message the log must carry"

        XCTAssertTrue(flag.fired, "the output strip stops updating if this seam is not observed")
    }

    /// The seam is held, not shadowed — the same contract `NavigationSeamTests`
    /// pins for `navigation`, with the same known limit: `Mirror` sees stored
    /// properties only, so a computed forwarder is caught by review, not here.
    @MainActor
    func testAppStateHoldsTheLogWithoutForwardingIt() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("activityLog"), "the facade holds the seam")
        XCTAssertFalse(names.contains("logMessages"),
                       "the log may not come back as a stored property on AppState")
    }

    // MARK: - What it records, and what it refuses

    func testProgressSpamAndEmptyMessagesNeverReachTheLog() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        log.record("")
        log.record("Detecting disks… 42 %")
        log.record("Detecting disks… 100 %")
        XCTAssertTrue(log.messages.isEmpty,
                      "a percentage tick is progress, not an event: \(log.messages)")

        log.record("Disks ✓ 16384 peaks")
        XCTAssertEqual(log.messages.count, 1)
    }

    /// A status written twice is one thing happening.
    func testAnImmediateRepeatIsNotStacked() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        log.record("Loaded WS2.h5")
        log.record("Loaded WS2.h5")
        XCTAssertEqual(log.messages.count, 1)

        log.record("Something else")
        log.record("Loaded WS2.h5")
        XCTAssertEqual(log.messages.count, 3, "a repeat that is not immediate is a real event")
    }

    func testTheLogIsCappedAndKeepsTheNewestLines() {
        let log = ActivityLog(now: { Date(timeIntervalSinceReferenceDate: 0) })
        for i in 0..<(ActivityLog.capacity + 50) { log.record("line \(i)") }

        XCTAssertEqual(log.messages.count, ActivityLog.capacity)
        XCTAssertTrue(log.messages.last?.hasSuffix("line \(ActivityLog.capacity + 49)") == true,
                      "the newest line survives")
        XCTAssertFalse(log.messages.contains { $0.hasSuffix("line 0") },
                       "the oldest lines are the ones dropped")
    }

    // MARK: - Where the output strip scrolls to

    /// The output strip scrolls on `.onChange` of the count, which never
    /// fires the first time the panel appears — it opens scrolled to its
    /// top instead of its newest line. The fix reads this pure index on
    /// `.onAppear` too, so it has to be right for a log with nothing in it
    /// as well as one already full.
    func testScrollTargetIsTheLastIndexOrNilWhenEmpty() {
        XCTAssertNil(ActivityLog.scrollTarget(forCount: 0))
        XCTAssertEqual(ActivityLog.scrollTarget(forCount: 1), 0)
        XCTAssertEqual(ActivityLog.scrollTarget(forCount: 5), 4)
        XCTAssertEqual(ActivityLog.scrollTarget(forCount: ActivityLog.capacity), ActivityLog.capacity - 1)
    }

    /// The stamp is the injected clock's, not the wall clock's.
    func testEachLineCarriesTheTimeItWasRecorded() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let log = ActivityLog(now: { now })
        let stamp = { (d: Date) -> String in
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
        }

        log.record("first")
        now.addTimeInterval(3661)
        log.record("second")

        XCTAssertTrue(log.messages[0].hasPrefix(stamp(Date(timeIntervalSinceReferenceDate: 0))))
        XCTAssertTrue(log.messages[1].hasPrefix(stamp(now)))
        XCTAssertNotEqual(String(log.messages[0].prefix(8)), String(log.messages[1].prefix(8)))
    }

    /// A READOUT IS NOT AN EVENT, and before 2026-09-12 the log could not tell
    /// the difference. Every click on the scan image wrote
    /// "Pattern x 154, y 152 from <filename>" through `statusText`, the
    /// consecutive-repeat rule never fired because the coordinates differ
    /// every time, and on a 330 × 330 scan there are 108 900 of them against a
    /// 300-line capacity — so moving the cursor evicted the run's real events
    /// from the record kept to explain them. Observed in the owner's own
    /// screenshot.
    ///
    /// Mutation: `suppressNextRecord` never reset, or read without being
    /// consumed. Either one makes the flag leak into the write after it, and
    /// the first real event following a click would vanish instead.
    func testAReadoutReachesTheStatusLineAndNotTheLog() {
        let log = ActivityLog(now: { Date(timeIntervalSince1970: 0) })
        log.record("Disks ✓ 802 752 peaks")
        XCTAssertEqual(log.messages.count, 1)

        log.suppressNextRecordOnce()
        log.record("Pattern x 154, y 152")
        XCTAssertEqual(log.messages.count, 1, "a readout was recorded as an event")

        // Consumed: the very next write is an event again.
        log.record("Pattern x 96, y 80")
        XCTAssertEqual(log.messages.count, 2,
                       "the suppression leaked into the write after it")
        XCTAssertTrue(log.messages.last?.hasSuffix("Pattern x 96, y 80") ?? false)

        // And suppressing then recording nothing must not arm the next write.
        log.suppressNextRecordOnce()
        log.record("")
        log.record("Phase map: β″ 1, matrix 0")
        XCTAssertEqual(log.messages.count, 3,
                       "an empty suppressed write left the flag armed")
    }
}

/// Set from `withObservationTracking`'s `onChange`, which runs off the main
/// actor. Nonisolated on purpose; see its one use above.
nonisolated final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var fired: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }

}
