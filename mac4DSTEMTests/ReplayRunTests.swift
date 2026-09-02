//
//  ReplayRunTests.swift
//  v2 S6 — the run-state seam: phase transitions, outcome bookkeeping, and the
//  keep-awake BALANCE, which is the one invariant a leaked assertion would
//  silently violate for the rest of the process's life. The activity closures
//  are injected so acquisition/release counts are observable.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

@MainActor
final class ReplayRunTests: XCTestCase {

    private final class ActivityCounter {
        var begins = 0
        var ends = 0
        let token = NSObject()
    }

    private func makeRun(_ counter: ActivityCounter) -> ReplayRun {
        ReplayRun(
            beginKeepAwake: { counter.begins += 1; return counter.token },
            endKeepAwake: { ended in
                XCTAssertTrue(ended === counter.token,
                              "The run must end the token it began")
                counter.ends += 1
            }
        )
    }

    func testBeginStartsTheRunAndTakesTheKeepAwakeAssertionOnce() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["Virtual detector", "DPC"])
        XCTAssertTrue(run.isRunning)
        XCTAssertEqual(run.steps.map(\.outcome), [.notReached, .notReached])
        XCTAssertEqual(counter.begins, 1)
        XCTAssertEqual(counter.ends, 0, "The assertion is held for the whole run")
    }

    func testFinishReleasesTheAssertionExactlyOnceAndFoldsARunningStep() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["Virtual detector"])
        run.willRun(step: 0)
        XCTAssertEqual(run.steps[0].outcome, .running)
        run.finish(haltReason: "the dataset changed")
        XCTAssertEqual(counter.ends, 1)
        XCTAssertEqual(run.phase, .finished)
        XCTAssertEqual(run.haltReason, "the dataset changed")
        guard case .failed = run.steps[0].outcome else {
            return XCTFail("A step still marked running at finish must not claim to run forever")
        }
        // A second finish must not double-release.
        run.finish(haltReason: nil)
        XCTAssertEqual(counter.ends, 1, "finish is idempotent on the assertion")
        XCTAssertEqual(run.haltReason, "the dataset changed",
                       "A second finish must not rewrite the run's outcome")
    }

    func testOutcomesAreRecordedPerStepAndTheHeadlineDistinguishesHalt() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["A", "B", "C"],
                  at: Date(timeIntervalSince1970: 1_000))
        run.willRun(step: 0)
        run.conclude(step: 0, outcome: .succeeded(detail: "A ✓", seconds: 2))
        run.willRun(step: 1)
        run.conclude(step: 1, outcome: .failed(reason: "no peaks"))
        run.finish(haltReason: "B failed", at: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(run.steps[0].outcome, .succeeded(detail: "A ✓", seconds: 2))
        XCTAssertEqual(run.steps[1].outcome, .failed(reason: "no peaks"))
        XCTAssertEqual(run.steps[2].outcome, .notReached,
                       "Steps after the halt stay not-reached — never guessed at")
        XCTAssertTrue(run.summaryHeadline?.contains("Halted at step 2 of 3") == true,
                      "Headline was: \(run.summaryHeadline ?? "nil")")
    }

    func testACompletedRunHeadlineCountsTheSteps() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["A", "B"])
        run.willRun(step: 0)
        run.conclude(step: 0, outcome: .succeeded(detail: "", seconds: 1))
        run.willRun(step: 1)
        run.conclude(step: 1, outcome: .succeeded(detail: "", seconds: 1))
        run.finish(haltReason: nil)
        XCTAssertTrue(run.summaryHeadline?.contains("Replayed 2 analyses") == true,
                      "Headline was: \(run.summaryHeadline ?? "nil")")
        XCTAssertNil(run.haltReason)
    }

    func testBeginWhileRunningIsRefusedSoAStrayCallCannotOrphanTheAssertion() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        XCTAssertTrue(run.begin(titles: ["A"]))
        XCTAssertFalse(run.begin(titles: ["B", "C"]),
                       "The refusal IS the single-flight gate — a caller that ignored it would write into the first run's table (Gate A finding A5)")
        XCTAssertEqual(counter.begins, 1, "A second begin must not take a second assertion")
        XCTAssertEqual(run.steps.map(\.title), ["A"],
                       "The in-flight run's bookkeeping must survive")
    }

    func testABetweenStepsHaltHeadlineNeverContradictsASucceededRow() {
        // Dataset changed after step 1 succeeded, before step 2 began: no
        // step halted the run, so the headline must not name one — "Halted
        // at step 1" beside step 1's ✓ was the self-contradiction Gate A
        // findings A1/B6 caught.
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["A", "B", "C"])
        run.willRun(step: 0)
        run.conclude(step: 0, outcome: .succeeded(detail: "A ✓", seconds: 1))
        run.finish(haltReason: "the dataset changed")
        XCTAssertTrue(run.summaryHeadline?.contains("Halted after 1 of 3 steps") == true,
                      "Headline was: \(run.summaryHeadline ?? "nil")")
    }

    func testACancelledStepIsNotReportedAsAFailure() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["A", "B"])
        run.willRun(step: 0)
        run.conclude(step: 0, outcome: .cancelled)
        run.finish(haltReason: "A was cancelled")
        XCTAssertEqual(run.steps[0].outcome, .cancelled,
                       "A deliberate stop must stay distinguishable from a compute failure in the record the user trusts")
        XCTAssertTrue(run.summaryHeadline?.contains("Halted at step 1 of 2") == true,
                      "Headline was: \(run.summaryHeadline ?? "nil")")
    }

    func testClearIsANoOpWhileRunningAndClearsWhenFinished() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.begin(titles: ["A"])
        run.clearUnlessRunning()
        XCTAssertTrue(run.isRunning,
                      "Clearing mid-run would strand the executor's bookkeeping")
        run.finish(haltReason: nil)
        run.clearUnlessRunning()
        XCTAssertEqual(run.phase, .idle)
        XCTAssertTrue(run.steps.isEmpty)
        XCTAssertEqual(counter.ends, 1)
    }

    func testFinishWithoutBeginDoesNotTouchTheAssertion() {
        let counter = ActivityCounter()
        let run = makeRun(counter)
        run.finish(haltReason: nil)
        XCTAssertEqual(counter.ends, 0)
        XCTAssertEqual(run.phase, .idle)
    }
}
