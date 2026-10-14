//
//  FigureExport.swift
//  Role: What the window can put in an exported image, and the figure export itself (tier 2, 2026-10-14). The result
//        image, the diffraction pattern and the EDX maps, each as the pixels the screen shows, with the outlines and
//        scale bar the screen draws; the same rasters feed the single-image exports (`ResultExport.swift`), the
//        Maps export (`MapsExport.swift`) and the multi-panel figure here, so the pictures cannot disagree.
//        Drawing is `FigureRendering`; this file only chooses what to draw. The figure leaves the app through SwiftUI's own
//        export panel (`fileExporter` over a `WritableDocument`, with `fileDialogMessage`): no AppKit save panel.
//

import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
import SpectroCore
#endif

/// One image the figure can hold, listed before anything is drawn. `id` is stable for as long as the image exists.
struct FigureChoice: Identifiable, Equatable {
    var id: String
    var label: String
    /// Ticked when the person has not chosen: the result, the pattern, the HAADF and the ColorMix (a figure of every element is
    /// the person's to ask for).
    var isDefault: Bool

    static let resultID = "result"
    static let patternID = "pattern"
    static func mapID(_ map: ActiveMap) -> String {
        switch map {
        case .haadf: "map.haadf"
        case .colorMix: "map.colormix"
        case .element(let z): "map.el.\(z)"
        }
    }
}

/// The result image as the screen shows it, before the scale bar and the caption: oriented as displayed, with the sampling along
/// the screen horizontal. The single export and the figure draw from this one value.
struct ResultExportRaster {
    var image: CGImage
    var product: DisplayedProduct
    /// Units per data pixel along the burnt-in bar; nil when the product states no sampling (the bar is then in pixels).
    var sampling: Double?
    var unit: String
    var masksNoData: Bool
}

/// The diffraction pattern as the pane shows it (colormap, window, gamma, log), with the q sampling.
struct PatternExportRaster {
    var image: CGImage
    var sampling: Double?
    var unit: String
}

/// A figure's bytes for SwiftUI's export panel: the file as its format made it, the type it is, the name it suggests and the sentence
/// the panel shows (what is being saved, at what size). A `WritableDocument` (SDK 27), so `fileExporter` takes it directly.
final class FigureFile: WritableDocument {
    let data: Data
    let format: ExportFigureFormat
    let suggestedName: String
    let message: String

    nonisolated static let writableContentTypes: [UTType] = [.png, .pdf, .tiff]

    init(data: Data, format: ExportFigureFormat, suggestedName: String, message: String) {
        self.data = data; self.format = format; self.suggestedName = suggestedName; self.message = message
    }

    var contentType: UTType { format.utType }

    nonisolated func writer(configuration: sending DocumentWriteConfiguration) -> sending FileWrapperDocumentWriter<Data> {
        FileWrapperDocumentWriter(configuration) { data, _ in FileWrapper(regularFileWithContents: data) }
    }

    @MainActor func snapshot(contentType: UTType) async throws -> Data { data }
}

extension ExportFigureFormat {
    var utType: UTType {
        switch self {
        case .png: .png
        case .pdf: .pdf
        case .tiff: .tiff
        }
    }
}

/// The appearance an export resolves SwiftUI's colours in.
enum FigureColors {
    /// The app's own: the Settings preference when it names one, else the system's (`AppleInterfaceStyle` is "Dark" in dark mode and
    /// absent in light). The pane draws the variant of that appearance, so a file carries the colour the pane showed when it was made.
    static func scheme(appearance: AppAppearance,
                       systemIsDark: Bool = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark") -> ColorScheme {
        appearance.colorScheme ?? (systemIsDark ? .dark : .light)
    }
}

extension AppState {

    // MARK: The rasters

    /// The displayed product as an image, "as displayed" (#17b): the display orientation is applied and recorded in the caption,
    /// because an applied-but-unrecorded rotation is the one outcome that is not acceptable. The scientific bundle takes the
    /// opposite choice and stays in scan-index order; see `scientificBundleMaps()`.
    func resultExportRaster() throws -> ResultExportRaster {
        let source: (bytes: [UInt8], width: Int, height: Int)
        // support-export-07 (S22e): masked pixels normalize to the negative
        // invalid-display sentinel; when any exist the burned figure carries
        // a "no data" legend beside its colorbar.
        var masksNoData = false
        // v2.5 step 3 (adapter step 3, plan §9d): the pixels come from the same
        // product the caption below describes — `displayedProduct` — never from
        // the raw fields, so the two halves of one export cannot disagree
        // (they could under the ACOM region reference before this).
        guard let product = displayedProduct else { throw SimpleError("No result image to export yet.") }
        switch product.payload {
        case .rgba(let rgba):
            source = (rgba.rgba, rgba.width, rgba.height)
        case .scalar(let image):
            let norm = image.normalized(symmetric: resultPresentation.resultColormap.isDiverging)
            masksNoData = norm.contains { $0 < 0 }
            let bytes = Self.applyColormap(norm, colormap: resultPresentation.resultColormap,
                                           lo: resultPresentation.displayRangeLo, hi: resultPresentation.displayRangeHi,
                                           gamma: resultPresentation.resultGamma)
            source = (bytes, image.width, image.height)
        }
        let orientation = effectiveRealSpaceDisplayOrientation
        let oriented = Self.orientedRGBA(
            source.bytes, width: source.width, height: source.height,
            orientation: orientation, mirrored: effectiveRealSpaceDisplayMirrored
        )
        guard let cg = Self.cgImage(rgba: oriented.bytes, width: oriented.width, height: oriented.height) else {
            throw SimpleError("Could not render the result image for export.")
        }
        let pixel = currentResultPersistenceMetadata
        // A quarter turn puts the other axis along the burnt-in bar, and for a
        // non-square scan that is a different pixel size.
        let sampling = orientation.swapsAxes
            ? (pixel.row ?? pixel.column) : (pixel.column ?? pixel.row)
        return ResultExportRaster(
            image: cg, product: product, sampling: sampling,
            unit: sampling != nil ? CalibrationUnitConversion.displayLabel(pixel.units ?? "px") : "px",
            masksNoData: masksNoData)
    }

    /// The displayed diffraction pattern as an image.
    func patternExportRaster() throws -> PatternExportRaster {
        guard let pattern = displayedPattern else { throw SimpleError("No diffraction pattern to export yet.") }
        let norm = pattern.normalized(useLog: logScale)
        let bytes = Self.applyColormap(norm, colormap: patternColormap,
                                       lo: patternDisplayRangeLo,
                                       hi: patternDisplayRangeHi,
                                       gamma: patternGamma)
        guard let cg = Self.cgImage(rgba: bytes, width: pattern.qx, height: pattern.qy) else {
            throw SimpleError("Could not render the diffraction pattern for export.")
        }
        let qSize = calibrationSession.calibration.qPixelSize
        return PatternExportRaster(
            image: cg, sampling: qSize,
            unit: qSize != nil ? CalibrationUnitConversion.displayLabel(calibrationSession.calibration.qPixelUnits ?? "1/nm") : "px")
    }

    /// The virtual detector the diffraction pane draws, as the export draws it: only in the Virtual Detector task, where the
    /// pane shows the overlay (the aperture exists in every task but means something in this one).
    var patternExportOverlays: [FigureOverlay] {
        navigation.analysisMode == .virtualDetector ? detectorOverlay : []
    }

    /// The live virtual detector as an overlay for the displayed pattern, whatever the task (empty without a pattern), in the colours of
    /// the app's appearance. The figure's "Detector outline" tick takes this directly.
    var detectorOverlay: [FigureOverlay] {
        guard displayedPattern != nil else { return [] }
        return [.detector(aperture, resultPresentation.virtualShape, exportColorScheme)]
    }

    /// The appearance the exports resolve colours in (`FigureColors.scheme`).
    var exportColorScheme: ColorScheme { FigureColors.scheme(appearance: preferences.appearance) }

    // MARK: The figure

    /// What this window can put in a figure, in the order the panels are laid out: the result, the pattern, then the EDX maps
    /// (HAADF, ColorMix, each element). Nothing is drawn to list them.
    var figureChoices: [FigureChoice] {
        var out: [FigureChoice] = []
        if resultPresentation.resultImage != nil || resultPresentation.resultRGBA != nil {
            out.append(FigureChoice(id: FigureChoice.resultID, label: currentResultDisplayName, isDefault: true))
        }
        if displayedPattern != nil {
            out.append(FigureChoice(id: FigureChoice.patternID, label: patternFigureLabel, isDefault: true))
        }
        if hasSpectrumImage { out += MapsExport.choices(spectroscopyRoom.model) }
        return out
    }

    /// The pattern panel's label: which pattern the pane shows.
    var patternFigureLabel: String {
        switch patternDisplayMode {
        case .mean: "Mean diffraction pattern"
        case .max: "Max diffraction pattern"
        case .current:
            realSpaceShape != .point && resultPresentation.virtualDiffractionPattern != nil
                ? "Diffraction pattern (region sum)" : "Diffraction pattern"
        }
    }

    /// The panels for the chosen ids, in layout order, each at data resolution with its outlines and scale bar. An id the window no
    /// longer has is skipped. The detector outline follows the pane (`patternExportOverlays`); the regions follow the Spectroscopy
    /// room's Export setting; every bar is drawn where a sampling exists.
    /// `detector` ticks the detector outline on the pattern; nil follows the pane (drawn in the Virtual Detector task only).
    func figurePanels(chosen ids: Set<String>, detector: Bool? = nil) -> [FigurePanel] {
        var panels: [FigurePanel] = []
        if ids.contains(FigureChoice.resultID), let raster = try? resultExportRaster() {
            panels.append(FigurePanel(label: currentResultDisplayName, image: raster.image,
                                      bar: .ladder(unitsPerDataPixel: raster.sampling, unit: raster.unit)))
        }
        if ids.contains(FigureChoice.patternID), let raster = try? patternExportRaster() {
            panels.append(FigurePanel(label: patternFigureLabel, image: raster.image, overlays: detector.map { $0 ? detectorOverlay : [] } ?? patternExportOverlays,
                                      bar: .ladder(unitsPerDataPixel: raster.sampling, unit: raster.unit)))
        }
        if hasSpectrumImage {
            let model = spectroscopyRoom.model
            let outlines = model.export.regions ? MapsExport.regionOverlays(model, scheme: exportColorScheme) : []
            let bar = model.scanPixel.map { FigureScaleBar.map(pixelSize: $0.size, unit: $0.unit) }
            for entry in MapsExport.figureOrder(MapsExport.maps(model)) where ids.contains(FigureChoice.mapID(entry.map)) {
                panels.append(FigurePanel(label: entry.label, image: entry.image, overlays: outlines, bar: bar))
            }
        }
        return panels
    }

    /// The machine-readable half of a figure's provenance (the file's description): what it holds and how it was drawn.
    func figureProvenanceRecord(_ panels: [FigurePanel], scale: Int, format: ExportFigureFormat = .png) -> [String: Any] {
        var record: [String: Any] = [
            "title": "Figure",
            "panels": panels.map(\.label),
            "format": format.rawValue,
        ]
        if format != .pdf { record["export_scale"] = scale }   // a vector file has no pixels to scale
        if let file = descriptor?.fileName { record["source_file"] = file }
        return record
    }

    /// The figure of the chosen images at `scale` pixels per point, with the panels it holds. Throws the sentence the person is
    /// shown when nothing is chosen, when the figure would pass `FigureLayout.maximumPixels` on a side, or when it cannot be drawn.
    func figureImage(chosen ids: Set<String>, scale: Int, detector: Bool? = nil) throws -> (image: CGImage, panels: [FigurePanel]) {
        let panels = figurePanels(chosen: ids, detector: detector)
        guard !panels.isEmpty else { throw SimpleError("Pick at least one image for the figure.") }
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })
        let size = FigureLayout.pixelSize(plan, scale: scale)
        guard max(size.width, size.height) <= FigureLayout.maximumPixels else {
            throw SimpleError("This figure would be \(size.width) \u{00D7} \(size.height) pixels, over the \(FigureLayout.maximumPixels) the export draws. Pick fewer images or a smaller image size.")
        }
        guard let figure = FigureRendering.render(panels, scale: scale) else { throw SimpleError("Could not draw the figure.") }
        return (figure, panels)
    }

    /// The figure of the chosen images as a one-page vector PDF, with the panels it holds and its page size in points. The same
    /// refusals as `figureImage`.
    func figurePDF(chosen ids: Set<String>, detector: Bool? = nil) throws -> (data: Data, panels: [FigurePanel], width: Int, height: Int) {
        let panels = figurePanels(chosen: ids, detector: detector)
        guard !panels.isEmpty else { throw SimpleError("Pick at least one image for the figure.") }
        let plan = FigureLayout.plan(panels.map { ($0.label, $0.image.width, $0.image.height) })
        let size = FigureLayout.pixelSize(plan, scale: 1)
        guard max(size.width, size.height) <= FigureLayout.maximumPixels else {
            throw SimpleError("This figure would be \(size.width) \u{00D7} \(size.height) points, over the \(FigureLayout.maximumPixels) the export draws. Pick fewer images.")
        }
        guard let data = FigureRendering.renderPDF(panels) else { throw SimpleError("Could not draw the figure.") }
        return (data, panels, size.width, size.height)
    }

    /// The properties a figure's file carries: the record as its description (a PNG text chunk, a TIFF ImageDescription), and at 2x /
    /// 3x the density that places it at the 1x size. LZW for a TIFF, whose pixels would otherwise be stored raw.
    nonisolated static func figureProperties(format: ExportFigureFormat, title: String, record: [String: Any], pixelScale: Int) -> [CFString: Any]? {
        switch format {
        case .png:
            return pngProperties(title: title, record: record, pixelScale: pixelScale)
        case .tiff:
            var tiff: [CFString: Any] = [kCGImagePropertyTIFFCompression: 5, kCGImagePropertyTIFFSoftware: "mac4DSTEM"]   // 5 = LZW
            if JSONSerialization.isValidJSONObject(record),
               let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                tiff[kCGImagePropertyTIFFImageDescription] = json
            }
            var properties: [CFString: Any] = [kCGImagePropertyTIFFDictionary: tiff]
            if let density = pngDensity(pixelScale: pixelScale) { properties.merge(density) { $1 } }
            return properties
        case .pdf:
            return nil
        }
    }

    /// The figure of the chosen images as the file to write, in the preferences' format and image size (a PDF is vector and has
    /// neither pixels nor a scale). Throws the sentence the person is shown when it cannot be made. The panel-free half of the export.
    func figureFile(chosen ids: Set<String>, detector: Bool? = nil) throws -> FigureFile {
        let scale = preferences.exportScale.pixelScale
        let format = preferences.figureFormat
        let name = exportBaseName + "_figure"
        switch format {
        case .pdf:
            let made = try figurePDF(chosen: ids, detector: detector)
            return FigureFile(data: made.data, format: .pdf, suggestedName: name,
                              message: Self.exportPanelMessage(subject: Self.figureSubject(made.panels), width: made.width, height: made.height, scale: nil))
        case .png, .tiff:
            let made = try figureImage(chosen: ids, scale: scale, detector: detector)
            let properties = Self.figureProperties(format: format, title: "Figure",
                                                   record: figureProvenanceRecord(made.panels, scale: scale, format: format), pixelScale: scale)
            guard let data = Self.encodeImage(made.image, type: format.utType, properties: properties) else {
                throw SimpleError("Could not encode the figure as \(format.displayName).")
            }
            return FigureFile(data: data, format: format, suggestedName: name,
                              message: Self.exportPanelMessage(subject: Self.figureSubject(made.panels), width: made.image.width, height: made.image.height, scale: scale))
        }
    }

    /// What follows the export panel: the status line and the export record on success, the error on failure (a cancelled panel is
    /// neither).
    func figureExported(_ result: Result<URL, Error>, file: FigureFile) {
        switch result {
        case .success(let url):
            statusText = "Exported \(url.lastPathComponent)"
            recordExportRun(format: file.format.rawValue, fileName: url.lastPathComponent, productKind: nil, productStep: nil)
        case .failure(let error):
            present(error)
        }
    }

    /// The encoded bytes of an image in any type ImageIO writes.
    /// A TIFF is tagged sRGB (the figure is drawn in device RGB, which ImageIO's PNG writer already records as sRGB; its TIFF writer
    /// would leave the file untagged and a viewer would guess).
    nonisolated static func encodeImage(_ image: CGImage, type: UTType, properties: [CFString: Any]?) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let tagged = type == .tiff ? (CGColorSpace(name: CGColorSpace.sRGB).flatMap { image.copy(colorSpace: $0) } ?? image) : image
        CGImageDestinationAddImage(dest, tagged, properties as CFDictionary?)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// What the save panel calls the figure: its images by name when they fit one line, else how many.
    nonisolated static func figureSubject(_ panels: [FigurePanel]) -> String {
        let names = panels.map(\.label).joined(separator: ", ")
        if names.count <= 80 { return "Figure: " + names }
        return "Figure of \(panels.count) images"
    }
}
