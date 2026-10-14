//
//  DropToOpen.swift
//  Role: what a file dropped on a dataset window asks for (UI audit 2026-10-14, F). The window's
//        `.dropDestination(for: URL.self)` (App/mac4DSTEMApp.swift, SwiftUI's own, no AppKit) hands the dropped
//        URLs here; the open itself is `AppState.openFile(url:)`, the same funnel as File > Open Dataset…, a
//        Recents row and Finder's Open With, so every refusal it has (a load in flight, a sidecar save, a dataset
//        another window holds, an unreadable file) applies to a drop unchanged.
//

import Foundation

enum DropToOpen {

    /// The dataset a drop asks for: the first file URL among what was dropped (one dataset per window, so a
    /// multiple drop opens the first), or nil when the drop carried none (a web link, text).
    static func dataset(in dropped: [URL]) -> URL? {
        dropped.first(where: \.isFileURL)
    }
}
