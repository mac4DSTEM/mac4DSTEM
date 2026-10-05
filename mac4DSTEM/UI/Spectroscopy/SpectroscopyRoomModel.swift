import SwiftUI
import Observation

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
/// names. The five `*Settings` structs are the inspectors' controls, one per step.
@MainActor @Observable
final class SpectroscopyRoomModel {
    // Elements & maps
    var elements = ElementSelection()
    var mapMode: MapMode = .netCounts
    var smoothing = "None"
    var mixed: Set<Int> = []                   // tiles whose checkbox is on
    var tiles: [MapTile] = []

    // Regions
    var regions: [RegionSummary] = []
    var selectedRegion: Int?
    var drawTool: DrawTool = .rectangle

    // Spectrum
    var series: SpectrumSeries
    var markers: [LineMarker] = []
    var layers = SpectrumLayers()
    var viewport: SpectrumViewport
    var spectrumTitle = "Spectrum"
    var spectrumSubtitle = ""

    // Results
    var results: [ResultRow] = []
    var unit: AbundanceUnit = .atomic
    var expandedRows: Set<Int> = []
    var resultsTitle = "Results"
    /// The session's `validation` string for the shown at% (ADR 054 §3: "none"). nil = unknown.
    var validation: String?
    var unvalidated: Bool { ValidationState.isUnvalidated(validation) }
    var ratioLine: RatioLine?
    var fitFooter = ""

    // Inspectors
    var image = SpectrumImageSettings()
    var regionSettings = RegionSettings()
    var quantify = QuantifySettings()
    var export = ExportSettings()
    var mapLabel = "ColorMix"
    var scaleBar = ""                          // empty: no scale bar drawn

    init(series: SpectrumSeries) {
        self.series = series
        self.viewport = SpectrumViewport(domain: series.domain, minimumSpan: 2 * series.energyStep)
    }

    /// Map units shown in the map header.
    var mapUnits: String { mapMode == .atomic ? "at%" : "counts" }

    func toggleMix(_ z: Int) { if mixed.contains(z) { mixed.remove(z) } else { mixed.insert(z) } }
    func toggleExpanded(_ z: Int) { if expandedRows.contains(z) { expandedRows.remove(z) } else { expandedRows.insert(z) } }
}

struct MapTile: Identifiable {
    var z: Int
    var width: Int, height: Int
    var values: [Float]                        // 0...1, row-major
    var id: Int { z }
}

struct RegionSummary: Identifiable, Equatable {
    var id: Int
    var name: String
    var pixels: Int
    var counts: Double                         // millions
    var tint: Color
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
    var frameLo: Int?, frameHi: Int?, frames: Int?
    var energyAxis = "File"
    var energyAxisReadout: String?
    var countsHistogram: [Double] = []
    var countsMedian: String?
    var liveDead: String?
    var geometry: String?
}

struct RegionSettings {
    var source = "Drawn"
    var phase: String?
    var pixels: String?
    var counts: String?
    var liveTime: String?
    var lineWidth = 3
    var isLine = false                         // Line width appears only for a drawn line
    var compare: String?
}

struct QuantifySettings {
    var method = ""
    var background = "Empirical + Al edge"     // ADR 054 §2
    var kFactors = "Brown-Powell (computed)"   // ADR 054 §3
    var absorption = true
    var absorptionNote: String?
    var thickness: Double?, thicknessSigma: Double?
    var chiSquared: Double?
    var expertOpen = false
    var estimator = "Least squares"            // ADR 054 §1
    var sigmaK: Double? = 20                   // flat 20 % (second opinion C4)
    var polyOrder = 6   // eXSpy's whole-range parity polynomial (ADR 054 corrections)
    var energyLock = false
}

struct ExportSettings {
    var format = "CSV"
    var includeMethod = true
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
            LineMarker(label: "Ga Lα?", energy: 1.10, elementZ: 31, kind: .suspect),
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
        m.resultsTitle = "Results · β″ pooled"; m.scaleBar = "50 nm"
        m.image = SpectrumImageSettings(
            source: "Linked 4D · shape differs", sourceWarning: true, frameLo: 1, frameHi: 24, frames: 24,
            energyAxis: "Refined", energyAxisReadout: "+4 eV, 9.98 eV/ch",
            countsHistogram: [9, 8, 6, 4, 3, 2, 1.4, 1, 0.6, 0.4], countsMedian: "median 11",
            liveDead: "1311 s total · dead 52 %", geometry: "TOA 18° · 4 det. · 0.12 sr")
        m.regionSettings = RegionSettings(source: "Phase", phase: "β″ (Mg₅Si₆)", pixels: "1 842 · 2.8 %", counts: "4.31 M",
                                          liveTime: "37 s · 20 ms/px", compare: "Al Kα · live time")
        m.quantify.method = "Mg/Si in Al · LS · BP k"; m.quantify.absorptionNote = "4 detectors · TOA from file"
        m.quantify.thickness = 80; m.quantify.thicknessSigma = 15; m.quantify.chiSquared = 1.04
        m.smoothing = "3 × 3 · σ 1 px"
        m.ratioLine = RatioLine(label: "Mg / Si net ratio", value: 1.092, sigma: 0.021, note: "k-free, counting only")
        m.fitFooter = "Least squares · empirical continuum + Al edge · Brown-Powell k (ε Super-X G1) · absorption 80 ± 15 nm · no escape peaks"
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
