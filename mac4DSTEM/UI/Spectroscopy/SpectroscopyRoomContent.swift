import ShellLayout
import ShellSpectroscopy
import SwiftUI

/// The room's centre (the corrected design, 2026-10-22): the maps on top and the lower pane (the spectrum beside the results table) below, divided by
/// MacEMUI's `VerticalPaneSplit`; the divider is the person's and the scene remembers it. A one-pixel image has no maps and the lower pane fills the room.
/// There is no header strip: the region tool and the map mode are in the inspector (Tools, Maps), the shortcuts in the Analysis menu.
struct SpectroscopyRoomContent: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        if model.gridSize.w * model.gridSize.h == 1 {
            lower
        } else {
            VerticalPaneSplit(storageKey: "spectroscopy.lowerSplit", defaultFraction: 0.58, resizeLabel: "Resize the maps and the spectrum", topName: "Maps",
                              minimumTop: 120, minimumBottom: 160) {
                SpectroscopyMapsBlock(model: model).padding(8)
            } bottom: {
                lower
            }
        }
    }

    /// The spectrum with the results table to its right, divided by MacEMUI's `HorizontalPaneSplit`.
    private var lower: some View {
        HorizontalPaneSplit(storageKey: "spectroscopy.resultsSplit", defaultFraction: 0.66, resizeLabel: "Resize the spectrum and the results",
                            leadingName: "Spectrum", minimumLeading: 320, minimumTrailing: 240) {
            SpectrumStripView(model: model)
        } trailing: {
            SpectroscopyResultsPanel(model: model)
        }
    }
}

#Preview("Room, 1280") { SpectroscopyRoomContent(model: .fixture).frame(width: 980, height: 760) }
#Preview("Room, narrow") { SpectroscopyRoomContent(model: .fixture).frame(width: 600, height: 900) }
