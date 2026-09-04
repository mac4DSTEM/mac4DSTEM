//
//  ActivityLog.swift
//  Role: The session's rolling record of what happened, shown in the output
//        strip along the bottom of the science panes.
//
//  An `AppState` seam (docs/development-process.md §7), extracted 2026-09-04
//  under CLAUDE.md's rule that a session touching `AppState` moves one
//  responsibility out of it. It sits in App/ rather than Session/ for the
//  same reason `WorkspaceNavigation` does: it is view-state with no science
//  in it, and Session/ is a package the app target excludes file by file.
//
//  Views read `activityLog.messages`; no forwarding properties on `AppState`.
//
//  `@Observable` here is load-bearing, not ceremony. `WorkspaceView`'s output
//  strip reads `messages` and scrolls on its count; without observation the
//  strip goes quiet and nothing else breaks, which is the kind of silent
//  failure this repo keeps buying. `ActivityLogTests` pins the whole chain
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

    /// Record one status event.
    ///
    /// Two things never reach the log. Progress spam — every "… 42 %" tick of
    /// an operation — because it would bury the events worth reading. And an
    /// immediate repeat of the last message, because a status written twice is
    /// one thing happening, not two.
    func record(_ message: String) {
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
}
