//
//  DropToOpen.swift
//  Role: what a file dropped on a dataset window asks for (UI audit 2026-10-14, F). The window's
//        `.dropDestination(for: URL.self)` (App/mac4DSTEMApp.swift, SwiftUI's own, no AppKit) hands the dropped
//        URLs here; the open itself is `AppState.openFile(url:)`, the same funnel as File > Open Dataset…, a
//        Recents row and Finder's Open With, so every refusal it has (a load in flight, a sidecar save, a dataset
//        another window holds, an unreadable file) applies to a drop unchanged.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMSession
#endif

enum DropToOpen {

    /// The dataset a drop asks for: the first file URL among what was dropped (one dataset per window, so a
    /// multiple drop opens the first), or nil when the drop carried none (a web link, text).
    static func dataset(in dropped: [URL]) -> URL? {
        dropped.first(where: \.isFileURL)
    }
}

/// Which window a Finder open (Open With, a double-click, a file dropped on the Dock icon) goes to (#163). An empty
/// window takes any file. A window that holds a dataset takes only that file again, so the open brings it forward
/// instead of making a new window that refuses it (drive 2026-11-11, check 3). Any other file, or any file while the
/// window is opening one, is declined, and SwiftUI makes a new window for it. Without the declaration SwiftUI made a
/// new window for every Finder open, and the empty welcome window stayed behind.
enum ExternalOpen {

    /// The window's `handlesExternalEvents(preferring:allowing:)` patterns. SwiftUI matches them against the opened
    /// URL's `absoluteString`; the held file is listed as written and with its symlinks resolved (`/var` and
    /// `/private/var` are one folder), the spellings Finder may send.
    static func patterns(holdsDocument: Bool, isOpening: Bool, heldPath: String? = nil) -> Set<String> {
        if isOpening { return [] }
        if let heldPath {
            let url = URL(fileURLWithPath: heldPath)
            return [url.absoluteString, url.standardizedFileURL.resolvingSymlinksInPath().absoluteString]
        }
        return holdsDocument ? [] : ["*"]
    }

    /// The window already holds `url`: opening it again changes nothing (Finder's open only brings the window forward).
    static func isHeld(_ url: URL, heldPath: String?) -> Bool {
        guard let heldPath else { return false }
        return OpenDatasetRegistry.sameFile(url, URL(fileURLWithPath: heldPath))
    }
}
