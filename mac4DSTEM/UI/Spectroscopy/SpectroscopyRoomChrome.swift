import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
#endif

/// The room's header row (workspace alignment design 2026-10-22, D2): the two controls that act on what the maps draw, the region
/// tool and the map mode, where they are used (they were a click and a scroll away in the inspector), at the height every 4D pane
/// header has. The verb is the toolbar's (Quantify); a fitted run is said here as plain text with a check, never as a button.
struct SpectroscopyRoomHeader: View {
    @Bindable var model: SpectroscopyRoomModel

    static let height = LayoutPolicy.paneHeaderHeight

    var body: some View {
        HStack(spacing: 14) {
            GlassChipGroup(chips: RegionSection.toolChips, mode: .single, selection: RegionSection.toolSelection(model),
                           identifier: "spectroscopy.regionTool")
            GlassChipGroup(chips: ElementsSection.mapChips(quantified: model.hasFit), mode: .single,
                           selection: ElementsSection.mapSelection(model), identifier: "spectroscopy.mapMode")
            Spacer(minLength: 8)
            if let status = Self.statusText(model) {
                Label(status, systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("spectroscopy.header.status")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectroscopy.header")
    }

    /// "Quantified" once the region has been fitted, nil before: a state, so it is text.
    static func statusText(_ model: SpectroscopyRoomModel) -> String? { model.hasFit && !model.results.isEmpty ? "Quantified" : nil }
}

/// The results table beside the spectrum (design D3): the rows, the unvalidated badge, the caveat and the Method line of the
/// quantification, in the room with the data they describe. The content is `ResultsSection`'s (it left the inspector, which holds
/// settings only); the width is the person's (a stored fraction, arrow keys on the divider).
struct SpectroscopyResultsPanel: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Results").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).frame(height: LayoutPolicy.paneHeaderHeight, alignment: .leading)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                    ResultsSection(model: model)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectroscopy.results")
    }

    /// The panel's width in a room `roomWidth` wide: the stored one, at least 240 and at most 45 % of the room; the default 320.
    static func width(stored: CGFloat?, roomWidth: CGFloat) -> CGFloat {
        min(max(stored ?? 320, 240), max(240, roomWidth * 0.45))
    }
}
