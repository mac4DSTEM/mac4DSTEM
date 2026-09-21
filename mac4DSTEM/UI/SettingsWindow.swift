//
//  SettingsWindow.swift
//  Role: session S21's Settings scene (`ROADMAP.md` "Settings window,
//        Xcode-style sidebar", owner 2026-09-21) — grows the one-section
//        scene `UI/MaterialsProjectSettingsView.swift` opened (S5) into a
//        `NavigationSplitView`: a sidebar of sections, a `Form` detail. Every
//        preference it edits lives on `AppPreferences`
//        (`Session/AppPreferences.swift`), the Settings scene's one state
//        owner, reached through `.environment(preferences)`
//        (`App/mac4DSTEMApp.swift`) — never through a dataset window's
//        `AppState`, which this scene has none of (S5's header explains why).
//
//  `NavigationSplitView`, never `HSplitView`/`NSSplitView` — the same rule
//  `ContentView`'s own workspace split follows (`docs/architecture.md`,
//  `tools/run-tests.sh inventory`).
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, analysis, materialsProject, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .analysis: return "Analysis"
        case .materialsProject: return "Materials Project"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .analysis: return "cpu"
        case .materialsProject: return "cube.transparent"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsWindow: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var selection: SettingsSection? = .general
    /// Finding A (adversarial review, 2026-09-21): hoisted out of
    /// `MaterialsProjectSettingsView`, which the `switch` below rebuilds
    /// (a fresh `@State` each time, discarding the local one) whenever the
    /// sidebar selection leaves `.materialsProject` and comes back. This
    /// `@State` lives on `SettingsWindow` instead, which the switch does not
    /// rebuild, so a typed-but-not-yet-saved key survives the round trip.
    @State private var materialsProjectKeyDraft = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(
                min: LayoutPolicy.sidebarWidth.min,
                ideal: LayoutPolicy.sidebarWidth.ideal,
                max: LayoutPolicy.sidebarWidth.max
            )
        } detail: {
            Form {
                switch selection ?? .general {
                case .general: GeneralSettingsSection()
                case .appearance: AppearanceSettingsSection()
                case .analysis: AnalysisSettingsSection()
                case .materialsProject: MaterialsProjectSettingsView(keyDraft: $materialsProjectKeyDraft)
                case .advanced: AdvancedSettingsSection()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((selection ?? .general).title)
        }
        .frame(
            minWidth: LayoutPolicy.settingsWindow.min.width,
            idealWidth: LayoutPolicy.settingsWindow.ideal.width,
            minHeight: LayoutPolicy.settingsWindow.min.height,
            idealHeight: LayoutPolicy.settingsWindow.ideal.height
        )
    }
}

// MARK: - General

private struct GeneralSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(RecentDatasets.self) private var recents
    @State private var confirmingClearRecents = false

    var body: some View {
        @Bindable var preferences = preferences
        Section("Opening datasets") {
            Picker("\u{201C}Open Dataset…\u{201D} does", selection: $preferences.openBehaviour) {
                ForEach(OpenDatasetBehaviour.allCases) { behaviour in
                    Text(behaviour.displayName).tag(behaviour)
                }
            }
            .accessibilityIdentifier("settings.general.openBehaviour")
            .help("\u{201C}Open with Options…\u{201D} always shows the configurator regardless of this setting.")

            Toggle("Keep the Mac awake during long runs", isOn: $preferences.keepAwake)
                .accessibilityIdentifier("settings.general.keepAwake")
        }

        Section("Recents") {
            Button("Clear Recent Datasets", role: .destructive) {
                confirmingClearRecents = true
            }
            .disabled(recents.entries.isEmpty)
            .accessibilityIdentifier("settings.general.clearRecents")
            .confirmationDialog(
                "Clear all \(recents.entries.count) recent datasets?",
                isPresented: $confirmingClearRecents,
                titleVisibility: .visible
            ) {
                Button("Clear Recent Datasets", role: .destructive) { recents.clearAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Section("Theme") {
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance.theme")
        }

        Section("Defaults for a new window") {
            Picker("Default colormap for maps", selection: $preferences.mapColormap) {
                ForEach(ColormapKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("settings.appearance.mapColormap")

            Picker("Default colormap for diffraction patterns", selection: $preferences.diffractionColormap) {
                ForEach(ColormapKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("settings.appearance.diffractionColormap")

            Picker("Intensity display", selection: $preferences.intensityDisplay) {
                ForEach(IntensityDisplayDefault.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .accessibilityIdentifier("settings.appearance.intensityDisplay")

            Toggle("Show scale bar", isOn: $preferences.showScaleBar)
                .accessibilityIdentifier("settings.appearance.showScaleBar")
        }
        .help("Applies to a newly opened window. It never changes an analysis's own colormap — a diverging strain or DPC-difference map stays diverging.")
    }
}

// MARK: - Analysis

private struct AnalysisSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Section("Matching engine") {
            Picker("Default engine", selection: $preferences.enginePreference) {
                ForEach(ACOMMatchingBackend.allCases) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            .accessibilityIdentifier("settings.analysis.engine")
            Text("ACOM's own \u{201C}Engine\u{201D} control can still change it per session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Disk detection") {
            Toggle("Offer the learned (neural net) detector", isOn: $preferences.offerLearnedDetector)
                .accessibilityIdentifier("settings.analysis.offerLearnedDetector")
            Text("Turning this off only hides the option; it does not change the classical detector's threshold, radius, or any other per-dataset setting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var preferences = preferences
        Section("Logging") {
            Picker("Log verbosity", selection: $preferences.logVerbosity) {
                ForEach(LogVerbosityDefault.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .accessibilityIdentifier("settings.advanced.logVerbosity")
            // No wiring yet: the output strip's `ActivityLog` has one
            // recording path with no verbosity tiers to switch — see
            // `Session/AppPreferences.swift`'s `LogVerbosityDefault` doc.
            // "Reveal Log File" is omitted: the app writes no log file to
            // disk, only `ActivityLog`'s in-memory, per-window strip.
        }

        Section("Reset") {
            Button("Reset All Settings…", role: .destructive) {
                confirmingReset = true
            }
            .accessibilityIdentifier("settings.advanced.resetAll")
            .confirmationDialog(
                "Reset all settings to their defaults?",
                isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset All Settings", role: .destructive) { preferences.resetAllToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resets every Settings preference. It does not touch your recent datasets, saved sessions, or the Materials Project key.")
            }
        }
    }
}
