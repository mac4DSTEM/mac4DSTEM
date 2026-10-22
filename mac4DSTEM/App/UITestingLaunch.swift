//
//  UITestingLaunch.swift
//  Role: the `--ui-testing` launch of the UI test target in one place: the flag, the window width argument, and the reset of
//        saved window state that makes a launch start deterministic. macTEM carries the same helper under the same name
//        (design review 2026-10-22: the reset was written twice and would drift); a change here is copied there.
//
//  AppKit-free: UserDefaults and the file system only. SwiftUI offers no way to drop restored window frames or saved
//  application state, which is why the reset reaches these two stores.
//

import Foundation

enum UITestingLaunch {
    /// Launched by the UI test target: deterministic window, no restore.
    static let isActive = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    /// The window's width: the default 1440, or `--ui-window-width <points>` (800 or more), so a journey can see the narrower layout.
    static let windowWidth: CGFloat = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "--ui-window-width"), i + 1 < arguments.count,
              let width = Double(arguments[i + 1]), width >= 800 else { return 1440 }
        return CGFloat(width)
    }()

    static let windowHeight: CGFloat = 900

    /// A launch starts from no saved window or split geometry and no saved application state. Before any window is made. (The unit
    /// runner clears the same window keys from outside: `tools/run-tests.sh clear_test_host_geometry`.) No-op unless `isActive`.
    static func resetSavedState(defaults: UserDefaults = .standard, home: String = NSHomeDirectory(),
                                bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard isActive else { return }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame") || key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
        }
        // A launch killed by the test leaves saved windows that the next launch restores into nothing (0 windows, the app frontmost
        // and "Disabled" to XCUITest): start from no saved application state.
        if let id = bundleIdentifier {
            let saved = URL(fileURLWithPath: home).appendingPathComponent("Library/Saved Application State/\(id).savedState")
            try? FileManager.default.removeItem(at: saved)
        }
        defaults.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }
}
