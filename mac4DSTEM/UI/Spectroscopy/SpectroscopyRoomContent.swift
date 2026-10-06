import SwiftUI

/// The room's centre (ADR 056, mock v2.1): the maps grid on top, the spectrum strip and the quantification panel side by side
/// below. Below `SpectroscopyLayout.narrowThreshold` of content the grid stacks (ColorMix across, tiles two by two), and the
/// whole room scrolls.
struct SpectroscopyRoomContent: View {
    @Bindable var model: SpectroscopyRoomModel

    private enum Metrics {
        static let mapsFraction: CGFloat = 0.58            // of the room's height (the mock's grid is 51 to 57 %)
        static let quantWidth: (min: CGFloat, fraction: CGFloat, max: CGFloat) = (300, 0.36, 420)
        static let stripHeight: CGFloat = 300
        static let narrowQuantHeight: CGFloat = 280
        static let gridPadding: CGFloat = 8
    }

    var body: some View {
        GeometryReader { geo in
            if SpectroscopyLayout.isNarrow(contentWidth: geo.size.width) { narrow(geo.size) } else {
                let l = MapGridLayout.layout(tileCount: model.gridItems.count, aspect: model.gridAspect, in: wideAvail(geo.size),
                                             maxColorMixHeight: SpectroscopyLayout.narrowColorMixHeight(roomHeight: geo.size.height))
                if l.stacked { narrow(geo.size) } else { wide(geo.size, arrangement: l.arrangement) }
            }
        }
    }

    private func wideAvail(_ size: CGSize) -> CGSize {
        CGSize(width: size.width - 2 * Metrics.gridPadding,
               height: size.height * Metrics.mapsFraction - LayoutPolicy.paneHeaderHeight - 1 - 2 * Metrics.gridPadding)
    }

    private func wide(_ size: CGSize, arrangement: MapGridLayout.Arrangement) -> some View {
        let mapsHeight = size.height * Metrics.mapsFraction
        let quantWidth = min(max(size.width * Metrics.quantWidth.fraction, Metrics.quantWidth.min), Metrics.quantWidth.max)
        return VStack(spacing: 0) {
            MapsHeader(model: model)
            Divider()
            MapsGridView(model: model, arrangement: arrangement)
                .padding(Metrics.gridPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack(spacing: 0) {
                SpectrumStripView(model: model).frame(maxWidth: .infinity)
                Divider()
                QuantPanelView(model: model).frame(width: quantWidth)
            }
            .frame(height: max(size.height - mapsHeight, 0))
        }
    }

    private func narrow(_ size: CGSize) -> some View {
        let width = size.width - 2 * Metrics.gridPadding
        let arrangement = MapGridLayout.stacked(tileCount: model.gridItems.count, aspect: model.gridAspect, width: width,
                                                maxColorMixHeight: SpectroscopyLayout.narrowColorMixHeight(roomHeight: size.height))
        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                MapsHeader(model: model)
                Divider()
                MapsGridView(model: model, arrangement: arrangement).padding(Metrics.gridPadding)
                Divider()
                SpectrumStripView(model: model).frame(height: Metrics.stripHeight)
                Divider()
                QuantPanelView(model: model).frame(height: Metrics.narrowQuantHeight)
            }
        }
    }
}

#Preview("Room, 1280") { SpectroscopyRoomContent(model: .fixture).frame(width: 980, height: 760) }
#Preview("Room, narrow") { SpectroscopyRoomContent(model: .fixture).frame(width: 600, height: 900) }
