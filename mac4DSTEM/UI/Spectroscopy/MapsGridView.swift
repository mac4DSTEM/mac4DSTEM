import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// One entry of the grid beside the ColorMix.
enum MapGridItem: Identifiable {
    case haadf
    case element(MapTile)
    var id: ActiveMap {
        switch self { case .haadf: .haadf; case .element(let t): .element(t.z) }
    }
}

extension SpectroscopyRoomModel {
    /// The scan's grid: the tiles', else the room's own (the HAADF backdrop's).
    var gridSize: (w: Int, h: Int) {
        if let t = tiles.first { return (t.width, t.height) }
        return (gridWidth, gridHeight)
    }
    var hasHAADF: Bool { gridWidth > 0 && backdrop.count == gridWidth * gridHeight }
    /// HAADF first, then the elements.
    var gridItems: [MapGridItem] { (hasHAADF ? [.haadf] : []) + tiles.map { .element($0) } }
    var gridAspect: CGFloat { let g = gridSize; return g.w > 0 && g.h > 0 ? CGFloat(g.w) / CGFloat(g.h) : 1 }
}

/// The maps: the ColorMix large on the left, HAADF and one tile per element beside it, each at the scan's aspect
/// (`MapGridLayout`). The tiles are pickers (spec 2 D-2): the accent outline means "in the ColorMix"; the regions live on the
/// ColorMix only (D-1).
struct MapsGridView: View {
    @Bindable var model: SpectroscopyRoomModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let plan: MapGridLayout.Plan
    @State private var mixCache = ColorMixRasterCache()
    @State private var tileCache = MapTileRasterCache()

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapTileView(model: model, map: .colorMix, title: "ColorMix", image: colorMixImage(), tile: nil)
                .frame(width: plan.colorMix.width, height: plan.colorMix.height)
                .offset(x: plan.colorMix.minX, y: plan.colorMix.minY)
            if !plan.tiles.isEmpty {
                tileGrid.frame(width: plan.tileArea.width, height: plan.tileArea.height, alignment: .topLeading)
                    .offset(x: plan.tileArea.minX, y: plan.tileArea.minY)
            }
        }
        .frame(width: plan.size.width, height: plan.size.height, alignment: .topLeading)
    }

    /// The tiles in their own container: it scrolls along `plan.scroll` when they do not fit, the ColorMix never does.
    @ViewBuilder private var tileGrid: some View {
        let content = ZStack(alignment: .topLeading) {
            ForEach(Array(model.gridItems.enumerated()), id: \.element.id) { i, item in
                if i < plan.tiles.count {
                    let r = plan.tiles[i]
                    tileView(item).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                }
            }
        }
        .frame(width: plan.tileContent.width, height: plan.tileContent.height, alignment: .topLeading)
        .animation(TileMotion.animation(reduceMotion: reduceMotion), value: model.tiles.map(\.id))   // the one animation in the room
        switch plan.scroll {
        case .none: content
        case .vertical: ScrollView(.vertical) { content }
        case .horizontal: ScrollView(.horizontal) { content }
        }
    }

    @ViewBuilder private func tileView(_ item: MapGridItem) -> some View {
        switch item {
        case .haadf:
            MapTileView(model: model, map: .haadf, title: "HAADF", image: haadfImage(), tile: nil)
        case .element(let t):
            MapTileView(model: model, map: .element(t.z), title: PeriodicLayout.symbol(t.z), image: elementImage(t), tile: t)
        }
    }

    private func colorMixImage() -> CGImage? {
        let g = model.gridSize
        var colors: [Int: ColorMixComposite.RGB] = [:]
        var displays: [Int: MapDisplay] = [:]
        var style = Hasher()
        for t in model.tiles where model.mixed.contains(t.z) {
            let c = Self.rgb(model.color(t.z))
            colors[t.z] = c
            let d = model.display(.element(t.z))
            displays[t.z] = d
            style.combine(MapStyle.stamp(color: c, display: d))
        }
        // The HAADF tile's outline: off, the mix sits on black (an empty backdrop is "none").
        let backdrop = model.mixHAADF ? model.backdrop : []
        let key = ColorMixRasterCache.Key(revision: model.tileRevision, mixed: model.mixed, width: g.w, height: g.h,
                                          backdropCount: backdrop.count, style: style.finalize(), mixHAADF: model.mixHAADF)
        return mixCache.image(for: key) {
            ColorMixRaster.image(tiles: model.tiles, mixed: model.mixed, colors: colors, backdrop: backdrop,
                                 width: g.w, height: g.h, displays: displays)
        }
    }

    private func elementImage(_ t: MapTile) -> CGImage? {
        let c = Self.rgb(model.color(t.z)), d = model.display(.element(t.z))
        let key = MapTileRasterCache.Key(revision: model.tileRevision, style: MapStyle.stamp(color: c, display: d), count: t.values.count)
        return tileCache.image(.element(t.z), key: key) { ElementTileRaster.image(tile: t, color: c, display: d) }
    }

    private func haadfImage() -> CGImage? {
        let d = model.display(.haadf), cm = model.haadfColormap
        let key = MapTileRasterCache.Key(revision: model.tileRevision, style: MapStyle.stamp(color: nil, display: d, colormap: cm), count: model.backdrop.count)
        return tileCache.image(.haadf, key: key) {
            ElementTileRaster.haadf(values: model.backdrop, width: model.gridWidth, height: model.gridHeight, colormap: cm, display: d)
        }
    }

    static func rgb(_ c: Color) -> ColorMixComposite.RGB {
        let r = c.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue))
    }
}

private enum TileMetrics {
    static let corner: CGFloat = 6
    static let handle: CGFloat = 6
    static let reach: CGFloat = 7          // a handle's grab radius, points
    static let click: CGFloat = 3          // travel below which a press is a click
    static let chip: CGFloat = 12
}

/// One map: the bitmap at the scan's aspect, its header (name, colour chip), and the outline. A click on an element or HAADF
/// tile picks it into the ColorMix or out of it (the accent outline means "in the ColorMix", the quiet outline "not"); a hover
/// on an element tile highlights its lines in the spectrum. Only the ColorMix carries the live region: a drag draws, moves or
/// resizes it, the pins and the "Region" label sit on it, and so does the scale bar.
struct MapTileView: View {
    @Bindable var model: SpectroscopyRoomModel
    let map: ActiveMap
    let title: String
    let image: CGImage?
    let tile: MapTile?
    @State private var edit: Edit?
    @State private var draft: [PixelPoint] = []
    @State private var closedAt = Date.distantPast
    @FocusState private var focused: Bool

    private enum Edit {
        case draw(from: PixelPoint)
        case move(start: SpectrumRegionShape, from: PixelPoint)
        case handle(RegionHandle, start: SpectrumRegionShape)
    }

    /// Regions live on the ColorMix only (spec 2 D-1).
    static func carriesRegion(_ map: ActiveMap) -> Bool { map == .colorMix }

    private var carriesRegion: Bool { Self.carriesRegion(map) }
    private var inMix: Bool { model.isInMix(map) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                canvas(size)
                if map == .colorMix, !model.tiles.contains(where: { model.mixed.contains($0.z) }) {
                    // A small label on a glass capsule (spec 2 D-8: glass only over a map).
                    Text("Pick elements to map").font(.callout).lineLimit(1).minimumScaleFactor(0.7)
                        .overlayCapsule()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
                if carriesRegion, let px = model.scanPixel, model.gridWidth > 0,
                   let plan = MapScaleBar.plan(pixelSize: px.size, unit: px.unit, pointsPerPixel: size.width / CGFloat(model.gridWidth),
                                               targetPoints: min(64, size.width * 0.3)) {
                    MapScaleBarView(plan: plan)
                }
                if carriesRegion, let a = regionLabelAnchor(size) {
                    Text("Region \u{00B7} \(model.regions.first { $0.id == model.selectedRegion }?.pixels ?? 0) px \u{00B7} live").font(.callout).lineLimit(1)
                        .overlayCapsule()
                        .fixedSize()
                        .position(x: a.x, y: a.y)
                        .allowsHitTesting(false)
                }
                header
                RoundedRectangle(cornerRadius: TileMetrics.corner)
                    .strokeBorder(inMix ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: inMix ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: TileMetrics.corner))
            .onChange(of: model.drawTool) { draft = [] }   // a polygon draft belongs to the polygon tool
        }
        .onContinuousHover { phase in
            guard case .element(let z) = map else { return }
            switch phase {
            case .active: if model.highlightedZ != z { model.highlightedZ = z }
            case .ended: if model.highlightedZ == z { model.highlightedZ = nil }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(inMix ? .isSelected : [])
        .accessibilityLabel(title + (inMix ? ", in the ColorMix" : ""))
        .accessibilityIdentifier("spectroscopy.tile.\(Self.key(map))")
    }

    /// The bitmap: on the ColorMix a drag edits the region, a key press removes it or cancels a draft; on any other tile a click picks.
    @ViewBuilder private func canvas(_ size: CGSize) -> some View {
        let c = Canvas { ctx, sz in draw(ctx, sz) }.contentShape(Rectangle())
        if carriesRegion {
            c.gesture(drag(size))
                .simultaneousGesture(TapGesture(count: 2).onEnded { closePolygon(size) })
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                // Both delete keys. Drive 2026-10-07: `KeyEquivalent.delete` matched only the forward-delete key; the
                // Backspace key arrives as the BS character, so it is matched by its character here.
                .onKeyPress { press in
                    guard press.key == .delete || press.key == .deleteForward || press.characters == "\u{8}" || press.characters == "\u{7F}",
                          let id = RegionKeys.removableID(model.regions) else { return .ignored }
                    model.onRemoveRegion?(id)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !draft.isEmpty else { return .ignored }
                    draft = []
                    return .handled
                }
        } else {
            c.onTapGesture { model.pick(map) }
        }
    }

    static func key(_ m: ActiveMap) -> String {
        switch m { case .haadf: "haadf"; case .colorMix: "colormix"; case .element(let z): PeriodicLayout.symbol(z) }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white).shadow(radius: 1)
            Spacer(minLength: 4)
            if map == .colorMix {
                let mixed = model.tiles.filter { model.mixed.contains($0.z) }.map { PeriodicLayout.symbol($0.z) }
                let notMixed = model.tiles.filter { !model.mixed.contains($0.z) }.map { PeriodicLayout.symbol($0.z) }
                // UX #10: the mixed symbols only; what is not in the mix is in this help.
                Text(ColorMixHeader.text(mixed: mixed)).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1).truncationMode(.head)
                    .help(ColorMixHeader.help(mixed: mixed, notMixed: notMixed))
            } else {
                chip
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(alignment: .top) { LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false) }
        .modifier(HeaderPick(model: model, map: map))
    }

    /// The colour chip is a button on every tile but the ColorMix: it opens its popover and never toggles the mix (the Button
    /// takes its own press; the header's tap below it is for the rest of the row).
    @ViewBuilder private var chip: some View {
        if map != .colorMix { MapDisplayChip(model: model, map: map, title: title) }
    }

    // MARK: drawing

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let g = model.gridSize
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        if let image {
            ctx.draw(ctx.resolve(Image(decorative: image, scale: 1).interpolation(.none)), in: CGRect(origin: .zero, size: size))
        }
        guard carriesRegion, g.w > 0, g.h > 0 else { return }
        let cw = size.width / CGFloat(g.w), ch = size.height / CGFloat(g.h)
        func pt(_ p: PixelPoint) -> CGPoint { CGPoint(x: CGFloat(p.x) * cw, y: CGFloat(p.y) * ch) }
        func rect(_ r: PixelRect) -> CGRect { CGRect(x: CGFloat(r.x0) * cw, y: CGFloat(r.y0) * ch, width: CGFloat(r.width) * cw, height: CGFloat(r.height) * ch) }
        let dash = StrokeStyle(lineWidth: 1.2, dash: [4, 3])
        func handleDot(_ p: CGPoint) {
            let r = CGRect(x: p.x - TileMetrics.handle / 2, y: p.y - TileMetrics.handle / 2, width: TileMetrics.handle, height: TileMetrics.handle)
            ctx.fill(Path(r), with: .color(.white)); ctx.stroke(Path(r), with: .color(.black.opacity(0.6)), lineWidth: 0.5)
        }
        if let shape = model.regionOutline {
            switch shape {
            case .rectangle(let r), .ellipse(let r):
                let rr = rect(r)
                ctx.stroke(shape.isEllipse ? Path(ellipseIn: rr) : Path(rr), with: .color(.white), style: dash)
                for p in [CGPoint(x: rr.minX, y: rr.minY), CGPoint(x: rr.midX, y: rr.minY), CGPoint(x: rr.maxX, y: rr.minY),
                          CGPoint(x: rr.minX, y: rr.midY), CGPoint(x: rr.maxX, y: rr.midY),
                          CGPoint(x: rr.minX, y: rr.maxY), CGPoint(x: rr.midX, y: rr.maxY), CGPoint(x: rr.maxX, y: rr.maxY)] { handleDot(p) }
            case .polygon(let v):
                var p = Path()
                for (i, q) in v.enumerated() { i == 0 ? p.move(to: pt(q)) : p.addLine(to: pt(q)) }
                p.closeSubpath()
                ctx.stroke(p, with: .color(.white), style: dash)
                for q in v { handleDot(pt(q)) }
            }
        }
        if model.layers.pins {
            for pin in model.pins {   // a pinned region stays visible on the map, faint, in the pin's own colour
                guard let shape = pin.shape else { continue }
                var path = Path()
                switch shape {
                case .rectangle(let r): path = Path(rect(r))
                case .ellipse(let r): path = Path(ellipseIn: rect(r))
                case .polygon(let v):
                    for (i, q) in v.enumerated() { i == 0 ? path.move(to: pt(q)) : path.addLine(to: pt(q)) }
                    path.closeSubpath()
                }
                ctx.stroke(path, with: .color(pin.tint.opacity(SpectrumLayers.pinOpacity)), lineWidth: 1.2)
            }
        }
        if draft.count > 0 {
            var p = Path()
            for (i, q) in draft.enumerated() { i == 0 ? p.move(to: pt(q)) : p.addLine(to: pt(q)) }
            ctx.stroke(p, with: .color(.white), style: dash)
            for q in draft { handleDot(pt(q)) }
        }
    }

    /// Where the live region's label sits (its centre-left), above the region's top edge; nil without a region.
    private func regionLabelAnchor(_ size: CGSize) -> CGPoint? {
        let g = model.gridSize
        guard g.w > 0, g.h > 0, let shape = model.regionOutline else { return nil }
        let cw = size.width / CGFloat(g.w), ch = size.height / CGFloat(g.h)
        let top: CGPoint
        switch shape {
        case .rectangle(let r), .ellipse(let r): top = CGPoint(x: CGFloat(r.x0) * cw, y: CGFloat(r.y0) * ch)
        case .polygon(let v):
            guard let t = v.min(by: { $0.y < $1.y }) else { return nil }
            top = CGPoint(x: CGFloat(t.x) * cw, y: CGFloat(t.y) * ch)
        }
        // The capsule is about 120 x 20 pt; `position` takes its centre.
        return CGPoint(x: min(max(top.x + 60, 64), max(size.width - 64, 64)), y: max(top.y - 8, 28))
    }

    // MARK: gestures

    private func drag(_ size: CGSize) -> some Gesture {
        let g = model.gridSize
        func point(_ p: CGPoint) -> PixelPoint {
            guard size.width > 0, size.height > 0 else { return PixelPoint(x: 0, y: 0) }
            return PixelPoint(x: Double(min(max(p.x / size.width, 0), 1)) * Double(g.w), y: Double(min(max(p.y / size.height, 0), 1)) * Double(g.h))
        }
        let tol = g.w > 0 && size.width > 0 ? Double(TileMetrics.reach / (size.width / CGFloat(g.w))) : 1
        return DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard g.w > 0, g.h > 0 else { return }
                if edit == nil {
                    focused = true
                    let start = point(v.startLocation)
                    if let shape = model.regionOutline {
                        switch RegionEditing.hit(shape, at: start, tolerance: tol) {
                        case .handle(let h): edit = .handle(h, start: shape)
                        case .inside: edit = .move(start: shape, from: start)
                        case .outside: edit = .draw(from: start)
                        }
                    } else { edit = .draw(from: start) }
                }
                guard hypot(v.translation.width, v.translation.height) >= TileMetrics.click else { return }
                if let shape = shape(for: edit, at: point(v.location), grid: g) { model.onRegionEdit?(shape, false) }
            }
            .onEnded { v in
                defer { edit = nil }
                guard g.w > 0, g.h > 0 else { return }
                if hypot(v.translation.width, v.translation.height) < TileMetrics.click {
                    if case .draw = edit, model.drawTool == .polygon { addVertex(point(v.startLocation), tol: tol, grid: g) }
                    return
                }
                if let shape = shape(for: edit, at: point(v.location), grid: g) { model.onRegionEdit?(shape, true) }
            }
    }

    private func shape(for edit: Edit?, at p: PixelPoint, grid g: (w: Int, h: Int)) -> SpectrumRegionShape? {
        switch edit {
        case .draw(let from)?:
            return RegionEditing.drawnRect(from: from, to: p, grid: g).flatMap { RegionDrawing.shape(tool: model.drawTool, rect: $0) }
        case .move(let start, let from)?:
            return RegionEditing.moved(start, dx: Int((p.x - from.x).rounded()), dy: Int((p.y - from.y).rounded()), grid: g)
        case .handle(let h, let start)?:
            return RegionEditing.edited(start, handle: h, to: p, grid: g)
        case nil: return nil
        }
    }

    /// Polygon tool: a click adds a corner; a click on the first corner (three or more set) closes it into the live region.
    /// The second click of a closing click pair is not a corner.
    private func addVertex(_ p: PixelPoint, tol: Double, grid g: (w: Int, h: Int)) {
        guard Date().timeIntervalSince(closedAt) > 0.4 else { return }
        if draft.count >= 3, let first = draft.first, max(abs(p.x - first.x), abs(p.y - first.y)) <= tol {
            commit(draft)
        } else {
            draft.append(PixelPoint(x: min(max(p.x, 0), Double(g.w)), y: min(max(p.y, 0), Double(g.h))))
        }
    }

    /// A double-click closes the draft (three or more distinct corners).
    private func closePolygon(_ size: CGSize) {
        let g = model.gridSize
        let tol = g.w > 0 && size.width > 0 ? Double(TileMetrics.reach / (size.width / CGFloat(g.w))) : 1
        if let v = PolygonDraft.closing(draft, tolerance: tol) { commit(v) }
    }

    private func commit(_ corners: [PixelPoint]) {
        draft = []
        closedAt = Date()
        model.onRegionEdit?(.polygon(corners), true)
    }
}

/// Region-editing rules that need no view (spec 2 D-16).
nonisolated enum PolygonDraft {
    /// The corners a double-click closes: a corner within `tolerance` (grid pixels) of the one before it is the click pair's
    /// second click and is dropped; nil when fewer than three distinct corners remain.
    static func closing(_ draft: [PixelPoint], tolerance: Double) -> [PixelPoint]? {
        var out: [PixelPoint] = []
        for p in draft {
            if let l = out.last, max(abs(p.x - l.x), abs(p.y - l.y)) <= tolerance { continue }
            out.append(p)
        }
        return out.count >= 3 ? out : nil
    }
}

nonisolated enum RegionKeys {
    /// The region ⌫ removes: the live region the person drew (never the whole map).
    static func removableID(_ regions: [RegionSummary]) -> Int? { regions.first { $0.isDrawn }?.id }
}

nonisolated enum RegionDrawing {
    /// The shape a drag makes with the tool: the polygon tool takes clicks, not drags. Exhaustive on purpose: a new tool must say here
    /// what its drag draws.
    static func shape(tool: DrawTool, rect: PixelRect) -> SpectrumRegionShape? {
        switch tool {
        case .rectangle: .rectangle(rect)
        case .ellipse: .ellipse(rect)
        case .polygon: nil
        }
    }
}

/// A click anywhere on a non-ColorMix tile's header row picks the tile; the chip's Button takes its own press first.
private struct HeaderPick: ViewModifier {
    @Bindable var model: SpectroscopyRoomModel
    let map: ActiveMap
    func body(content: Content) -> some View {
        if map == .colorMix { content }
        else { content.contentShape(Rectangle()).onTapGesture { model.pick(map) } }
    }
}

extension SpectrumRegionShape {
    var isEllipse: Bool { if case .ellipse = self { true } else { false } }
}

// MARK: - Colour, contrast and gamma of the active map

/// The chip on a tile's header: a swatch of its colour; its popover is the app's per-pane display popover
/// (`ColormapChip`: a grouped Form with the histogram's contrast handles and gamma), here for one map. Elements get a
/// `ColorPicker` (the tile and the ColorMix follow); HAADF gets its colormap.
struct MapDisplayChip: View {
    @Bindable var model: SpectroscopyRoomModel
    let map: ActiveMap
    let title: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: { swatch.frame(minWidth: 20, minHeight: 20).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help("Colour, contrast and gamma of \(title)")
            .accessibilityLabel("Display of \(title)")
            .accessibilityIdentifier("spectroscopy.mapDisplay")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                MapDisplayPopover(model: model, map: map)
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .frame(width: LayoutPolicy.popoverWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }

    @ViewBuilder private var swatch: some View {
        switch map {
        case .element(let z):
            RoundedRectangle(cornerRadius: 2).fill(model.color(z)).frame(width: TileMetrics.chip, height: TileMetrics.chip)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.8), lineWidth: 0.5))
        default:
            Image(nsImage: Colormaps.swatch(model.haadfColormap)).clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(width: TileMetrics.chip * 2, height: TileMetrics.chip)
        }
    }
}

extension Binding where Value == Float {
    var mapGammaDouble: Binding<Double> { Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Float($0) }) }
}

extension SpectroscopyRoomModel {
    /// The histogram's real values (spec 2 D-13): an element map's counts at value 1 (`MapTile.scale`); the HAADF is shown as its
    /// own 0…1 intensity, so scale 1 and no unit.
    func histogramScale(_ map: ActiveMap) -> Float {
        if case .element(let z) = map, let t = tiles.first(where: { $0.z == z }), t.scale > 0 { return t.scale }
        return 1
    }
    func histogramUnit(_ map: ActiveMap) -> String {
        if case .element = map { return "counts" }
        return ""
    }
    /// One map's contrast window and gamma as a binding; the identity is stored as absent. Setting one map's display never
    /// touches another's (`mapDisplays` is keyed by the map).
    func displayBinding(_ map: ActiveMap) -> Binding<MapDisplay> {
        Binding(get: { self.display(map) }, set: { self.mapDisplays[map] = $0 == self.defaultDisplay(map) ? nil : $0 })
    }
    /// The map's own values, the histogram's input.
    func pixels(of map: ActiveMap) -> [Float] {
        switch map {
        case .haadf: backdrop
        case .element(let z): tiles.first { $0.z == z }?.values ?? []
        case .colorMix: []
        }
    }
    func colorBinding(_ z: Int) -> Binding<Color> { Binding(get: { self.color(z) }, set: { self.elementColors[z] = $0 }) }
    func mapTitle(_ map: ActiveMap) -> String {
        switch map { case .haadf: "HAADF"; case .colorMix: "ColorMix"; case .element(let z): PeriodicLayout.symbol(z) }
    }
}

struct MapDisplayPopover: View {
    @Bindable var model: SpectroscopyRoomModel
    let map: ActiveMap

    var body: some View {
        let display = model.displayBinding(map)
        let pixels = model.pixels(of: map)
        Form {
            Section {
                switch map {
                case .element(let z):
                    ColorPicker("Colour", selection: model.colorBinding(z), supportsOpacity: false)
                case .haadf:
                    Picker("Colormap", selection: $model.haadfColormap) { ColormapChoices() }.pickerStyle(.menu)
                case .colorMix: EmptyView()
                }
            }
            if !pixels.isEmpty {
                Section("Histogram") {
                    HistogramView(pixels: pixels, version: model.tileRevision, rangeLo: display.lo, rangeHi: display.hi,
                                  scale: model.histogramScale(map), unit: model.histogramUnit(map))
                        .help("Drag the handles to set this map's contrast window.")
                    AdjustmentSlider("Gamma", value: display.gamma.mapGammaDouble, in: 0.2...3, defaultValue: 1.0)
                }
            }
        }
    }
}

/// The HAADF colormap menu's items, each with its swatch.
struct ColormapChoices: View {
    var body: some View {
        ForEach(ColormapKind.allCases) { kind in
            Label { Text(kind.displayName) } icon: { Image(nsImage: Colormaps.swatch(kind)).clipShape(RoundedRectangle(cornerRadius: 2)) }.tag(kind)
        }
    }
}

extension SpectroscopyRoomModel {
    /// A click on a tile (spec 2 D-2): an element goes in or out of the ColorMix, the HAADF tile toggles the backdrop under it;
    /// the ColorMix itself is not a picker. A click on an element also highlights its lines (D-15).
    func pick(_ map: ActiveMap) {
        switch map {
        case .element(let z): toggleMix(z); highlightedZ = z
        case .haadf: mixHAADF.toggle()
        case .colorMix: break
        }
    }
    /// What the tile's accent outline shows: the element is in the mix, or the HAADF backdrop is on.
    func isInMix(_ map: ActiveMap) -> Bool {
        switch map {
        case .element(let z): mixed.contains(z)
        case .haadf: mixHAADF
        case .colorMix: false
        }
    }
}

/// The one animation in the room (UX #12): tiles moving when one comes or goes. Reduce Motion: none.
enum TileMotion {
    static func animation(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy }
}

/// The ColorMix header: the mixed symbols, no cap; what is not picked into the mix is named in the header's help (a picked
/// element whose line is not a measurement starts out of the mix, so a missing colour is explained, not silent).
nonisolated enum ColorMixHeader {
    static func text(mixed: [String]) -> String { mixed.joined(separator: " \u{00B7} ") }
    static func help(mixed: [String], notMixed: [String]) -> String {
        let base = text(mixed: mixed)
        guard !notMixed.isEmpty else { return base.isEmpty ? "The ColorMix: click an element's tile to add it." : "The ColorMix: " + base }
        let off = notMixed.joined(separator: ", ") + " not ticked"
        return "The ColorMix: " + (base.isEmpty ? off : base + " (" + off + ")")
    }
}

extension View {
    /// A glass capsule for text drawn over a map (spec 2 D-8, the only glass in the room): dark whatever the appearance, so it reads on any map.
    func overlayCapsule() -> some View {
        self.padding(.horizontal, 10).padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .environment(\.colorScheme, .dark)
    }
}
