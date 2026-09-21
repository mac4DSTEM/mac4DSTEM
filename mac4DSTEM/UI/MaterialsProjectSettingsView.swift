//
//  MaterialsProjectSettingsView.swift
//  Role: session S5's Settings scene — the app's first (`mac4DSTEMApp.swift`
//        gains a `Settings { }` scene beside its one `WindowGroup`). The only
//        place the Materials Project API key is entered, since the owner's
//        product decision makes Materials Project the default phase source.
//
//  A `Settings` scene has no dataset window's `AppState` to read — each
//  window owns its own (`mac4DSTEMApp.swift`'s `DatasetWindow`) — and the key
//  is process-wide (one Keychain item), not per-window state, so this view
//  owns its own `MaterialsProjectSettings` rather than reaching into a
//  window's. `MaterialsProjectImportSheet` reloads `appState.materialsProject`
//  itself when it opens, which is what keeps a key saved here visible there.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct MaterialsProjectSettingsView: View {
    @State private var settings = MaterialsProjectSettings()
    @State private var keyDraft = ""
    @State private var actionError: String?

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .frame(
            minWidth: LayoutPolicy.materialsProjectSettingsWidth.min,
            idealWidth: LayoutPolicy.materialsProjectSettingsWidth.ideal
        )
        .padding()
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
