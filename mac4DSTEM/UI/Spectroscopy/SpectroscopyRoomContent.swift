import SwiftUI

/// The room's centre (ADR 056, mock v2.1; spec 2 D-4, D-7): the maps block on top (the grid only) and the spectrum, full width,
/// below it. The two bands never scroll as a whole (`SpectroscopyRoomPlan`): the spectrum is always on screen, the grid is
/// fitted inside the maps block, and only the tile grid scrolls (inside its own area) when its tiles cannot fit. Two dividers
/// are the person's: the spectrum's header row (drag up / down: the maps' share of the height) and a grab zone between the
/// ColorMix and the tile column (drag left / right: the ColorMix's share of the width). Both fractions live on the model
/// (per window, not method state); nil = the plan's own default.
struct SpectroscopyRoomContent: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var mapsStart: CGFloat?
    @State private var mixStart: CGFloat?

    private var headerFloor: CGFloat { LayoutPolicy.paneHeaderHeight + 1 }

    var body: some View {
        GeometryReader { geo in
            let plan = SpectroscopyRoomPlan.make(room: geo.size, headerHeight: headerFloor,
                                                 tileCount: model.gridItems.count, aspect: model.gridAspect,
                                                 mapsFraction: model.mapsFraction, mixFraction: model.mixFraction)
            VStack(spacing: 0) {
                grid(plan)
                    .frame(height: plan.mapsHeight)
                    .clipped()
                SpectrumStripView(model: model, onHeaderDrag: { translation, ended in
                    dragSplit(translation.height, ended: ended, plan: plan, room: geo.size)
                })
                .frame(height: plan.bottomHeight)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    private func grid(_ plan: SpectroscopyRoomPlan.Plan) -> some View {
        MapsGridView(model: model, plan: plan.maps).padding(SpectroscopyRoomPlan.gridPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) { mixHandle(plan) }
    }

    // MARK: dividers

    /// The horizontal divider: the cumulative drag moves the maps' fraction, from where it stood at the drag's start (the
    /// fraction in effect, so a stored value past what fits does not leave a dead zone).
    private func dragSplit(_ dy: CGFloat, ended: Bool, plan: SpectroscopyRoomPlan.Plan, room: CGSize) {
        guard room.height > 0 else { return }
        let start = mapsStart ?? plan.mapsHeight / room.height
        mapsStart = start
        model.mapsFraction = SpectroscopyRoomPlan.fraction(afterDrag: dy, available: room.height, from: start, bottomFloor: headerFloor)
        if ended { mapsStart = nil }
    }

    /// The vertical divider between the ColorMix and the tile column (side-by-side kind only): a 1-pt rule in a grab zone of
    /// `LayoutPolicy.dividerGrabWidth`, centred in the gap, the height of the tile area.
    @ViewBuilder private func mixHandle(_ plan: SpectroscopyRoomPlan.Plan) -> some View {
        let maps = plan.maps
        if maps.kind == .sideBySide, maps.tileArea.width > 0, maps.tileArea.height > 0 {
            let grab = LayoutPolicy.dividerGrabWidth
            let width = plan.gridAvail.width
            Rectangle().fill(.separator).frame(width: 1)
                .frame(width: grab, height: maps.tileArea.height)
                .contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = mixStart ?? maps.colorMix.width / max(width, 1)
                        mixStart = start
                        model.mixFraction = MapGridLayout.mixFraction(afterDrag: value.translation.width, available: width, from: start)
                    }
                    .onEnded { _ in mixStart = nil })
                .accessibilityLabel("Resize the ColorMix")
                .accessibilityIdentifier("spectroscopy.mixDivider")
                .padding(.leading, SpectroscopyRoomPlan.gridPadding + maps.colorMix.maxX + MapGridLayout.gap / 2 - grab / 2)
                .padding(.top, SpectroscopyRoomPlan.gridPadding)
        }
    }
}

#Preview("Room, 1280") { SpectroscopyRoomContent(model: .fixture).frame(width: 980, height: 760) }
#Preview("Room, narrow") { SpectroscopyRoomContent(model: .fixture).frame(width: 600, height: 900) }
