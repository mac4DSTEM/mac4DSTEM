import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
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

    nonisolated static func pngName(stem: String, label: String) -> String { "\(stem)-\(label).png" }
    nonisolated static func csvName(stem: String) -> String { "\(stem)-maps.csv" }

    /// One row per pixel (x, y, then one column per tile in tile order), net counts = value x `MapTile.scale`, written with a
    /// period and six significant digits whatever the locale. The `#` header names the file, the map mode and the units, and
    /// carries a tile's "not a measurement" note with it.
    nonisolated static func csv(stem: String, mode: MapMode, tiles: [MapTile], symbol: (Int) -> String) throws -> String {
        guard let first = tiles.first else { throw Failure("No element maps to write.") }
        for t in tiles where t.width != first.width || t.height != first.height || t.values.count != t.width * t.height {
            throw Failure("The element maps are not on one grid.")
        }
        var out = ["# mac4DSTEM Spectroscopy element maps, file: \(stem)",
                   "# map mode: \(mode.rawValue), units: \(mode.units) (value x scale; one row per scan pixel, row-major)"]
        for t in tiles { if let why = t.notMeasuredWhy { out.append("# \(symbol(t.z)): not a measurement: \(why.replacingOccurrences(of: "\n", with: " "))") } }
        out.append((["x", "y"] + tiles.map { symbol($0.z) }).joined(separator: ","))
        for y in 0..<first.height {
            for x in 0..<first.width {
                let i = y * first.width + x
                out.append(([String(x), String(y)] + tiles.map { t in
                    let v = Double(t.values[i]) * Double(t.scale)
                    return v.isFinite ? String(format: "%.6g", v) : ""
                }).joined(separator: ","))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Every file the room's maps make: the HAADF (when the file has one), each element, the ColorMix (when something is
    /// ticked or a HAADF stands behind it), and the CSV; images are the same ones the screen draws.
    static func files(_ model: SpectroscopyRoomModel) throws -> [File] {
        let stem = model.export.mapsStem
        var out: [File] = []
        func add(_ label: String, _ image: CGImage?) throws {
            guard let image else { return }
            guard let data = MapBitmap.pngData(image) else { throw Failure("Could not encode \(label).") }
            out.append(File(name: pngName(stem: stem, label: label), data: data))
        }
        if model.hasHAADF {
            try add("HAADF", ElementTileRaster.haadf(values: model.backdrop, width: model.gridWidth, height: model.gridHeight,
                                                     colormap: model.haadfColormap, display: model.display(.haadf)))
        }
        var colors: [Int: ColorMixComposite.RGB] = [:], displays: [Int: MapDisplay] = [:]
        for t in model.tiles {
            let c = MapsGridView.rgb(model.color(t.z)), d = model.display(.element(t.z))
            colors[t.z] = c; displays[t.z] = d
            try add(PeriodicLayout.symbol(t.z), ElementTileRaster.image(tile: t, color: c, display: d))
        }
        let g = model.gridSize
        try add("ColorMix", ColorMixRaster.image(tiles: model.tiles, mixed: model.mixed, colors: colors,
                                                 backdrop: model.mixHAADF ? model.backdrop : [], width: g.w, height: g.h, displays: displays))
        let text = try csv(stem: stem, mode: model.mapMode, tiles: model.tiles, symbol: PeriodicLayout.symbol)
        out.append(File(name: csvName(stem: stem), data: Data(text.utf8)))
        return out
    }

    /// Writes the files into `folder` (the person's pick, so its security scope is opened around the writes) and returns the
    /// names written; throws on the first failure. An existing file of the same name is replaced.
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

    /// The line the Export section shows afterwards.
    nonisolated static func note(written: [String], folder: URL) -> String {
        "Wrote \(written.count) file\(written.count == 1 ? "" : "s") to \(folder.lastPathComponent)"
    }
}
