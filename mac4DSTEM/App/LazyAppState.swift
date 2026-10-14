//
//  LazyAppState.swift
//  Role: a dataset window's `AppState`, built the first time the window asks for it and never again.
//
//  Why: `DatasetWindow.init` runs every time the scene's content closure is evaluated, and it used to build an
//  `AppState` in `State(initialValue:)` each time, then drop all but the first (the state graph, and the
//  recovery record read from UserDefaults at `AppState.recoveryRecord`'s default). `@State` keeps only its first
//  value, so the rest was construction and a disk read for nothing (UI audit 2026-10-13, finding 1). The window now
//  holds this small box instead: `init` is cheap, and the one `AppState` is made on the first `state` read, in
//  `body`. Output is identical; nothing moves out of `AppState`, because the cost was at its construction site,
//  not in what it holds.
//

import Foundation

@MainActor
final class LazyAppState {
    private let make: @MainActor () -> AppState
    private var built: AppState?

    init(make: @escaping @MainActor () -> AppState) {
        self.make = make
    }

    /// The window's state: made on first use, the same instance after.
    var state: AppState {
        if let built { return built }
        let made = make()
        built = made
        return made
    }

    /// Whether the state has been made yet (a test).
    var isBuilt: Bool { built != nil }
}
