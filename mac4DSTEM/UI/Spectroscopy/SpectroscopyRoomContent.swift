import SwiftUI

/// The room's centre (ADR 056, mock v2.1; spec 2 D-4, D-7): the maps block on top (the grid only) and the spectrum, full width,
/// below it. The two bands never scroll as a whole (`SpectroscopyRoomPlan`): the spectrum is always on screen, the grid is
/// fitted inside the maps block, and only the tile grid scrolls (inside its own area) when its tiles cannot fit. Two dividers
/// are the person's: the spectrum's header row (drag up / down: the maps' share of the height) and a grab zone between the
/// ColorMix and the tile column (drag left / right: the ColorMix's share of the width), and the results panel's edge beside the
/// spectrum (drag left / right: its width). The fractions live on the model (per window, not method state; nil = the plan's own
/// default) and in the scene's storage, so a window comes back as it was left. Above the maps is the header row (region tool,
/// map mode); the results table sits right of the spectrum.
struct SpectroscopyRoomContent: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var mapsStart: CGFloat?
    @State private var mixStart: CGFloat?
    @State private var resultsStart: CGFloat?
    // Scene storage keeps the person's three divider positions (-1: the plan's own default).
    @SceneStorage("spectroscopy.mapsFraction") private var storedMaps = -1.0
    @SceneStorage("spectroscopy.mixFraction") private var storedMix = -1.0
    @SceneStorage("spectroscopy.resultsWidth") private var storedResults = -1.0

    private var headerFloor: CGFloat { LayoutPolicy.paneHeaderHeight + 1 }

    var body: some View {
        GeometryReader { geo in
            let headerRow = SpectroscopyRoomHeader.height
            let body = CGSize(width: geo.size.width, height: max(0, geo.size.height - headerRow))
            let plan = SpectroscopyRoomPlan.make(room: body, headerHeight: headerFloor,
                                                 tileCount: model.gridItems.count, aspect: model.gridAspect,
                                                 mapsFraction: model.mapsFraction, mixFraction: model.mixFraction)
            let resultsWidth = SpectroscopyResultsPanel.width(stored: model.resultsWidth, roomWidth: geo.size.width)
            VStack(spacing: 0) {
                SpectroscopyRoomHeader(model: model)
                grid(plan)
                    .frame(height: plan.mapsHeight)
                    .clipped()
                HStack(spacing: 0) {
                    SpectrumStripView(model: model, onHeaderDrag: { translation, ended in
                        dragSplit(translation.height, ended: ended, plan: plan, room: body)
                    }, onHeaderAdjust: { direction in
                        adjustSplit(direction, plan: plan, room: body)
                    }, headerValue: splitValue(plan, room: body))
                    resultsDivider(width: resultsWidth, room: geo.size.width)
                    SpectroscopyResultsPanel(model: model).frame(width: resultsWidth)
                }
                .frame(height: plan.bottomHeight)
                .overlay(alignment: .top) { Divider() }
            }
            .onAppear { restoreStored() }
            .onChange(of: model.mapsFraction) { storedMaps = model.mapsFraction.map(Double.init) ?? -1 }
            .onChange(of: model.mixFraction) { storedMix = model.mixFraction.map(Double.init) ?? -1 }
            .onChange(of: model.resultsWidth) { storedResults = model.resultsWidth.map(Double.init) ?? -1 }
        }
    }

    /// The stored divider positions back onto the model, once, when the room appears (a value the model already holds wins).
    private func restoreStored() {
        if model.mapsFraction == nil, storedMaps >= 0 { model.mapsFraction = CGFloat(storedMaps) }
        if model.mixFraction == nil, storedMix >= 0 { model.mixFraction = CGFloat(storedMix) }
        if model.resultsWidth == nil, storedResults >= 0 { model.resultsWidth = CGFloat(storedResults) }
    }

    /// The vertical divider between the spectrum and the results table: a 1-pt rule in a grab zone, drag or arrow keys.
    private func resultsDivider(width: CGFloat, room: CGFloat) -> some View {
        Rectangle().fill(.separator).frame(width: 1)
            .frame(width: LayoutPolicy.dividerGrabWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = resultsStart ?? width
                    resultsStart = start
                    model.resultsWidth = SpectroscopyResultsPanel.width(stored: start - value.translation.width, roomWidth: room)
                }
                .onEnded { _ in resultsStart = nil })
            .accessibilityElement()
            .focusable()
            .onKeyPress(.leftArrow) { model.resultsWidth = SpectroscopyResultsPanel.width(stored: width + room * 0.05, roomWidth: room); return .handled }
            .onKeyPress(.rightArrow) { model.resultsWidth = SpectroscopyResultsPanel.width(stored: width - room * 0.05, roomWidth: room); return .handled }
            .accessibilityLabel("Resize the results table")
            .accessibilityValue("\(Int(width)) points wide")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.resultsWidth = SpectroscopyResultsPanel.width(stored: width + room * 0.05, roomWidth: room)
                case .decrement: model.resultsWidth = SpectroscopyResultsPanel.width(stored: width - room * 0.05, roomWidth: room)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("spectroscopy.resultsDivider")
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

    /// Keyboard and VoiceOver adjustments start from the rendered split, so a stored value clipped by the room's current
    /// geometry never creates a dead zone. The same fraction function clamps the requested adjustment as pointer dragging.
    private func adjustSplit(_ direction: AccessibilityAdjustmentDirection, plan: SpectroscopyRoomPlan.Plan, room: CGSize) {
        guard room.height > 0 else { return }
        let current = plan.mapsHeight / room.height
        let sign: CGFloat
        switch direction {
        case .increment: sign = 1
        case .decrement: sign = -1
        @unknown default: return
        }
        // A first increment must clear the maps' visibility floor; otherwise every step starts again at rendered zero.
        let step = plan.mapsHeight == 0 && sign > 0
            ? max(room.height * 0.05, SpectroscopyRoomPlan.minimumMapsHeight + 1)
            : room.height * 0.05
        model.mapsFraction = SpectroscopyRoomPlan.fraction(
            afterDrag: sign * step,
            available: room.height,
            from: current,
            bottomFloor: headerFloor
        )
    }

    private func splitValue(_ plan: SpectroscopyRoomPlan.Plan, room: CGSize) -> String {
        guard room.height > 0 else { return "Maps and spectrum" }
        let mapsPercent = Int((100 * plan.mapsHeight / room.height).rounded())
        return "Maps \(mapsPercent)%, spectrum \(100 - mapsPercent)%"
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
                .accessibilityElement()
                .focusable()
                .onKeyPress(.leftArrow) { adjustMix(.decrement, maps: maps, width: width); return .handled }
                .onKeyPress(.rightArrow) { adjustMix(.increment, maps: maps, width: width); return .handled }
                .accessibilityLabel("Resize the ColorMix")
                .accessibilityValue("\(Int((maps.colorMix.width / max(width, 1) * 100).rounded()))% of map width")
                .accessibilityAdjustableAction { adjustMix($0, maps: maps, width: width) }
                .accessibilityIdentifier("spectroscopy.mixDivider")
                .padding(.leading, SpectroscopyRoomPlan.gridPadding + maps.colorMix.maxX + MapGridLayout.gap / 2 - grab / 2)
                .padding(.top, SpectroscopyRoomPlan.gridPadding)
        }
    }

    private func adjustMix(_ direction: AccessibilityAdjustmentDirection, maps: MapGridLayout.Plan, width: CGFloat) {
        guard width > 0 else { return }
        let sign: CGFloat
        switch direction {
        case .increment: sign = 1
        case .decrement: sign = -1
        @unknown default: return
        }
        let current = maps.colorMix.width / width
        model.mixFraction = MapGridLayout.mixFraction(afterDrag: sign * width * 0.05, available: width, from: current)
    }
}

#Preview("Room, 1280") { SpectroscopyRoomContent(model: .fixture).frame(width: 980, height: 760) }
#Preview("Room, narrow") { SpectroscopyRoomContent(model: .fixture).frame(width: 600, height: 900) }
