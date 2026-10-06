import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The maps grid's header (ADR 056): what the maps show, and the region tools. The mode switch lists only what a map can
/// be: int and net counts. wt% and at% are computed on regions, in the quantification panel, never per pixel (ADR 054 item
/// 3), so they are not offered here and the switch's help says where they are.
struct MapsHeader: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Maps").fontWeight(.semibold)
                Text("· \(model.mapUnits)").foregroundStyle(.secondary)
            }.font(.callout).lineLimit(1)
            Spacer(minLength: 4)
            Picker("Map shows", selection: $model.mapMode) {
                ForEach(MapMode.allCases.filter(\.isAvailable), id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            .help("int: the line's window sum. net: less its background windows. wt% and at% are computed on regions (the quantification panel), not per pixel.")
            .accessibilityIdentifier("spectroscopy.mapMode")
            Picker("Region tool", selection: $model.drawTool) {
                ForEach(DrawTool.allCases, id: \.self) { Image(systemName: $0.symbol).tag($0).help($0 == .rectangle ? "Rectangle: drag on a map" : "Polygon: click the corners, then the first corner again") }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            .accessibilityIdentifier("spectroscopy.regionTool")
        }
        .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }
}

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
    /// HAADF first, then the elements (the quantified ones, then Auto ID's proposals).
    var gridItems: [MapGridItem] { (hasHAADF ? [.haadf] : []) + tiles.map { .element($0) } }
    var gridAspect: CGFloat { let g = gridSize; return g.w > 0 && g.h > 0 ? CGFloat(g.w) / CGFloat(g.h) : 1 }
}

/// The maps: the ColorMix large on the left, HAADF and one tile per element beside it, each at the scan's aspect
/// (`MapGridLayout`). Exactly one tile is active (the accent outline); the tick on an element tile means "in the ColorMix".
struct MapsGridView: View {
    @Bindable var model: SpectroscopyRoomModel
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
        for t in model.tiles where model.mixed.contains(t.z) && !t.proposed {
            let c = Self.rgb(model.color(t.z))
            colors[t.z] = c
            let d = model.display(.element(t.z))
            displays[t.z] = d
            style.combine(MapStyle.stamp(color: c, display: d))
        }
        let key = ColorMixRasterCache.Key(revision: model.tileRevision, mixed: model.mixed, width: g.w, height: g.h,
                                          backdropCount: model.backdrop.count, style: style.finalize())
        return mixCache.image(for: key) {
            ColorMixRaster.image(tiles: model.tiles, mixed: model.mixed, colors: colors, backdrop: model.backdrop,
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
    static let corner: CGFloat = 5
    static let handle: CGFloat = 6
    static let reach: CGFloat = 7          // a handle's grab radius, points
    static let click: CGFloat = 3          // travel below which a press is a click
    static let chip: CGFloat = 12
}

/// One map: the bitmap at the scan's aspect, its header (tick, name, colour chip, or "proposed · Accept"), the accent outline
/// when it is the active map, and the live region on it. A press on any tile makes it active; a drag draws, moves or resizes
/// the one live region (drawing on a tile makes it active too).
struct MapTileView: View {
    @Bindable var model: SpectroscopyRoomModel
    let map: ActiveMap
    let title: String
    let image: CGImage?
    let tile: MapTile?
    @State private var edit: Edit?
    @State private var draft: [PixelPoint] = []

    private enum Edit {
        case draw(from: PixelPoint)
        case move(start: SpectrumRegionShape, from: PixelPoint)
        case handle(RegionHandle, start: SpectrumRegionShape)
    }

    private var isActive: Bool { model.active == map }
    private var proposed: Bool { tile?.proposed == true }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { ctx, sz in draw(ctx, sz) }
                    .opacity(proposed ? 0.55 : 1)
                    .contentShape(Rectangle())
                    .gesture(drag(size))
                if map == .colorMix, !model.tiles.contains(where: { model.mixed.contains($0.z) && !$0.proposed }) {
                    // A small label on a quiet capsule: it reads on the grey scan image that stands in, whatever its brightness.
                    Text("Pick elements to map").font(.caption).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
                if (map == .colorMix || isActive), !proposed, let px = model.scanPixel, model.gridWidth > 0,
                   let plan = MapScaleBar.plan(pixelSize: px.size, unit: px.unit, pointsPerPixel: size.width / CGFloat(model.gridWidth),
                                               targetPoints: min(64, size.width * 0.3)) {
                    MapScaleBarView(plan: plan)
                }
                header
                if proposed {
                    RoundedRectangle(cornerRadius: TileMetrics.corner).strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
                if isActive {
                    RoundedRectangle(cornerRadius: TileMetrics.corner).strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                } else if !proposed {
                    RoundedRectangle(cornerRadius: TileMetrics.corner).strokeBorder(Color.primary.opacity(0.15))
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TileMetrics.corner))
            .onChange(of: model.active) { if !isActive { draft = [] } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(title + (isActive ? ", active map" : ""))
        .accessibilityIdentifier("spectroscopy.tile.\(Self.key(map))")
    }

    static func key(_ m: ActiveMap) -> String {
        switch m { case .haadf: "haadf"; case .colorMix: "colormix"; case .element(let z): PeriodicLayout.symbol(z) }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 4) {
            if let t = tile, !t.proposed {
                Toggle("In the ColorMix: \(title)", isOn: Binding(get: { model.mixed.contains(t.z) }, set: { _ in model.toggleMix(t.z) }))
                    .labelsHidden().toggleStyle(.checkbox).controlSize(.mini)
                    .environment(\.colorScheme, .dark)   // the tile is dark whatever the appearance: an unticked box stays visible on it
                    .help(t.notMeasuredWhy.map { "Not in the ColorMix by default (tick it to add): \($0)" } ?? "Include \(title) in the ColorMix")
            }
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white).shadow(radius: 1)
            if map == .colorMix {
                Spacer(minLength: 4)
                let own = model.tiles.filter { !$0.proposed }
                Text(ColorMixCaption.text(mixed: own.filter { model.mixed.contains($0.z) }.map { PeriodicLayout.symbol($0.z) },
                                          notMixed: own.filter { !model.mixed.contains($0.z) }.map { PeriodicLayout.symbol($0.z) }))
                    .font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1).truncationMode(.head)
            } else if proposed, let t = tile {
                Spacer(minLength: 4)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { Text("proposed").foregroundStyle(.white.opacity(0.85)).fixedSize(); accept(t) }
                    accept(t)
                }.font(.caption).lineLimit(1)   // R4c: no .fixedSize() here, it made the fit test unconstrained and the words wrapped
            } else {
                Spacer(minLength: 4)
                chip
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { model.active = map }   // the header sits above the bitmap's gesture: a press on it still picks the map
        .background(alignment: .top) { LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false) }
    }

    private func accept(_ t: MapTile) -> some View {
        Button("Accept") { model.elements.click(t.z) }
            .buttonStyle(.link).fixedSize()
            .help(model.elements.suggestions.first { $0.z == t.z }?.reason ?? "Accept \(title)")
    }

    /// The colour chip is a button on every non-proposed map but the ColorMix: it makes the tile active and opens its popover.
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
        guard isActive, g.w > 0, g.h > 0 else { return }
        let cw = size.width / CGFloat(g.w), ch = size.height / CGFloat(g.h)
        func pt(_ p: PixelPoint) -> CGPoint { CGPoint(x: CGFloat(p.x) * cw, y: CGFloat(p.y) * ch) }
        func rect(_ r: PixelRect) -> CGRect { CGRect(x: CGFloat(r.x0) * cw, y: CGFloat(r.y0) * ch, width: CGFloat(r.width) * cw, height: CGFloat(r.height) * ch) }
        let dash = StrokeStyle(lineWidth: 1.2, dash: [4, 3])
        func handleDot(_ p: CGPoint) {
            let r = CGRect(x: p.x - TileMetrics.handle / 2, y: p.y - TileMetrics.handle / 2, width: TileMetrics.handle, height: TileMetrics.handle)
            ctx.fill(Path(r), with: .color(.white)); ctx.stroke(Path(r), with: .color(.black.opacity(0.6)), lineWidth: 0.5)
        }
        var labelAt = CGPoint(x: 4, y: 4)
        if let shape = model.regionOutline {
            switch shape {
            case .rectangle(let r), .ellipse(let r):
                let rr = rect(r)
                ctx.stroke(shape.isEllipse ? Path(ellipseIn: rr) : Path(rr), with: .color(.white), style: dash)
                for p in [CGPoint(x: rr.minX, y: rr.minY), CGPoint(x: rr.midX, y: rr.minY), CGPoint(x: rr.maxX, y: rr.minY),
                          CGPoint(x: rr.minX, y: rr.midY), CGPoint(x: rr.maxX, y: rr.midY),
                          CGPoint(x: rr.minX, y: rr.maxY), CGPoint(x: rr.midX, y: rr.maxY), CGPoint(x: rr.maxX, y: rr.maxY)] { handleDot(p) }
                labelAt = CGPoint(x: rr.minX, y: max(rr.minY - 8, 18))
            case .polygon(let v):
                var p = Path()
                for (i, q) in v.enumerated() { i == 0 ? p.move(to: pt(q)) : p.addLine(to: pt(q)) }
                p.closeSubpath()
                ctx.stroke(p, with: .color(.white), style: dash)
                for q in v { handleDot(pt(q)) }
                if let top = v.min(by: { $0.y < $1.y }) { labelAt = CGPoint(x: pt(top).x, y: max(pt(top).y - 8, 18)) }
            }
            let live = model.regions.first { $0.id == model.selectedRegion }
            let text = Text("Region · \(live?.pixels ?? 0) px · live").font(.caption).foregroundStyle(.white)
            let r = CGRect(x: labelAt.x, y: labelAt.y - 8, width: 118, height: 16)
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(.black.opacity(0.55)))
            ctx.draw(text, at: CGPoint(x: r.minX + 5, y: r.midY), anchor: .leading)
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
                    model.active = map
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
                    model.active = map
                    if case .draw = edit, model.drawTool == .polygon { addVertex(point(v.startLocation), tol: tol, grid: g) }
                    return
                }
                if let shape = shape(for: edit, at: point(v.location), grid: g) { model.onRegionEdit?(shape, true) }
            }
    }

    private func shape(for edit: Edit?, at p: PixelPoint, grid g: (w: Int, h: Int)) -> SpectrumRegionShape? {
        switch edit {
        case .draw(let from)?:
            guard model.drawTool == .rectangle else { return nil }
            return RegionEditing.drawnRect(from: from, to: p, grid: g).map { .rectangle($0) }
        case .move(let start, let from)?:
            return RegionEditing.moved(start, dx: Int((p.x - from.x).rounded()), dy: Int((p.y - from.y).rounded()), grid: g)
        case .handle(let h, let start)?:
            return RegionEditing.edited(start, handle: h, to: p, grid: g)
        case nil: return nil
        }
    }

    /// Polygon tool: a click adds a corner; a click on the first corner (three or more set) closes it into the live region.
    private func addVertex(_ p: PixelPoint, tol: Double, grid g: (w: Int, h: Int)) {
        if draft.count >= 3, let first = draft.first, max(abs(p.x - first.x), abs(p.y - first.y)) <= tol {
            let shape = SpectrumRegionShape.polygon(draft)
            draft = []
            model.onRegionEdit?(shape, true)
        } else {
            draft.append(PixelPoint(x: min(max(p.x, 0), Double(g.w)), y: min(max(p.y, 0), Double(g.h))))
        }
    }
}

extension SpectrumRegionShape {
    var isEllipse: Bool { if case .ellipse = self { true } else { false } }
}

// MARK: - Colour, contrast and gamma of the active map

/// The chip on the active map's header: a swatch of its colour; its popover is the app's per-pane display popover
/// (`ColormapChip`: a grouped Form with the histogram's contrast handles and gamma), here for one map. Elements get a
/// `ColorPicker` (the tile and the ColorMix follow); HAADF gets its colormap.
struct MapDisplayChip: View {
    @Bindable var model: SpectroscopyRoomModel
    let map: ActiveMap
    let title: String
    @State private var isPresented = false

    var body: some View {
        Button { model.active = map; isPresented.toggle() } label: { swatch.frame(minWidth: 20, minHeight: 20).contentShape(Rectangle()) }
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
                    HistogramView(pixels: pixels, version: model.tileRevision, rangeLo: display.lo, rangeHi: display.hi)
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
