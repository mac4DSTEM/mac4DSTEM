//
//  SoftwareUpdate.swift
//  Role: mac4DSTEM > Check for Updates… in the website download (#122), on Sparkle 2, the Mac's standard updater for apps
//        outside the App Store. The App Store build compiles none of this (no SPARKLE condition when MACEM_STORE_BUILD=YES,
//        and its bundle carries no Sparkle.framework): the store updates it. Settings live in Info-Direct.plist: the feed on
//        mac4dstem.com, the public EdDSA key, the sandboxed installer. Sparkle asks the person on the second launch whether
//        to check by itself (once a day); the check is one HTTPS request for the feed, with no system profile.
//

import Foundation
#if SPARKLE
import Sparkle
import SwiftUI
#endif

/// When the updater runs, outside `#if SPARKLE` so the unit tests (whose target has no such condition) reach it.
nonisolated enum SoftwareUpdatePolicy {
    /// The Info-Direct.plist placeholder until the release key is in: with it Sparkle would refuse every update and say so
    /// at launch, so the updater stays off, and tools/release.sh refuses to build a download that carries it.
    static let placeholderKey = "SET-BEFORE-RELEASE"

    static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Off in a Debug build (a development build would be offered the released version over itself), under UI tests (the
    /// second-launch question would sit over a drive), and without a feed or a real key. Pure, so it is tested.
    static func shouldStart(info: [String: Any], debugBuild: Bool, uiTesting: Bool) -> Bool {
        guard !debugBuild, !uiTesting, info["SUFeedURL"] is String,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty, key != placeholderKey else { return false }
        return true
    }
}

#if SPARKLE
/// One per process: the updater and whether a check can start now (false while one runs, or when the updater is off).
@Observable
final class SoftwareUpdate {
    private(set) var canCheck = false
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        guard SoftwareUpdatePolicy.shouldStart(info: Bundle.main.infoDictionary ?? [:], debugBuild: SoftwareUpdatePolicy.isDebugBuild,
                                               uiTesting: UITestingLaunch.isActive) else { return }
        controller.startUpdater()
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

/// mac4DSTEM > Check for Updates…, under About mac4DSTEM, where Mac apps put it.
struct SoftwareUpdateCommands: Commands {
    let update: SoftwareUpdate

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(update: update)
        }
    }
}

/// A view, so the menu item tracks `canCheck` through Observation.
private struct CheckForUpdatesButton: View {
    let update: SoftwareUpdate

    var body: some View {
        Button("Check for Updates…") { update.checkForUpdates() }
            .disabled(!update.canCheck)
    }
}
#endif
