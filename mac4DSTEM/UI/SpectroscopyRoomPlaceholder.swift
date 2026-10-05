import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// PLACEHOLDERS (v5.0 WP2 lane R). The Spectroscopy room's real views — the
// map, the spectrum plot, the periodic table, the results table and each
// step's inspector — are lane V's (`UI/Spectroscopy/`), wired in by R2. These
// stand in so the shell can be built and seen: plain, labelled, and saying
// nothing about the data that the data has not said.

/// The centre column in the Spectroscopy room.
struct SpectroscopyRoomPlaceholder: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let metadata = appState.spectroscopy.metadata {
            ContentUnavailableView {
                Label("Spectroscopy · \(appState.spectroscopy.selectedStep.title)",
                      systemImage: appState.spectroscopy.selectedStep.systemImage)
            } description: {
                Text(SpectroscopyPlaceholderFormat.summary(metadata))
                if let note = SpectroscopyPlaceholderFormat.registrationNote(hasFourDCube: appState.hasDataset) {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("spectroscopy.notRegistered")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("spectroscopy.placeholder")
        } else {
            ContentUnavailableView(
                "No spectrum image",
                systemImage: WorkspaceArea.spectroscopy.systemImage,
                description: Text("Open an EDX spectrum image to work in this room.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("spectroscopy.noSpectrumImage")
        }
    }
}

/// The inspector's Settings tab in the Spectroscopy room: the selected step.
struct SpectroscopyInspectorPlaceholder: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let step = appState.spectroscopy.selectedStep
        InspectorSection(step.title) {
            InspectorNote("This step's controls are not built yet.")
        }
        .accessibilityIdentifier("spectroscopy.inspector.\(step.rawValue)")
    }
}

/// The Settings tab in a window that holds only a spectrum image: the
/// Spectroscopy room's step, or one line saying there is nothing to set — the
/// 4D rooms' settings (and Results', which are about 4D products) do not apply.
enum SpectrumOnlySettings: Equatable {
    case step
    case note(String)

    static func content(for area: WorkspaceArea) -> SpectrumOnlySettings {
        area == .spectroscopy
            ? .step
            : .note("Nothing to set here for a spectrum image yet.")
    }
}

struct SpectrumOnlySettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutPolicy.inspectorSectionSpacing) {
                switch SpectrumOnlySettings.content(for: appState.navigation.workspaceArea) {
                case .step: WorkspaceSettings()
                case .note(let text):
                    InspectorNote(text).accessibilityIdentifier("inspector.spectrumOnly.note")
                }
            }
            .padding()
        }
        .environment(\.inspectorScope, "settings")
    }
}

/// A 4D room in a window that holds only a spectrum image. The sidebar
/// disables these rooms and `selectWorkspace` declines them, so this is the
/// backstop, not a destination.
struct FourDRoomUnavailable: View {
    var body: some View {
        ContentUnavailableView(
            "No 4D-STEM scan in this window",
            systemImage: "square.stack.3d.up.slash",
            description: Text("This window holds a spectrum image only.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("workspace.noFourDCube")
    }
}

/// Results in a spectrum-only window, until quantification (WP3) produces any.
struct SpectrumOnlyResultsPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No Results Yet",
            systemImage: WorkspaceArea.results.systemImage,
            description: Text("Quantified regions of this spectrum image will appear here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("results.spectrumOnly.empty")
    }
}

/// The Info tab for a spectrum image: what the file says it is.
struct SpectrumImageInfoSection: View {
    let metadata: SpectrumImageMetadata

    var body: some View {
        InspectorSection("Spectrum image") {
            InspectorValueRow("File", metadata.fileName)
            InspectorValueRow("Scan", "\(metadata.scanWidth) × \(metadata.scanHeight) px", mono: true)
            InspectorValueRow("Channels", "\(metadata.channelCount)", mono: true)
            InspectorValueRow("Energy axis", SpectroscopyPlaceholderFormat.energyAxis(metadata), mono: true)
        }
    }
}

enum SpectroscopyPlaceholderFormat {
    /// A spectrum image beside a 4D cube is not registered to its scan: the
    /// registration record (M2, ADR 053 item 4) comes with WP3, and until then
    /// no pixel of one may be read as a pixel of the other.
    static func registrationNote(hasFourDCube: Bool) -> String? {
        hasFourDCube ? "Not registered to the 4D scan: the registration record comes with WP3." : nil
    }

    /// "64 × 64 px · 2048 channels · 0–20.48 keV".
    static func summary(_ m: SpectrumImageMetadata) -> String {
        "\(m.scanWidth) × \(m.scanHeight) px · \(m.channelCount) channels · \(energyAxis(m))"
    }

    /// The axis as the file states it, first channel to the end of the last.
    static func energyAxis(_ m: SpectrumImageMetadata) -> String {
        let start = m.energyOffsetEV / 1000
        let end = (m.energyOffsetEV + Double(m.channelCount) * m.energyDispersionEV) / 1000
        return "\(start.formatted(.number.precision(.fractionLength(0...3))))–"
            + "\(end.formatted(.number.precision(.fractionLength(0...3)))) keV"
    }
}
