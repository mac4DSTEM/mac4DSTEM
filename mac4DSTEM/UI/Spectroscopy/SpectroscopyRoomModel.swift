import SwiftUI
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The room's view-model: what every Spectroscopy view reads and edits. It holds NO
/// loading or fitting — lane R's `SpectroscopySession` fills the series, regions and
/// results (and receives the edits through the same properties); `.fixture` fills them
/// with illustrative Al-Mg-Si numbers for previews and tests. Nothing here is a
/// measured result, and every default below is empty: a row with no value hides.
///
/// Map contract: `tiles` hold the maps of the CURRENT `mapMode` (net counts or at%). The
/// session swaps them when `mapMode` changes; the composite does not convert.
///
/// Seam for lane R: replace the `fixture` values by the session's, keep the property
/// names. The `*Settings` structs are the inspector sections' controls (ADR 056: one window, no steps).
@MainActor @Observable
final class SpectroscopyRoomModel {
    // Elements & maps
    var elements = ElementSelection()
    var mapMode: MapMode = .netCounts
    /// The display kernel of the element maps (Velox pre-filter, display only here): the controller applies it to the signed net
    /// map before the clamp; the raw map and the export are untouched; every tile names it.
    var smoothing: MapSmoothing = .none
    var mixed: Set<Int> = []                   // tiles picked into the ColorMix
    var tiles: [MapTile] = []
    /// Colour per element the person chose in the active map's popover; absent: `ElementPalette`. View state: the element
    /// states the replay record keeps (`QuantificationMethod.ElementState`) hold no colour and a colour is not a method
    /// setting, so it lives (and is lost with the window) here, reset when a spectrum image is bound.
    var elementColors: [Int: Color] = [:]
    /// Contrast window and gamma per map (HAADF and each element); absent: the full range, gamma 1. View state, as above.
    var mapDisplays: [ActiveMap: MapDisplay] = [:]
    var haadfColormap: ColormapKind = .gray
    /// The scan's real-space pixel size and unit when the file states one (Velox, GMS); nil: no scale bar (none is invented).
    var scanPixel: (size: Double, unit: String)?
    /// Bumped whenever `tiles` or `backdrop` are replaced, so the map's bitmap is rebuilt by identity, not by comparing arrays.
    var tileRevision = 0
    /// The HAADF backdrop under the ColorMix (spec 2 D-2: the HAADF tile's outline toggles it); off, the mix sits on black.
    var mixHAADF = true
    /// The element whose lines the spectrum emphasises (spec 2 D-15): set by a click or hover on its tile or table cell; nil: none.
    var highlightedZ: Int?
    /// Scene state (spec 2 D-7): the maps block's share of the room's height, and the ColorMix's share of the maps block's width;
    /// nil = the plan's own default (`SpectroscopyRoomPlan.mapsFraction`, `MapGridLayout`). Neither is a method setting.
    var mapsFraction: CGFloat?
    var mixFraction: CGFloat?

    // Auto ID (the Elements & maps step's proposer run; the compute is the controller's)
    private(set) var autoID = AutoIDState()
    var onAutoID: (() -> Void)?
    var onCancelAutoID: (() -> Void)?

    // Regions: one live region on the active map; pins are frozen copies of it (ADR 056)
    var regions: [RegionSummary] = []
    var selectedRegion: Int?
    var drawTool: DrawTool = .rectangle
    var pins: [PinnedRegion] = []
    static let maximumPins = 3
    var compare: CompareBasis = .wholeMap
    /// The viewport follows the listed lines until the person pans or zooms it (reset returns it to them).
    var viewportIsManual = false
    /// The upper end of the fit range (keV) once the controller knows it: lines above it do not stretch the opening view.
    var fitEndKeV: Double?

    // Spectrum
    var series: SpectrumSeries
    var markers: [LineMarker] = []
    var layers = SpectrumLayers()
    var viewport: SpectrumViewport
    var spectrumTitle = "Spectrum"
    /// The pixels pooled into `series` (the region's, or the whole map's): the "counts / px" unit divides by it. 0 = unknown.
    var spectrumPixels = 0
    /// The line and background windows the net maps use, as energy bands the spectrum can draw (Show › Windows).
    var windowBands: [WindowBand] = []
    /// A candidate line picked from the spectrum's cursor menu (the periodic table's own click, set by the controller).
    var onPickElement: ((Int) -> Void)?
    var spectrumSubtitle = ""

    // Results
    var results: [ResultRow] = []
    var unit: AbundanceUnit = .atomic
    var resultsTitle = "Results"
    /// The session's `validation` string for the shown at% (ADR 054 §3: "none"). nil = unknown.
    var validation: String?
    var unvalidated: Bool { ValidationState.isUnvalidated(validation) }
    var ratioLine: RatioLine?
    /// Under the table (R3): the fit's warnings, why no at% was computed, why there is no fit at all.
    var fitWarnings: [FitWarning] = []
    var abundanceNote: String?
    /// The shown at% / wt% was computed without the absorption correction (off, or refused): the column header says so.
    var abundanceWithoutAbsorption = false
    var fitFailure: String?
    /// "Whole map, same listed elements, for comparison: Mg 0.9 ± 0.2 · Al 97.6 ± 0.5 · Si 1.5 ± 0.3 at%": the same method on the whole map, shown
    /// under a region's numbers; nil for the whole map itself, before Quantify and when no at% was computed.
    var wholeMapLine: String?
    /// What the Export… menu (the panel's header, the inspector's Export section) is writing and what it last said.
    var pendingExport: PendingExport?
    var exportNote: String?
    /// The unlisted-line check (WP3b F1): "checking…" until it lands, then what it found; nil before a fit. Its two buttons
    /// call the controller: the named elements become Fit only, or are dismissed (switched Off by the person).
    var unlisted: UnlistedLineNote?
    var onAddUnlistedAsFitOnly: (() -> Void)?
    var onDismissUnlisted: (() -> Void)?
    /// A fit is running (the numbers shown are the previous ones until it lands).
    var isFitting = false
    var fitFooter = ""
    /// False until WP3 fits a spectrum: the table then shows window net counts only, "—" in the k-free and at% columns.
    var hasFit = true
    var resultsFooter = ""

    /// Bound to a real spectrum image by `SpectroscopyRoomController` (false for the fixture): the controls that
    /// have nothing behind them yet (smoothing, the at% map, Quantify, Export) are not drawn.
    var isLive = false
    /// The spectrum image's own grid, and its HAADF on it (0...1, row-major, empty when the file has none).
    var gridWidth = 0
    var gridHeight = 0
    var backdrop: [Float] = []
    /// The selected region's shape, outlined on the map; nil for the whole map.
    var regionOutline: SpectrumRegionShape?
    /// Set by the controller: a shape drawn on the map becomes a region; a region is removed.
    /// A shape drawn, moved or resized on a map; `final` is false while the pointer is still down (the spectrum follows,
    /// the numbers wait for the end).
    var onRegionEdit: ((SpectrumRegionShape, _ final: Bool) -> Void)?
    var onRemoveRegion: ((Int) -> Void)?
    var onPin: (() -> Void)?
    var onUnpin: ((Int) -> Void)?

    // Inspectors
    var image = SpectrumImageSettings()
    var regionSettings = RegionSettings()
    var quantify = QuantifySettings()
    var export = ExportSettings()
    var mapLabel = "ColorMix"
    /// The live region's colour: its outline on the ColorMix, its curve in the spectrum and its capsule share it (pins keep their tints).
    static let liveRegionColor = Color.accentColor

    init(series: SpectrumSeries) {
        self.series = series
        self.viewport = SpectrumViewport(domain: series.domain, minimumSpan: 2 * series.energyStep)
    }

    /// Map units shown in the map header.
    var mapUnits: String { mapMode.units }

    // MARK: Auto ID

    /// A run starts; its token is the only one whose result may land (a newer run or a cancel invalidates it).
    func beginAutoID() -> Int {
        autoID.token += 1
        autoID.running = true
        autoID.failure = nil
        return autoID.token
    }

    /// The run's result: suggestions by `rerunAutoID` (a person's picks are never touched; the controller applies them), the
    /// sum-peak questions stay in the outcome. False, and nothing changes, when the run was cancelled or superseded.
    @discardableResult
    func finishAutoID(token: Int, outcome: AutoIDOutcome) -> Bool {
        guard token == autoID.token, autoID.running else { return false }
        autoID.running = false
        autoID.outcome = outcome
        autoID.listedAtRun = elements.activeZ   // R8: the excesses were judged against this list (see `autoIDExcesses`)
        elements.rerunAutoID(accepted: [:], suggestions: outcome.suggestions)
        return true
    }

    /// The excesses of the latest outcome, while the listed elements are the ones it was run against: an excess is "beside a
    /// listed line", so once a pick changes the list the sentence is stale and goes (R8; Auto ID's next run rejudges).
    var autoIDExcesses: [AutoIDExcess] {
        guard let o = autoID.outcome, autoID.listedAtRun == elements.activeZ else { return [] }
        return o.excesses
    }

    /// Spec 2 D-3: the controller applies the run's picks right after the landing, which changes the listed set; the excesses
    /// were judged against the list AFTER those picks, so re-mark it (else `autoIDExcesses` goes stale at once, R8).
    func markListedAfterPicks() { autoID.listedAtRun = elements.activeZ }
    /// The run could not be made (no beam energy, a rank-deficient design): the earlier outcome stays, the reason shows.
    func failAutoID(token: Int, message: String) {
        guard token == autoID.token, autoID.running else { return }
        autoID.running = false
        autoID.failure = message
    }

    /// Invalidates the running token; elements, markers and the earlier outcome are exactly as they were.
    func cancelAutoID() {
        autoID.token += 1
        autoID.running = false
    }

    /// The image changed under the room: nothing proposed for the old one stays.
    func resetAutoID() {
        let t = autoID.token + 1
        autoID = AutoIDState()
        autoID.token = t
    }

    func toggleMix(_ z: Int) { if mixed.contains(z) { mixed.remove(z) } else { mixed.insert(z) } }

    /// The colour of element `z` everywhere (tile, ColorMix, markers, table): the person's, else the palette's.
    func color(_ z: Int) -> Color { elementColors[z] ?? ElementPalette.color(z) }
    /// The person's window for the map, else its default: a robust percentile stretch of its own values (`MapContrast`), kept
    /// per tile revision so the sort runs once per map and not per draw.
    func display(_ map: ActiveMap) -> MapDisplay { mapDisplays[map] ?? defaultDisplay(map) }
    func defaultDisplay(_ map: ActiveMap) -> MapDisplay {
        if let c = defaultDisplays[map], c.revision == tileRevision, c.count == pixels(of: map).count { return c.display }
        let px = pixels(of: map)
        let d = MapContrast.defaultWindow(of: px)
        defaultDisplays[map] = (tileRevision, px.count, d)
        return d
    }
    @ObservationIgnored private var defaultDisplays: [ActiveMap: (revision: Int, count: Int, display: MapDisplay)] = [:]

}

/// A text file the save panel is about to write (the results CSV or the method JSON).
struct PendingExport: Equatable {
    var text: String
    var isJSON: Bool
    var name: String
}

struct AutoIDState: Equatable {
    var running = false
    var outcome: AutoIDOutcome?
    var failure: String?
    var listedAtRun: [Int] = []
    fileprivate(set) var token = 0
}

struct MapTile: Identifiable {
    var z: Int
    var width: Int, height: Int
    var values: [Float]                        // 0...1, row-major (the smoothed map when a kernel is set)
    /// The raw signed counts the file gave (net or integrated), unsmoothed, row-major; what an export writes. Empty for the fixture.
    var counts: [Double] = []
    /// Why the tile's map is a picture and not a measurement (it is still in the ColorMix; the note stays): its window method says "not a measurement" (s\u{00B7}B \u{2265} G).
    var notMeasuredWhy: String? = nil
    /// Counts at value 1 (the tile's own maximum; 1 when unknown): the histogram's real values (spec 2 D-13).
    var scale: Float = 1
    /// "Al Kα+Kβ": the lines the person chose for this map (nil = the default line, which says nothing).
    var lineLabel: String? = nil
    var id: Int { z }
}

/// Which map a display setting belongs to: a tile's chip popover edits its colour, contrast and gamma.
enum ActiveMap: Hashable, Sendable {
    case haadf, colorMix
    case element(Int)
}

/// Contrast window (fractions of the map's own range) and gamma of one map: presentation only, never written to a product.
struct MapDisplay: Equatable, Sendable {
    var lo: Float = 0, hi: Float = 1, gamma: Float = 1
    var isIdentity: Bool { lo == 0 && hi == 1 && gamma == 1 }
    /// 0...1 in, 0...1 out: the window, then the exponent the colour bar uses (`pow(fraction, 1 / gamma)`).
    func apply(_ v: Float) -> Float {
        guard !isIdentity else { return v }
        let span = max(hi - lo, 1e-6)
        return pow(min(max((v - lo) / span, 0), 1), 1 / max(gamma, 0.05))
    }
}

/// What the spectrum's grey overlay is: nothing, or the whole map's spectrum scaled to the region's counts.
enum CompareBasis: String, CaseIterable, Sendable { case none = "None", wholeMap = "Whole map" }

/// A frozen copy of the live region (Pin, ADR 056 addendum): its own spectrum, overlaid in its own colour while the live
/// rectangle moves on.
struct PinnedRegion: Identifiable, Equatable {
    var id: Int
    var label: String
    var tint: Color
    var shape: SpectrumRegionShape?
    var pixels: Int
    var spectrum: [Double]
    static let tints: [Color] = [.yellow, .pink, .teal]
}

struct RegionSummary: Identifiable, Equatable {
    var id: Int
    var name: String
    var pixels: Int
    var counts: Double                         // millions
    var tint: Color
    /// A region the user drew (removable); the whole map is not.
    var isDrawn = false
}

struct RatioLine: Equatable {
    var label: String                          // "Mg / Si net ratio"
    var value: Double, sigma: Double
    var note: String                           // "k-free, counting only"
}

// MARK: - Inspector settings (≤ 7 rows per step; ADR 054 §8)

struct SpectrumImageSettings {
    var source: String?
    var sourceWarning = false
    /// Hover text of the warning mark: what is not registered and why.
    var sourceNote: String?
    var frameLo: Int?, frameHi: Int?, frames: Int?
    /// A read-only "Frames" row ("1607 summed"), for a file whose frame range cannot be changed after the open.
    var framesReadout: String?
    var energyAxis = "File"
    var energyAxisReadout: String?
    /// The pooled fit's refinement of that axis (file vs refined, ADR 054 item 4); nil before a fit.
    var energyAxisRefined: String?
    var liveDead: String?
    var geometry: String?
}

/// The Region section's observed settings: only what a view reads (the phase row). The region's pixel count and counts are the
/// spectrum strip's (`spectrumPixels`, `spectrumSubtitle`); nothing written on a live-drag tick lives here.
struct RegionSettings {
    var phase: String?
}

/// The file and the region a spectrum CSV is about (its header lines).
struct SpectrumLabel: Equatable {
    var imageName: String
    var regionName: String
}

/// What the Export step will write, built by Core from the last fit (`SpectroscopyExport`); all nil until Quantify has run.
struct ExportSettings {
    var csv: String?
    var methodJSON: String?
    var elements: String?
    /// What names the shown spectrum's CSV, set once a spectrum is shown. The CSV itself is built when it is exported
    /// (`ExportSection.spectrumExport`, from `series`), not on every live-drag tick; nil until a spectrum is shown (the button is off).
    var spectrumOf: SpectrumLabel?
    var fileStem = "spectroscopy"
    /// The maps' file stem: the image's own name, no region (the maps are the whole scan). Set by the controller with the spectrum.
    var mapsStem = "spectroscopy"
    /// Maps… writes the scale bar into the PNGs (the owner's choice; the CSV never has one).
    var scaleBar = true
}

// MARK: - Illustrative fixture

extension SpectroscopyRoomModel {
    /// Illustrative Al-Mg-Si spectrum and numbers in the mock's shape. Synthetic.
    static var fixture: SpectroscopyRoomModel {
        let n = 230, e0 = 0.5, de = 0.01
        let peaks: [(Double, Double, Double)] = [(0.93, 300, 0.045), (1.25, 1000, 0.05), (1.487, 40_000, 0.055), (1.74, 1000, 0.056)]
        let matrix: [(Double, Double, Double)] = [(0.93, 70, 0.045), (1.25, 340, 0.05), (1.487, 41_000, 0.055), (1.74, 280, 0.056)]
        func gauss(_ e: Double, _ p: [(Double, Double, Double)]) -> Double {
            p.reduce(0) { $0 + $1.1 * exp(-pow(e - $1.0, 2) / (2 * $1.2 * $1.2)) }
        }
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func noise() -> Double {   // deterministic ±1 σ-ish jitter
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return (Double(rng >> 40) / Double(1 << 24)) * 2 - 1
        }
        var data: [Double] = [], bg: [Double] = [], model: [Double] = [], overlay: [Double] = []
        for i in 0..<n {
            let e = e0 + Double(i) * de
            let b = 55 * exp(-(e - 0.5) * 1.1) + (e > 1.56 ? 6 : 14) * exp(-(e - 1.0) * 0.9) * 0.5
            let m = b + gauss(e, peaks)
            bg.append(b); model.append(m); overlay.append(max(b + gauss(e, matrix) * 0.97, 1))
            data.append(max(m + noise() * m.squareRoot() * 1.7, 0.5))
        }
        let series = SpectrumSeries(energyStart: e0, energyStep: de, data: data, background: bg, model: model, overlay: overlay)
        let m = SpectroscopyRoomModel(series: series)
        // Cu is a documented DEFAULT (Q phase, ADR 054 §6), not a manual pick.
        m.elements = ElementSelection(
            roles: [13: .quantify, 12: .quantify, 14: .quantify, 29: .quantify, 8: .fitOnly],
            manual: [],
            suggestions: [ElementSuggestion(z: 31, reason: "Ga: from FIB?"), ElementSuggestion(z: 18, reason: "Ar: Al sum or Ar?")])
        m.markers = [
            LineMarker(label: "Cu Lα", energy: 0.93, elementZ: 29),
            LineMarker(label: "Mg Kα", energy: 1.254, elementZ: 12),
            LineMarker(label: "Al Kα", energy: 1.487, elementZ: 13),
            LineMarker(label: "Al K edge", energy: 1.5596, elementZ: 13, kind: .edge),
            LineMarker(label: "Si Kα", energy: 1.74, elementZ: 14)]
        m.mixed = [13, 12, 14]
        m.tiles = [13, 12, 14, 29, 8].map { z in MapTile.synthetic(z: z) }
        m.regions = [
            RegionSummary(id: 0, name: "Whole map", pixels: 65_536, counts: 41.2, tint: .gray),
            RegionSummary(id: 1, name: "Matrix (drawn)", pixels: 52_900, counts: 31.6, tint: .gray),
            RegionSummary(id: 2, name: "β″ precipitates (drawn)", pixels: 1_842, counts: 4.31, tint: .green),
            RegionSummary(id: 3, name: "Cu-rich (drawn)", pixels: 212, counts: 0.52, tint: .orange)]
        m.selectedRegion = 2
        m.results = [
            ResultRow(z: 13, netCounts: 412_380, netSigma: 650, kFreeRatio: 1, kFreeSigma: nil, atPercent: 88.1, atSigma: 0.9, wtPercent: 83.0, wtSigma: 1.0, sigmaTerms: "counting 0.2 % · fit 0.1 % · absorption 1 %"),
            ResultRow(z: 12, netCounts: 9_840, netSigma: 130, kFreeRatio: 0.0239, kFreeSigma: 0.0003, atPercent: 5.6, atSigma: 1.1, wtPercent: 4.5, wtSigma: 0.9, sigmaTerms: "counting 0.6 % · fit 0.4 % · k-factor 20 % flat · absorption 3 % · thickness 4 % → ±1.1 at% (k dominates)"),
            ResultRow(z: 14, netCounts: 9_010, netSigma: 125, kFreeRatio: 0.0219, kFreeSigma: 0.0003, atPercent: 5.1, atSigma: 1.0, wtPercent: 4.5, wtSigma: 0.9, sigmaTerms: "counting 0.6 % · fit 0.4 % · k-factor 20 % flat · absorption 3 % → ±1.0 at%"),
            ResultRow(z: 29, netCounts: 2_100, netSigma: 60, kFreeRatio: 0.0051, kFreeSigma: 0.0001, atPercent: 1.2, atSigma: 0.3, wtPercent: 3.0, wtSigma: 0.8, sigmaTerms: "counting 1.3 % · fit 0.9 % · k-factor 20 % flat → ±0.3 at%")]
        m.validation = "none"
        m.spectrumTitle = "Spectrum · β″ pooled"; m.spectrumSubtitle = "matrix, norm. to Al Kα"
        m.resultsTitle = "Results · β″ pooled"
        m.image = SpectrumImageSettings(
            source: "Linked 4D · shape differs", sourceWarning: true, frameLo: 1, frameHi: 24, frames: 24,
            energyAxis: "Refined", energyAxisReadout: "+4 eV, 9.98 eV/ch",
            liveDead: "1311 s total · dead 52 %", geometry: "TOA 18° · 4 det. · 0.12 sr")
        m.regionSettings = RegionSettings(phase: "β″ (Mg₅Si₆)")
        m.quantify.absorptionNote = "4 detectors · TOA from file"
        m.quantify.thickness = 80; m.quantify.thicknessSigma = 15; m.quantify.quality = "χ²ᵣ 1.04 (Pearson)"
        m.smoothing = .none
        m.ratioLine = RatioLine(label: "Mg / Si net ratio", value: 1.092, sigma: 0.021, note: "k-free, counting only")
        m.fitFooter = "Least squares · empirical continuum + Al edge · Bote-Salvat k (ε Super-X G1) · absorption 80 ± 15 nm · no escape peaks"
        return m
    }
}

extension MapTile {
    /// A fixture map: needles and a blob, per element.
    static func synthetic(z: Int, size: Int = 56) -> MapTile {
        var v = [Float](repeating: 0, count: size * size)
        for y in 0..<size { for x in 0..<size {
            let fx = Float(x) / Float(size), fy = Float(y) / Float(size)
            var a: Float
            switch z {
            case 13: a = 0.2 - 0.12 * exp(-(pow(fx - 0.5, 2) + pow(fy - 0.5, 2)) * 18)
            case 12, 14:
                let n1 = exp(-pow((fy - 0.5) - 0.9 * (fx - 0.45), 2) * 400) * (abs(fx - 0.5) < 0.3 ? 1 : 0)
                let n2 = exp(-pow(fx - 0.62, 2) * 500) * (abs(fy - 0.4) < 0.35 ? 1 : 0)
                a = Float(max(n1, n2)) * (z == 12 ? 0.9 : 0.75)
            default: a = Float(exp(-(pow(fx - 0.3, 2) + pow(fy - 0.28, 2)) * 700)) + Float(exp(-(pow(fx - 0.7, 2) + pow(fy - 0.7, 2)) * 700))
            }
            v[y * size + x] = min(max(a, 0), 1)
        } }
        return MapTile(z: z, width: size, height: size, values: v)
    }
}

/// Role symbol and colour for an element — colour on symbols only.
enum ElementPalette {
    static func color(_ z: Int) -> Color {
        switch z {
        case 13: .blue
        case 12: .green
        case 14: .red
        case 29: .orange
        case 8: .gray
        default: Color(hue: Double((z * 47) % 360) / 360, saturation: 0.6, brightness: 0.8)
        }
    }
}

extension ElementRole {
    var symbolName: String {
        switch self {
        case .quantify: "circle.fill"
        case .fitOnly: "circle.lefthalf.filled"
        case .off: "circle"
        }
    }
}
