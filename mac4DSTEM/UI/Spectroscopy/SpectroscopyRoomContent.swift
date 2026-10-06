import SwiftUI

/// The room's centre (ADR 056, mock v2.1): the maps block on top, the spectrum strip and the quantification panel side by
/// side below. The two bands never scroll as a whole (`SpectroscopyRoomPlan`): the spectrum and the table are always on
/// screen, the grid is fitted inside the maps block, and only the tile grid scrolls (inside its own area) when its tiles cannot fit.
struct SpectroscopyRoomContent: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        GeometryReader { geo in
            let plan = SpectroscopyRoomPlan.make(room: geo.size, headerHeight: LayoutPolicy.paneHeaderHeight + 1,
                                                 tileCount: model.gridItems.count, aspect: model.gridAspect)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    MapsHeader(model: model)
                    Divider()
                    grid(plan)
                }
                .frame(height: plan.mapsHeight)
                .clipped()
                Divider()
                HStack(spacing: 0) {
                    SpectrumStripView(model: model).frame(maxWidth: .infinity)
                    Divider()
                    QuantPanelView(model: model).frame(width: plan.quantWidth)
                }
                .frame(height: plan.bottomHeight)
            }
        }
    }

    private func grid(_ plan: SpectroscopyRoomPlan.Plan) -> some View {
        MapsGridView(model: model, plan: plan.maps).padding(SpectroscopyRoomPlan.gridPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Room, 1280") { SpectroscopyRoomContent(model: .fixture).frame(width: 980, height: 760) }
#Preview("Room, narrow") { SpectroscopyRoomContent(model: .fixture).frame(width: 600, height: 900) }
