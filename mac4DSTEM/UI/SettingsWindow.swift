//
//  SettingsWindow.swift
//  Role: the Settings scene (`ROADMAP.md` "Settings window, Xcode-style
//        sidebar") — grows the one-section scene
//        `UI/MaterialsProjectSettingsView.swift` opened (S5) into a
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

import ShellLayout
import SwiftUI
import ShellMetal
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, analysis, materialsProject, agents, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .analysis: return "Analysis"
        case .materialsProject: return "Materials Project"
        case .agents: return "Agents"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .analysis: return "cpu"
        case .materialsProject: return "cube.transparent"
        case .agents: return "door.left.hand.open"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsWindow: View {
    @State private var selection: SettingsSection? = .general
    /// Hoisted out of `MaterialsProjectSettingsView`, which the `switch`
    /// below rebuilds (a fresh `@State` each time, discarding the local one)
    /// whenever the sidebar selection leaves `.materialsProject` and comes
    /// back. This `@State` lives on `SettingsWindow` instead, which the
    /// switch does not rebuild, so a typed-but-not-yet-saved key survives
    /// the round trip.
    @State private var materialsProjectKeyDraft = ""
    @Environment(AppPreferences.self) private var preferences

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
                case .agents: AgentSettingsSection()
                case .advanced: AdvancedSettingsSection()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((selection ?? .general).title)
        }
        // The category list stands; there is nothing to toggle in a
        // settings window — matches System Settings' own shape.
        .toolbar(removing: .sidebarToggle)
        // Here, not on the Agents section: Reset All Settings (Advanced) turns the preference off too, and the door must follow.
        .onChange(of: preferences.agentDoorEnabled) { _, enabled in AgentDoor.shared.setEnabled(enabled) }
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

        Section("Exported images") {
            Picker("Image size", selection: $preferences.exportScale) {
                ForEach(ExportImageScale.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .accessibilityIdentifier("settings.general.exportScale")
            .help(FigureExportSection.sizeHelp)

            Picker("Figure format", selection: $preferences.figureFormat) {
                ForEach(ExportFigureFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .accessibilityIdentifier("settings.general.figureFormat")
            .help(FigureExportSection.formatHelp)
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
        Section("Disk detection") {
            Toggle("Offer the learned (neural net) detector", isOn: $preferences.offerLearnedDetector)
                .accessibilityIdentifier("settings.analysis.offerLearnedDetector")
            Text("Turning this off only hides the option; it does not change the classical detector's threshold, radius, or any other per-dataset setting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Agents

/// The agent door's one switch and what it is doing (`App/AgentDoor/AgentDoor.swift`). The sentence under it says what an agent
/// can and cannot do, because the switch opens a listener and the person should know its reach before turning it on.
struct AgentSettingsSection: View {   // internal: AgentDoorTests reads `statusText`
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        let door = AgentDoor.shared
        Section("Agent access") {
            Toggle("Let agents on this Mac look at open windows", isOn: $preferences.agentDoorEnabled)
                .accessibilityIdentifier("settings.agents.enabled")
            LabeledContent("Status", value: Self.statusText(door.status, requests: door.requestCount))
                .accessibilityIdentifier("settings.agents.status")
            Text("While this is on, an agent you run on this Mac (Claude, Codex) can read what mac4DSTEM's windows show through the mac4DSTEM MCP bridge: the dataset, its calibration, the result and the diffraction pattern as pictures, the detected disks and the recipe. It cannot change anything. Nothing leaves this Mac, and other computers cannot reach the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The status row's words. Pure, so it is tested.
    static func statusText(_ status: AgentDoor.Status, requests: Int) -> String {
        switch status {
        case .off: return "Off"
        case .starting: return "Opening\u{2026}"
        case .listening(let port):
            if requests == 0 { return "On (port \(port)), no agent has asked yet" }
            return "On (port \(port)), \(requests) \(requests == 1 ? "request" : "requests") answered"
        case .failed(let why): return "Could not open: \(why)"
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var confirmingReset = false

    var body: some View {
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
