import ShellLayout
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
#endif

/// The results table beside the spectrum (design D3): the rows, the unvalidated badge, the caveat and the Method line of the
/// quantification, in the room with the data they describe. The content is `ResultsSection`'s (it left the inspector, which holds
/// settings only); the width is the room's `HorizontalPaneSplit`'s.
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
}
