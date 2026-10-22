import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
#endif

/// The Spectroscopy room's Maps export: every element map, the ColorMix and the HAADF as PNG files exactly as shown (colour,
/// contrast window, gamma, no chrome) at the scan's own pixel grid, and the raw net-count maps as one CSV, all into one folder.
/// Pure: the files are built from the model's state (`files`) and written by `write`; the view only picks the folder.
@MainActor
enum MapsExport {
    struct File: Equatable { var name: String; var data: Data }
    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// The files' stem: the image's name without its extension, letters, digits, `-` and `_` only.
    nonisolated static func stem(imageName: String) -> String {
        let base = (imageName as NSString).deletingPathExtension
        let clean = String(base.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
        return clean.isEmpty ? "spectroscopy" : clean
    }

    /// "<stem>-<label>.png", or "<stem>-<label>-net-3x3.png" when the picture went through a display kernel: the file says what it
    /// shows; "-scalebar" when the scale bar is drawn into it, "-region" when the regions are, "-2x" or "-3x" when it is enlarged
    /// (in that order, last before the extension). The CSV never carries a tag (it is raw).
    nonisolated static func pngName(stem: String, label: String, mode: MapMode = .netCounts, smoothing: MapSmoothing = .none,
                                    scaleBar: Bool = false, region: Bool = false, pixelScale: Int = 1) -> String {
        var name = "\(stem)-\(label)"
        if smoothing != .none { name += "-" + String(mode.rawValue.filter { $0.isLetter || $0.isNumber }) + "-" + smoothing.fileTag }
        if scaleBar { name += "-scalebar" }
        if region { name += "-region" }
        if pixelScale > 1 { name += "-\(pixelScale)x" }
        return name + ".png"
    }
    nonisolated static func csvName(stem: String) -> String { "\(stem)-maps.csv" }
    /// The folder the files go into: "<stem>-maps".
    nonisolated static func folderName(stem: String) -> String { "\(stem)-maps" }

    /// One row per pixel (x, y, then one column per tile in tile order), written with a period and six significant digits
    /// whatever the locale. The numbers are the RAW signed counts the file gave (`MapTile.counts`, negative where the background
    /// exceeded the window, never smoothed); a tile without them (the fixture) falls back to value x `MapTile.scale`, and the
    /// header says so. The `#` header names the file, the map mode, the units and what the numbers are, and carries a tile's
    /// "not a measurement" note with it.
    nonisolated static func csv(stem: String, mode: MapMode, tiles: [MapTile], provenance: [String] = [], symbol: (Int) -> String) throws -> String {
        guard let first = tiles.first else { throw Failure("No element maps to write.") }
        for t in tiles where t.width != first.width || t.height != first.height || t.values.count != t.width * t.height {
            throw Failure("The element maps are not on one grid.")
        }
        let raw = tiles.allSatisfy { $0.counts.count == $0.width * $0.height }
        var out = ["# mac4DSTEM Spectroscopy element maps, file: \(stem)",
                   "# map mode: \(mode.rawValue), units: \(mode.units) (one row per scan pixel, row-major)",
                   rawLine(mode: mode, raw: raw)]
        if mode.isComposition { out += provenance }
        for t in tiles { if let why = t.notMeasuredWhy { out.append("# \(symbol(t.z)): not a measurement: \(why.replacingOccurrences(of: "\n", with: " "))") } }
        out.append((["x", "y"] + tiles.map { symbol($0.z) }).joined(separator: ","))
        for y in 0..<first.height {
            for x in 0..<first.width {
                let i = y * first.width + x
                out.append(([String(x), String(y)] + tiles.map { t in
                    let v = raw ? t.counts[i] : Double(t.values[i]) * Double(t.scale)
                    return v.isFinite ? String(format: "%.6g", v) : ""
                }).joined(separator: ","))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// The header line that says what the numbers are: raw counts as the file gave them, or (no counts held) the display values.
    nonisolated static func rawLine(mode: MapMode, raw: Bool) -> String {
        guard raw else { return "# \(mode.units) per pixel (display values: value x scale)" }
        if mode.isComposition { return "# \(mode.units) per pixel from EDXQuantification.quantifyMaps, unsmoothed" }
        return "# raw \(mode.units) per pixel as the file gives them"
            + (mode == .netCounts ? " (negative = background exceeded the window)" : "") + ", unsmoothed"
    }

    /// One map as the screen draws it: the HAADF, an element, or the ColorMix. `tagged` is false for a map the display kernel and
    /// the map mode do not touch (the HAADF; the ColorMix is made of elements, so it carries the tag); `label` is the on-screen title, `fileLabel` the word its file is named by.
    struct Map {
        var map: ActiveMap
        var label: String
        var fileLabel: String
        var image: CGImage
        var tagged: Bool
    }

    /// The maps the room shows, as images at the scan's own grid, in the order the files and the figures list them: the HAADF
    /// (when the file has one), each element, the ColorMix (when something is ticked or a HAADF stands behind it).
    static func maps(_ model: SpectroscopyRoomModel) -> [Map] {
        var out: [Map] = []
        if model.hasHAADF, let image = ElementTileRaster.haadf(values: model.backdrop, width: model.gridWidth, height: model.gridHeight,
                                                              colormap: model.haadfColormap, display: model.display(.haadf)) {
            out.append(Map(map: .haadf, label: "HAADF", fileLabel: "HAADF", image: image, tagged: false))
        }
        var colors: [Int: ColorMixComposite.RGB] = [:], displays: [Int: MapDisplay] = [:]
        for t in model.tiles {
            let c = ColorMixComposite.rgb(model.color(t.z)), d = model.display(.element(t.z))
            colors[t.z] = c; displays[t.z] = d
            if let image = ElementTileRaster.image(tile: t, color: c, display: d) {
                out.append(Map(map: .element(t.z), label: t.lineLabel ?? PeriodicLayout.symbol(t.z), fileLabel: PeriodicLayout.symbol(t.z),
                               image: image, tagged: true))
            }
        }
        let g = model.gridSize
        if let image = ColorMixRaster.image(tiles: model.tiles, mixed: model.mixed, colors: colors,
                                            backdrop: model.mixHAADF ? model.backdrop : [], width: g.w, height: g.h, displays: displays) {
            out.append(Map(map: .colorMix, label: colorMixLabel(model), fileLabel: "ColorMix", image: image, tagged: true))
        }
        return out
    }

    /// "ColorMix · Al · Mg · Si": the title with the elements mixed in.
    static func colorMixLabel(_ model: SpectroscopyRoomModel) -> String {
        let mixed = model.tiles.filter { model.mixed.contains($0.z) }.map { PeriodicLayout.symbol($0.z) }
        return mixed.isEmpty ? "ColorMix" : "ColorMix \u{00B7} " + mixed.joined(separator: " \u{00B7} ")
    }

    /// The order a figure lays the maps out in: the HAADF, the ColorMix, then each element (the files list the ColorMix last).
    static func figureOrder(_ maps: [Map]) -> [Map] {
        func rank(_ m: Map) -> Int { switch m.map { case .haadf: 0; case .colorMix: 1; case .element: 2 } }
        return maps.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// What the room can put in a figure, listed without drawing a map, in `figureOrder`: the HAADF and the ColorMix are ticked
    /// to begin with, an element is the person's to ask for. The ColorMix exists by `ColorMixRaster`'s rule: something ticked, or a
    /// HAADF under it.
    static func choices(_ model: SpectroscopyRoomModel) -> [FigureChoice] {
        var out: [FigureChoice] = []
        if model.hasHAADF { out.append(FigureChoice(id: FigureChoice.mapID(.haadf), label: "HAADF", isDefault: true)) }
        let g = model.gridSize
        let ticked = model.tiles.contains { model.mixed.contains($0.z) }
        if g.w > 0, g.h > 0, ticked || (model.mixHAADF && model.backdrop.count == g.w * g.h) {
            out.append(FigureChoice(id: FigureChoice.mapID(.colorMix), label: colorMixLabel(model), isDefault: true))
        }
        for t in model.tiles {
            out.append(FigureChoice(id: FigureChoice.mapID(.element(t.z)), label: t.lineLabel ?? PeriodicLayout.symbol(t.z), isDefault: false))
        }
        return out
    }

    /// The regions as the screen draws them on the ColorMix (`SpectroscopyRegionBridge` and MacEMUI's drawing layer): the live region dashed in the accent colour, each
    /// pin in its tint at the pin opacity, the same widths and dash; none when the room shows no region.
    static func regionOverlays(_ model: SpectroscopyRoomModel, scheme: ColorScheme = .dark) -> [FigureOverlay] {
        var out: [FigureOverlay] = []
        if let shape = model.regionOutline {
            out.append(.region(shape, RegionStroke(color: SpectroscopyRoomModel.liveRegionColor.cgColor(scheme: scheme),
                                                   width: RegionStrokeWidth.live, dash: [4, 3])))
        }
        if model.layers.pins {
            for pin in model.pins {
                guard let shape = pin.shape else { continue }
                out.append(.region(shape, RegionStroke(color: pin.tint.cgColor(opacity: SpectrumLayers.pinOpacity, scheme: scheme),
                                                       width: RegionStrokeWidth.pin)))
            }
        }
        return out
    }

    /// Every file the room's maps make: the HAADF (when the file has one), each element, the ColorMix (when something is
    /// ticked or a HAADF stands behind it), and the CSV; images are the same ones the screen draws. With `export.scaleBar` on and
    /// a pixel size from the file, each PNG carries the scale bar drawn into its bitmap (one pixel per scan pixel, so the bar's
    /// length in pixels is the round length over the pixel size) and its name says "-scalebar"; a map too narrow for a bar, or a
    /// file with no pixel size, is written as it is and named so. With `export.regions` on and a region drawn, each PNG carries
    /// the regions as the screen outlines them and its name says "-region" (the screen draws them on the ColorMix only; a
    /// file on its own cannot say which map "carries" them, so every map does). `pixelScale` 2 or 3 writes every PNG that many
    /// pixels per scan pixel (each scan pixel a block, the bar and the outlines drawn at the larger size) and the name says
    /// "-2x". The outlines are coloured in `scheme` (`FigureColors.scheme`). The CSV never changes.
    static func files(_ model: SpectroscopyRoomModel, pixelScale: Int = 1, scheme: ColorScheme = .dark) throws -> [File] {
        let stem = model.export.mapsStem
        let scale = max(pixelScale, 1)
        var out: [File] = []
        let pixel = model.export.scaleBar ? model.scanPixel : nil
        let outlines = model.export.regions ? regionOverlays(model, scheme: scheme) : []
        for entry in maps(model) {
            let image = entry.image
            // The bar the person asked for, if the map has room for it (`MapScaleBar.tilePlan`'s rule).
            let bar = pixel.flatMap { px in
                MapScaleBar.tilePlan(pixelSize: px.size, unit: px.unit, pointsPerPixel: 1, width: Double(image.width),
                                     locale: Locale(identifier: "en_US_POSIX")) == nil
                    ? nil : FigureScaleBar.map(pixelSize: px.size, unit: px.unit)
            }
            var final = image
            if bar != nil || !outlines.isEmpty || scale > 1 {
                guard let drawn = FigureRendering.rendered(FigurePanel(label: entry.label, image: image, overlays: outlines, bar: bar),
                                                           magnification: 1, deviceScale: scale) else { throw Failure("Could not draw \(entry.label).") }
                final = drawn
            }
            guard let data = MapBitmap.pngData(final, pixelScale: scale) else { throw Failure("Could not encode \(entry.label).") }
            out.append(File(name: pngName(stem: stem, label: entry.fileLabel,
                                          mode: entry.tagged ? model.mapMode : .netCounts,
                                          smoothing: entry.tagged ? model.smoothing : .none,
                                          scaleBar: bar != nil, region: !outlines.isEmpty, pixelScale: scale), data: data))
        }
        let text = try csv(stem: stem, mode: model.mapMode, tiles: model.tiles, provenance: model.quantMapsProvenance, symbol: PeriodicLayout.symbol)
        out.append(File(name: csvName(stem: stem), data: Data(text.utf8)))
        return out
    }

    /// Writes the files into `folder` (the person's pick, so its security scope is opened around the writes) and returns the
    /// names written; throws on the first failure. An existing file of the same name is replaced: the Export section never reaches
    /// this with a folder it did not just make (`writeInNewFolder`).
    nonisolated static func write(_ files: [File], to folder: URL) throws -> [String] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var names: [String] = []
        for f in files {
            try f.data.write(to: folder.appendingPathComponent(f.name), options: .atomic)
            names.append(f.name)
        }
        return names
    }

    /// A folder name inside `parent` that nothing uses yet: `name`, then "`name` 2", "`name` 3", ... as Finder numbers copies.
    nonisolated static func freeFolderName(_ name: String, in parent: URL,
                                           exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> String {
        var candidate = name, n = 2
        while exists(parent.appendingPathComponent(candidate)) { candidate = "\(name) \(n)"; n += 1 }
        return candidate
    }

    /// Writes the files into a NEW folder inside `parent` (the person's pick) and returns it with the names written. The folder is
    /// `name`, or the first free "`name` 2", ...: a second export of the same scan lands beside the first, never over it, so there is
    /// nothing to ask.
    nonisolated static func writeInNewFolder(_ files: [File], in parent: URL, named name: String) throws -> (folder: URL, names: [String]) {
        let scoped = parent.startAccessingSecurityScopedResource()
        defer { if scoped { parent.stopAccessingSecurityScopedResource() } }
        let folder = parent.appendingPathComponent(freeFolderName(name, in: parent), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return (folder, try write(files, to: folder))
    }

    /// The line the Export section shows afterwards.
    nonisolated static func note(written: [String], folder: URL) -> String {
        "Wrote \(written.count) file\(written.count == 1 ? "" : "s") to \(folder.lastPathComponent)"
    }
}
