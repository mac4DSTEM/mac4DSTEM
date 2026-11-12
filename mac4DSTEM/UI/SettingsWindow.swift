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

import ShellAgentDoor
import ShellLayout
import SwiftUI
import UniformTypeIdentifiers
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
        .onChange(of: preferences.agentDoorEnabled) { _, enabled in Mac4DSTEMAgentDoor.setEnabled(enabled) }
        .onChange(of: preferences.agentRunsEnabled) { _, allowed in Mac4DSTEMAgentDoor.setRunsAllowed(allowed) }
        .onChange(of: preferences.agentFolderBookmark) { _, bookmark in
            Mac4DSTEMAgentDoor.setFolder(bookmark: bookmark, savesAllowed: preferences.agentFolderSavesEnabled)
        }
        .onChange(of: preferences.agentFolderSavesEnabled) { _, allowed in
            Mac4DSTEMAgentDoor.setFolder(bookmark: preferences.agentFolderBookmark, savesAllowed: allowed)
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

        #if SPARKLE
        SoftwareUpdateSettingsSection()   // the website download only (App/SoftwareUpdate.swift)
        #endif

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
        ModelCacheSection()
    }
}

/// How much the learned detector's caches hold on this Mac (mac4DSTEM#179): Core ML's cache of device-specialised models,
/// which grew to 26 GB before 5.2.1, and the app's compiled models. The app is sandboxed, so these are in
/// its container, where Finder and Terminal do not look. Read-only; measured off the main actor each time the section
/// appears.
private struct ModelCacheSection: View {
    @State private var usage: ModelCacheUsage?

    var body: some View {
        Section("Model caches") {
            LabeledContent("Core ML cache", value: usage.map { ModelCacheUsage.text($0.coreML) } ?? "Measuring…")
                .accessibilityIdentifier("settings.analysis.coreMLCache")
            LabeledContent("Compiled detector models", value: usage.map { ModelCacheUsage.text($0.compiledModels) } ?? "Measuring…")
                .accessibilityIdentifier("settings.analysis.compiledModels")
            Text("Kept by macOS and the learned detector in the app's own Caches folder. Shown only; nothing is removed here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            usage = await Task.detached(priority: .utility) {
                ModelCacheUsage.appCachesDirectory().map(ModelCacheUsage.measure(appCaches:))
                    ?? ModelCacheUsage(coreML: nil, compiledModels: nil)
            }.value
        }
    }
}

// MARK: - Agents

/// The agent door's switch, status, connection command and new-token button: MacEMUI's shared section on mac4DSTEM's door
/// (`App/AgentDoor/Mac4DSTEMAgentDoor.swift`), with this app's words for what an agent can read.
private struct AgentSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var choosingFolder = false

    var body: some View {
        @Bindable var preferences = preferences
        AgentDoorSettingsSection(door: Mac4DSTEMAgentDoor.shared, isOn: $preferences.agentDoorEnabled,
                                 canSee: "the dataset, its calibration, the result and the diffraction pattern as pictures, the detected disks, "
                                     + "the precipitate objects and the recipe",
                                 runs: $preferences.agentRunsEnabled,
                                 canRun: "move to a scan position, tune the disk detection, press Run and Stop, and open the files of "
                                     + "the Agent folder")
        // The one folder an agent may work in (`App/AgentDoor/AgentFolder.swift`, issue #191).
        Section("Agent folder") {
            LabeledContent("Folder") {
                HStack {
                    Text(AgentFolder.displayPath(bookmark: preferences.agentFolderBookmark) ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { choosingFolder = true }
                        .accessibilityIdentifier("settings.agents.folder.choose")
                    if preferences.agentFolderBookmark != nil {
                        Button("Remove") { preferences.agentFolderBookmark = nil }
                            .accessibilityIdentifier("settings.agents.folder.remove")
                    }
                }
            }
            Toggle("Let agents save results there", isOn: $preferences.agentFolderSavesEnabled)
                .disabled(preferences.agentFolderBookmark == nil || !preferences.agentRunsEnabled)
                .accessibilityIdentifier("settings.agents.folder.saves")
            Text("An agent can list the files in this folder and its subfolders, and, with \"Let agents run analyses\" on, open "
                + "them. With saving on, it can save result pictures there; it never replaces or deletes a file. Nothing outside "
                + "the folder is reached.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result, let bookmark = AgentFolder.bookmark(for: folder) {
                preferences.agentFolderBookmark = bookmark
            }
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
