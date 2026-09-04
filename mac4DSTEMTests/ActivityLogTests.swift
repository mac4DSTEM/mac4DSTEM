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
