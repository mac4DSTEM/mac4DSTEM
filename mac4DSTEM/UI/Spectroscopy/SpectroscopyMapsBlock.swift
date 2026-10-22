//
//  SpectroscopyMapsBlock.swift
//  Role: the Spectroscopy room's maps (the corrected design, 2026-10-22): the colour mix as the ANCHOR tile on the left, where regions are drawn and edited, the HAADF and one
//        map per element fitted into the rest, everything scaling with the panes. The frame of a tile (name, scale bar and its popover, colour scale, one cursor, zoom and pan) is
//        MacEMUI's `MapTileView`; here are the pictures (the app's rasters through their caches) and the wiring to the room's model. Pure rules (`MapTileCaption`, the readout) are tested.
//

import ShellInspector
import ShellLayout
import SwiftUI
import ShellMetal
import ShellSpectroscopy
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
#endif

/// One tile beside the colour mix: the HAADF or an element's map (the mix is the anchor and is not an item).
enum MapGridItem: Identifiable {
    case colorMix
    case haadf
    case element(MapTile)
    var id: ActiveMap {
        switch self { case .colorMix: .colorMix; case .haadf: .haadf; case .element(let t): .element(t.z) }
    }
}

extension SpectroscopyRoomModel {
    /// The scan's grid: the tiles', else the room's own (the HAADF backdrop's).
    var gridSize: (w: Int, h: Int) {
        if let t = tiles.first { return (t.width, t.height) }
        return (gridWidth, gridHeight)
    }
    var hasHAADF: Bool { gridWidth > 0 && backdrop.count == gridWidth * gridHeight }
    /// The tiles on the right: HAADF first, then the elements. The colour mix is the anchor and is not among them.
    var gridItems: [MapGridItem] { (hasHAADF ? [.haadf] : []) + tiles.map { .element($0) } }
    var gridAspect: CGFloat { let g = gridSize; return g.w > 0 && g.h > 0 ? CGFloat(g.w) / CGFloat(g.h) : 1 }

    /// What the colour mix tile says while it has no picture.
    static let mixPlaceholder = "Select maps on the right to build the colour mix"
    /// The colour mix has something to draw: an element is ticked, or the HAADF is in and there is one.
    var mixHasImage: Bool { tiles.contains { mixed.contains($0.z) } || (mixHAADF && hasHAADF) }
}

/// The maps: the colour mix large on the left, HAADF and one tile per element fitted beside it, each at the scan's aspect. The tiles are pickers
/// (spec 2 D-2: the accent ring means "in the colour mix"); the regions live on the colour mix only (D-1). A one-pixel image has no maps.
struct SpectroscopyMapsBlock: View {
    @Bindable var model: SpectroscopyRoomModel
    @Environment(AppState.self) private var appState: AppState?   // absent in a bare render (previews, tests)
    @Environment(PrecipitateTableSelection.self) private var tableSelection: PrecipitateTableSelection?

    var body: some View {
        let g = model.gridSize
        if g.w * g.h == 1 {
            EmptyView()
        } else {
            // The glyphs resolve once for the whole block; the tiles take the value, not the app state.
            let glyphs = PrecipitateGlyphTileInput.resolve(appState: appState, tableSelection: tableSelection, gridWidth: g.w, gridHeight: g.h)
            AnchoredMapsBlock(anchor: MapGridItem.colorMix, items: model.gridItems, aspect: model.gridAspect, storageKey: "spectroscopy.mapsSplit",
                              solo: .constant(nil), soloEnabled: false) { item, size, isAnchor in
                SpectroscopyMapTile(model: model, item: item, size: size, isAnchor: isAnchor, glyphs: glyphs)
            }
            .accessibilityIdentifier("spectroscopy.maps")
        }
    }
}

/// What a tile's name line says after the name ("Al · Kα+Kβ · net · filtered"): pure, so a test holds it.
nonisolated enum MapTileCaption {
    static let filtered = "filtered"

    /// An element: the chosen lines without the symbol ("Kα+Kβ" of "Al Kα+Kβ"), "at% · per-pixel" on a composition map, "filtered" under a display
    /// kernel. The colour mix: the mixed names joined by " + ", then "filtered". The HAADF: nothing. nil when there is nothing to say.
    static func detail(map: ActiveMap, mode: MapMode, smoothing: MapSmoothing, lineLabel: String?, mixed: [String]) -> String? {
        switch map {
        case .haadf: return nil
        case .colorMix:
            guard !mixed.isEmpty else { return nil }
            return (mixed.joined(separator: " + ") + (smoothing == .none ? "" : " \u{00B7} " + filtered))
        case .element:
            var parts: [String] = []
            if let label = lineLabel {
                let words = label.split(separator: " ", maxSplits: 1)
                parts.append(String(words.count == 2 ? words[1] : Substring(label)))
            }
            if mode.isComposition { parts.append("\(mode.rawValue) \u{00B7} per-pixel") }
            if smoothing != .none { parts.append(filtered) }
            return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
        }
    }
}

/// One tile with its picture from the app's rasters (through the two caches) and the wiring of its click, hover, regions and popover.
private struct SpectroscopyMapTile: View {
    @Bindable var model: SpectroscopyRoomModel
    let item: MapGridItem
    let size: CGSize
    let isAnchor: Bool
    /// The precipitate glyphs for the element and colour mix tiles, resolved once by the block; nil draws none.
    let glyphs: PrecipitateGlyphTileInput?
    @State private var mixCache = ColorMixRasterCache()
    @State private var tileCache = MapTileRasterCache()

    var body: some View {
        let map = item.id
        let g = model.gridSize
        let place = model.mapView.placement(in: size)
        MapTileView(title: title, detail: detail, image: image, size: size, scanWidth: g.w, scanHeight: g.h,
                    pixelSize: model.scanPixel?.size, pixelUnit: model.scanPixel?.unit, colorbar: colorbar,
                    regions: isAnchor ? SpectroscopyRegionBridge.regions(model) : nil,
                    inMix: isAnchor ? nil : model.isInMix(map), onToggleMix: isAnchor ? nil : { model.pick(map) },
                    placeholder: isAnchor ? SpectroscopyRoomModel.mixPlaceholder : nil, transform: $model.mapView,
                    valueText: valueText, onHover: onHover,
                    controls: { MapDisplayPopover(model: model, map: map).formStyle(.grouped).scrollContentBackground(.hidden).fixedSize(horizontal: false, vertical: true) })
            .overlay {
                // MapTileView has no slot for an overlay: the glyphs sit over the tile and follow its zoom and pan.
                if map.carriesGlyphs, let glyphs {
                    PrecipitateGlyphTileLayer(input: glyphs)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(place.scale)
                        .offset(place.offset)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .accessibilityIdentifier("spectroscopy.tile.\(Self.key(map))")
    }

    static func key(_ m: ActiveMap) -> String {
        switch m { case .haadf: "haadf"; case .colorMix: "colormix"; case .element(let z): PeriodicLayout.symbol(z) }
    }

    private var tile: MapTile? { if case .element(let t) = item { t } else { nil } }

    private var title: String {
        switch item { case .colorMix: "Colour mix"; case .haadf: "HAADF"; case .element(let t): PeriodicLayout.symbol(t.z) }
    }

    private var detail: String? {
        let mixed = model.tiles.filter { model.mixed.contains($0.z) }.map { PeriodicLayout.symbol($0.z) }
        return MapTileCaption.detail(map: item.id, mode: model.mapMode, smoothing: model.smoothing, lineLabel: tile?.lineLabel,
                                     mixed: (model.mixHAADF && model.hasHAADF ? ["HAADF"] : []) + mixed)
    }

    private var colorbar: MapColorbarSpec? {
        switch item {
        case .colorMix: return nil
        case .haadf: return MapColorbarSpec(low: 0, high: 1, unit: "", coloring: .colormap(model.haadfColormap))
        case .element(let t):
            let display = model.display(.element(t.z))
            return MapColorbarSpec(low: Double(display.lo * t.scale), high: Double(display.hi * t.scale), unit: model.mapMode.units,
                                   coloring: .color(RegionColor(model.color(t.z), resolvedIn: EnvironmentValues())))
        }
    }

    private var valueText: (Int, Int) -> String? {
        guard let t = tile else { return { _, _ in nil } }
        let symbol = PeriodicLayout.symbol(t.z), mode = model.mapMode
        return { column, row in MapHoverReadout.text(symbol: symbol, tile: t, mode: mode, column: column, row: row) }
    }

    /// The pointer over an element tile highlights its lines in the spectrum; nothing else (no status-line writes).
    private var onHover: ((x: Int, y: Int)?) -> Void {
        guard let t = tile else { return { _ in } }
        let z = t.z
        return { pixel in
            if pixel != nil { if model.highlightedZ != z { model.highlightedZ = z } }
            else if model.highlightedZ == z { model.highlightedZ = nil }
        }
    }

    private var image: CGImage? {
        switch item {
        case .colorMix: model.mixHasImage ? colorMixImage() : nil
        case .haadf: haadfImage()
        case .element(let t): elementImage(t)
        }
    }

    private func colorMixImage() -> CGImage? {
        let g = model.gridSize
        var colors: [Int: ColorMixComposite.RGB] = [:]
        var displays: [Int: MapDisplay] = [:]
        var style = Hasher()
        for t in model.tiles where model.mixed.contains(t.z) {
            let c = ColorMixComposite.rgb(model.color(t.z))
            colors[t.z] = c
            let d = model.display(.element(t.z))
            displays[t.z] = d
            style.combine(MapStyle.stamp(color: c, display: d))
        }
        // The HAADF tile's ring: out, the mix sits on black (an empty backdrop is "none").
        let backdrop = model.mixHAADF ? model.backdrop : []
        let key = ColorMixRasterCache.Key(revision: model.tileRevision, mixed: model.mixed, width: g.w, height: g.h,
                                          backdropCount: backdrop.count, style: style.finalize(), mixHAADF: model.mixHAADF)
        return mixCache.image(for: key) {
            ColorMixRaster.image(tiles: model.tiles, mixed: model.mixed, colors: colors, backdrop: backdrop,
                                 width: g.w, height: g.h, displays: displays)
        }
    }

    private func elementImage(_ t: MapTile) -> CGImage? {
        let c = ColorMixComposite.rgb(model.color(t.z)), d = model.display(.element(t.z))
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
}

extension ColorMixComposite {
    /// A colour as the rasters take it, resolved in the default environment.
    static func rgb(_ c: Color) -> RGB {
        let r = c.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue))
    }
}

/// The pointer's value on an element tile (the shared hover chip): the symbol and the number in the map's own unit, "Mg 36.2 wt%"
/// or "Si 412 380 net counts"; the pixel is clamped to the grid, nil for a tile with no pixels.
enum MapHoverReadout {
    static func text(symbol: String, tile: MapTile, mode: MapMode, column: Int, row: Int) -> String? {
        guard tile.width > 0, tile.height > 0 else { return nil }
        let i = min(max(row, 0), tile.height - 1) * tile.width + min(max(column, 0), tile.width - 1)
        let value: Double
        if i < tile.counts.count { value = tile.counts[i] }
        else if i < tile.values.count { value = Double(tile.values[i] * tile.scale) }
        else { return nil }
        guard value.isFinite else { return "\(symbol) \u{2013}" }
        if mode.isComposition { return "\(symbol) \(value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))) \(mode.rawValue)" }
        return "\(symbol) \(ResultFormat.counts(value)) \(mode.units)"
    }
}

nonisolated enum RegionKeys {
    /// The region ⌫ removes: the selected region when the person drew it (never the whole map, never a pool).
    static func removableID(_ regions: [RegionSummary], selected: Int?) -> Int? { regions.first { $0.isDrawn && $0.id == selected }?.id }
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
    /// The histogram section's title: an element map under a display kernel says its values are smoothed (the unit string is
    /// repeated on every readout, so the title carries it once).
    func histogramTitle(_ map: ActiveMap) -> String {
        if case .element = map, smoothing != .none { return "Histogram \u{00B7} smoothed, \(smoothing.label)" }
        return "Histogram"
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
    /// The maps a click can put in the colour mix: the HAADF (when there is one), then the elements.
    var mixCandidates: [ActiveMap] { (hasHAADF ? [.haadf] : []) + tiles.map { .element($0.z) } }
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
                case .colorMix:
                    // The mix's members, as the tiles' rings say: tick a map in or out here too.
                    ForEach(model.mixCandidates, id: \.self) { candidate in
                        Toggle(model.mapTitle(candidate), isOn: Binding(get: { model.isInMix(candidate) }, set: { _ in model.pick(candidate) }))
                            .toggleStyle(.checkbox)
                    }
                }
            } header: {
                if map == .colorMix { Text("Maps in the colour mix") }
            }
            if !pixels.isEmpty {
                Section(model.histogramTitle(map)) {
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
            Label { Text(kind.displayName) } icon: { Colormaps.swatch(kind).clipShape(RoundedRectangle(cornerRadius: 2)) }.tag(kind)
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
