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
/// One per process: the updater, whether a check can start now (false while one runs, or when the updater is off), and the
/// Settings switch for the daily check.
@Observable
final class SoftwareUpdate {
    private(set) var canCheck = false
    /// False in a Debug build, under UI tests and without a key (`SoftwareUpdatePolicy`): Settings shows the switch off and dimmed.
    private(set) var isRunning = false
    /// Settings > General > Check for updates automatically: Sparkle's own setting, the one its second-launch question sets,
    /// so a person who answered "Don't Check" can turn it on later (and the other way round).
    var automaticallyChecks = false {
        didSet {
            guard isRunning, controller.updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        guard SoftwareUpdatePolicy.shouldStart(info: Bundle.main.infoDictionary ?? [:], debugBuild: SoftwareUpdatePolicy.isDebugBuild,
                                               uiTesting: UITestingLaunch.isActive) else { return }
        // Started on the next turn of the main loop, once the app has finished launching and opened its window: Sparkle's
        // second-launch question then comes over a window instead of before one.
        Task { @MainActor [weak self] in self?.start() }
    }

    private func start() {
        controller.startUpdater()
        isRunning = true
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheck = value }
            },
            // The second-launch answer arrives here too, so the Settings switch shows it.
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.automaticallyChecksForUpdates
                Task { @MainActor in self?.automaticallyChecks = value }
            },
        ]
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

/// Settings > General > Software Update (the download only; `SettingsWindow` shows it under `#if SPARKLE`).
struct SoftwareUpdateSettingsSection: View {
    @Environment(SoftwareUpdate.self) private var update

    var body: some View {
        @Bindable var update = update
        Section("Software Update") {
            Toggle("Check for updates automatically", isOn: $update.automaticallyChecks)
                .disabled(!update.isRunning)
                .accessibilityIdentifier("settings.general.automaticUpdates")
                .help("Once a day mac4DSTEM asks mac4dstem.com whether a newer version exists. Nothing else is sent.")
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
