//
//  ReplayRun.swift
//  Role: The live state of one unattended promote run — which step is
//        executing, what each step's outcome was, and the summary a user
//        reads the next morning. v2 S6's `AppState` seam
//        (docs/development-process.md §7): the state the stage ADDS, in its
//        own `@Observable` type that `AppState` holds — the
//        `DatasetResidency` / `SessionReplay` precedent, no forwarding
//        properties.
//
//  KEEP-AWAKE lives here, not in the executor, so acquisition and release are
//  one type's invariant: the assertion begins in `begin` and ends in `finish`,
//  and there is no path that leaves it held (`finish` is the only exit the
//  executor has). The closures are injectable because a unit test cannot
//  observe a real `ProcessInfo` activity — the balance is what the tests pin.
//  Honesty limit, stated where the user can read it: an idle-sleep assertion
//  does not survive a closed lid. The inspector caption says so.
//

import Foundation

@Observable
final class ReplayRun {

    enum Outcome: Equatable {
        /// Step not started yet (or never reached, if the run halted earlier).
        case notReached
        /// Currently executing.
        case running
        /// Ran and published. `detail` is the entry point's own success status
        /// line — peak counts, index fractions — captured verbatim.
        case succeeded(detail: String, seconds: Double)
        /// Ran and did not publish (error), with the reason.
        case failed(reason: String)
        /// The user (or a dataset change) stopped it — a deliberate stop is
        /// not a failure, and a summary that says "failed" for a cancel
        /// misdescribes the run (Gate A finding B6, 2026-08-25).
        case cancelled
        /// Never ran — the plan refused it, with the reason.
        case refused(reason: String)

        /// A terminal outcome the run halted on (anything but not-reached,
        /// running, or success).
        var halted: Bool {
            switch self {
            case .failed, .cancelled, .refused: true
            case .notReached, .running, .succeeded: false
            }
        }
    }

    struct StepReport: Identifiable, Equatable {
        let index: Int
        let title: String
        var outcome: Outcome = .notReached
        var id: Int { index }
    }

    enum Phase: Equatable {
        case idle
        case running
        case finished
    }

    /// Derived from the timestamps, so the phase and the dates the summary
    /// renders can never disagree (Gate A simplification, 2026-08-25).
    var phase: Phase {
        if startedAt == nil { return .idle }
        return endedAt == nil ? .running : .finished
    }

    private(set) var steps: [StepReport] = []
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    /// Nil when the run replayed every step; otherwise why it stopped where it
    /// did. A halted run is a completed record of an incomplete replay — the
    /// steps after the halt stay `.notReached` rather than being guessed at.
    private(set) var haltReason: String?

    var isRunning: Bool { phase == .running }

    private let beginKeepAwake: () -> NSObjectProtocol?
    private let endKeepAwake: (NSObjectProtocol) -> Void
    @ObservationIgnored private var keepAwakeToken: NSObjectProtocol?

    init(
        beginKeepAwake: @escaping () -> NSObjectProtocol? = {
            ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "mac4DSTEM promote run — replaying recorded analyses"
            )
        },
        endKeepAwake: @escaping (NSObjectProtocol) -> Void = {
            ProcessInfo.processInfo.endActivity($0)
        }
    ) {
        self.beginKeepAwake = beginKeepAwake
        self.endKeepAwake = endKeepAwake
    }

    /// Start a run over these step titles. Returns false while one is already
    /// running — the caller must NOT proceed then: the executor is
    /// single-flight, and a second caller that ignored the refusal would
    /// write into the first run's step table and release its keep-awake
    /// assertion mid-run (Gate A finding A5, 2026-08-25). Called BEFORE the
    /// full-extent reopen, so the assertion covers the longest unattended
    /// phase, not just the analyses (findings B1/C1).
    @discardableResult
    func begin(titles: [String], at date: Date = Date()) -> Bool {
        guard phase != .running else { return false }
        steps = titles.enumerated().map { StepReport(index: $0.offset, title: $0.element) }
        startedAt = date
        endedAt = nil
        haltReason = nil
        keepAwakeToken = beginKeepAwake()
        return true
    }

    func willRun(step index: Int) {
        guard phase == .running, steps.indices.contains(index) else { return }
        steps[index].outcome = .running
    }

    func conclude(step index: Int, outcome: Outcome) {
        guard phase == .running, steps.indices.contains(index) else { return }
        steps[index].outcome = outcome
    }

    /// End the run — the one exit. Releases the keep-awake assertion whatever
    /// the outcome; a step still marked `.running` (the executor halted around
    /// it) is folded into the halt rather than left claiming to run forever.
    func finish(haltReason: String?, at date: Date = Date()) {
        guard phase == .running else { return }
        for index in steps.indices where steps[index].outcome == .running {
            steps[index].outcome = .failed(reason: haltReason ?? "the run ended while this step was executing")
        }
        self.haltReason = haltReason
        endedAt = date
        if let token = keepAwakeToken {
            endKeepAwake(token)
            keepAwakeToken = nil
        }
    }

    /// Dataset change while no run is in flight: the summary described the
    /// previous dataset's promote and would be misread under a new one. A
    /// RUNNING run is never cleared here — the executor observes the epoch
    /// change and halts through `finish`, which keeps the keep-awake balance
    /// in one place.
    func clearUnlessRunning() {
        guard phase != .running else { return }
        steps = []
        startedAt = nil
        endedAt = nil
        haltReason = nil
    }

    // MARK: - Summary presentation

    /// One line for the inspector header, e.g.
    /// "Replayed 4 analyses · 23:41 – 03:12" or
    /// "Halted at step 2 of 4 · 23:41 – 23:58".
    ///
    /// A halt names the step that halted it only when one exists — a
    /// between-steps halt (dataset changed before the next step began) says
    /// "after N of M" instead, so the headline can never contradict a step
    /// row that shows ✓ (Gate A findings A1/B6, 2026-08-25).
    var summaryHeadline: String? {
        guard phase == .finished else { return nil }
        let window = [startedAt, endedAt]
            .compactMap { $0 }
            .map { $0.formatted(date: .omitted, time: .shortened) }
            .joined(separator: " – ")
        if haltReason == nil {
            let count = steps.count
            return "Replayed \(count) \(count == 1 ? "analysis" : "analyses") · \(window)"
        }
        if let halted = steps.firstIndex(where: { $0.outcome.halted }) {
            return "Halted at step \(halted + 1) of \(steps.count) · \(window)"
        }
        let completed = steps.filter { $0.outcome != .notReached }.count
        return "Halted after \(completed) of \(steps.count) steps · \(window)"
    }
}
