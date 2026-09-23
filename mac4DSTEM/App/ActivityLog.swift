//
//  ActivityLog.swift
//  Role: The session's rolling record of what happened, shown in the output
//        strip along the bottom of the science panes.
//
//  An `AppState` seam (docs/archive/development-process-2026-08-31.md §7),
//  under CLAUDE.md's rule that a session touching `AppState` moves one
//  responsibility out of it. It sits in App/ rather than Session/ for the
//  same reason `WorkspaceNavigation` does: it is view-state with no science
//  in it, and Session/ is a package the app target excludes file by file.
//
//  Views read `activityLog.messages`; no forwarding properties on `AppState`.
//
//  `@Observable` here is load-bearing, not ceremony: `WorkspaceView`'s output
//  strip reads `messages` and scrolls on its count, and without observation
//  the strip goes silently stale. `ActivityLogTests` pins the whole chain
//  with `withObservationTracking` rather than trusting the annotation.
//

import Foundation

@Observable
final class ActivityLog {
    /// Oldest first, newest last — the order the strip scrolls in.
    private(set) var messages: [String] = []

    /// An unbounded log is a memory leak with a scroll bar. A long run writes
    /// thousands of lines and nobody reads past the last screenful.
    static let capacity = 300

    /// Injected so a test can assert the stamp instead of asserting that the
    /// clock is a clock.
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Set by `AppState.showReadout` for the one write that follows it.
    ///
    /// A READOUT IS NOT AN EVENT. The status line has two jobs — reporting
    /// what happened, and showing where you are — and only the first belongs
    /// in a log. Without this, every click on the scan image writes "Pattern
    /// x 154, y 152 from <filename>" here; the dedupe below never fires
    /// because the coordinates differ every time, and a 330 × 330 scan has
    /// 108 900 of them against a 300-line capacity — cursor movement would
    /// evict the run's real events (detection, import, phase map) from the
    /// record kept to explain them (observed 2026-09-12).
    ///
    /// A one-shot flag, not an `isEvent:` parameter on `record`, because the
    /// caller is `statusText.didSet` and a `didSet` cannot see who wrote to it.
    @ObservationIgnored private var suppressNextRecord = false

    /// The next `record` is a readout and is dropped. Consumed either way, so
    /// a suppressed write cannot leak into the one after it.
    func suppressNextRecordOnce() { suppressNextRecord = true }

    /// Empties the log. The bottom workspace's Output tab "Clear" button
    /// (ADR 034) — a deliberate user action, not a rule this file enforces
    /// on its own, so it is a plain removal with no suppression bookkeeping.
    func clear() { messages.removeAll() }

    /// Record one status event.
    ///
    /// Three things never reach the log. A readout, per
    /// `suppressNextRecordOnce` above — the primary defence against progress
    /// spam, since `AppState.updateCancellableOperation` is the one funnel
    /// every operation's progress passes through and it calls `showReadout`.
    /// An immediate repeat of the last message, because a status written twice
    /// is one thing happening, not two. And any message ending in "%", a
    /// backstop that is not sufficient alone: `SystemMonitor.scanProgressStatus`
    /// returns lines like "...1.54 GB of 1.66 GB", which end in "GB" not "%",
    /// so a whole-cube pass could still write a line per tick without the
    /// funnel (observed 2026-09-12). The suffix check stays as a second line
    /// of defence; no status string needs it any more since the progress bar
    /// beside them draws the percentage instead.
    func record(_ message: String) {
        let suppressed = suppressNextRecord
        suppressNextRecord = false
        guard !suppressed else { return }
        guard !message.isEmpty, !message.hasSuffix("%") else { return }
        if messages.last?.hasSuffix(message) == true { return }
        messages.append("\(Self.clock.string(from: now()))  \(message)")
        if messages.count > Self.capacity {
            messages.removeFirst(messages.count - Self.capacity)
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// The row a `ScrollViewReader` should scroll to for a log holding
    /// `count` lines — the newest one, or none for an empty log. Pulled out
    /// so the output strip's `.onAppear` (the panel opening scrolled to the
    /// top instead of the newest line) and its `.onChange` of the count can
    /// share one rule instead of restating "`count - 1`, unless there is
    /// nothing" at each call site.
    static func scrollTarget(forCount count: Int) -> Int? {
        count > 0 ? count - 1 : nil
    }
}

extension AppState {
    /// Show something in the status line WITHOUT recording it as an event.
    ///
    /// For a readout — where the cursor is, which pattern is on screen. It
    /// lives beside `ActivityLog` rather than in `AppState.swift` because the
    /// rule it encodes is the log's: this file is what decides what counts as
    /// an event, so it owns the one way of saying "this is not one".
    func showReadout(_ text: String) {
        activityLog.suppressNextRecordOnce()
        statusText = text
    }
}
