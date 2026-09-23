//
//  MaterialsProjectSettingsView.swift
//  Role: the Settings window's Materials Project section — the only place
//        the Materials Project API key is entered, since the owner's product
//        decision makes Materials Project the default phase source.
//
//  This file holds only the `Section` content; `UI/SettingsWindow.swift`'s
//  `NavigationSplitView` supplies the surrounding `Form`/sizing under the
//  SAME type name so nothing else has to change: `body` **is** the section,
//  not a section inside a nested Form.
//
//  A `Settings` scene has no dataset window's `AppState` to read — each
//  window owns its own (`mac4DSTEMApp.swift`'s `DatasetWindow`) — and the key
//  is process-wide (one Keychain item), not per-window state, so this view
//  owns its own `MaterialsProjectSettings` rather than reaching into a
//  window's. `MaterialsProjectImportSheet` reloads `appState.materialsProject`
//  itself when it opens, which is what keeps a key saved here visible there.
//
//  `keyDraft` is a `Binding`, not local `@State` (adversarial review, Finding
//  A): `SettingsWindow`'s detail pane rebuilds this view on
//  every sidebar selection (it lives inside a `switch` on the selected
//  section, `UI/SettingsWindow.swift`), so local `@State` here was silently
//  discarded — a typed-but-not-saved key vanished the moment the user left
//  and returned to this section. The draft is hoisted to `SettingsWindow`,
//  the parent that actually outlives the switch.
//
//  Not to be confused with a dataset window's inspector Settings tab
//  (`WorkspaceInspector.swift`'s `InspectorTab.settings`) — that is a room's
//  per-analysis controls; this is the app-wide `Settings` scene (⌘,).
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct MaterialsProjectSettingsView: View {
    @State private var settings = MaterialsProjectSettings()
    @Binding var keyDraft: String
    @State private var actionError: String?

    var body: some View {
        Section("Materials Project API key") {
            SecureField("API key", text: $keyDraft)
                .accessibilityIdentifier("materialsProject.settings.apiKey")
            HStack {
                Button("Save") { save() }
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityIdentifier("materialsProject.settings.save")
                Button("Remove", role: .destructive) { remove() }
                    .disabled(!settings.hasKey)
                    .accessibilityIdentifier("materialsProject.settings.remove")
            }
            Text(settings.hasKey ? "Stored in Keychain" : "No key set")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("materialsProject.settings.status")
            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Sent only to api.materialsproject.org, and only when you fetch a material.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(
                "Get a key at materialsproject.org/api",
                destination: URL(string: "https://materialsproject.org/api")!
            )
            .font(.caption)
        }
    }

    private var trimmedDraft: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            try settings.save(trimmedDraft)
            keyDraft = ""
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try settings.remove()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}
