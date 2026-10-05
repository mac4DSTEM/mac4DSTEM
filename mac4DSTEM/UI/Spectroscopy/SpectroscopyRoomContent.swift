import SwiftUI

/// The room's centre: map + results on top, the spectrum full width below (mock screen 1).
/// Below `SpectroscopyLayout.narrowThreshold` of content the results stack under the map and
/// the spectrum's toggles fold into "Show" (ADR 055).
struct SpectroscopyRoomContent: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        GeometryReader { geo in
            let narrow = SpectroscopyLayout.isNarrow(contentWidth: geo.size.width)
            VStack(spacing: 0) {
                Group {
                    if narrow {
                        VStack(spacing: 0) {
                            ColorMixMapView(model: model)
                            Divider()
                            SpectroscopyResultsTable(model: model)
                        }
                    } else {
                        HStack(spacing: 0) {
                            ColorMixMapView(model: model).frame(width: LayoutPolicy.thumbnailMaximumHeight + 16)
                            Divider()
                            SpectroscopyResultsTable(model: model).frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: narrow ? geo.size.height * 0.5 : min(geo.size.height * 0.45, 400))
                Divider()
                SpectrumPlotView(model: model, narrow: narrow).frame(maxHeight: .infinity)
            }
        }
    }
}

#Preview("Room, 1280") { SpectroscopyRoomContent(model: .fixture).frame(width: 980, height: 760) }
#Preview("Room, narrow") { SpectroscopyRoomContent(model: .fixture).frame(width: 600, height: 900) }
