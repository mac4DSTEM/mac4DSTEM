import Foundation
import CoreGraphics

// The Spectroscopy room's pure half (v5.0 WP2 lane V, ADR 054/055): everything the
// views decide that is not drawing — element roles, the "Auto ID never drops manual
// picks" rule, the narrow-layout switch, the spectrum's axes, the residual strip.
// No SwiftUI, no loading, no compute of a scientific number; the numbers shown come
// from the session (lane R) through `SpectroscopyRoomModel`. Unit-tested in
// `SpectroscopyViewModelTests`.

// MARK: - Layout

/// ADR 055 §1: below about 760 pt of content the results table stacks under the map
/// and the spectrum header's toggles fold into one "Show" menu.
nonisolated enum SpectroscopyLayout {
    static let narrowThreshold: CGFloat = 760
    static func isNarrow(contentWidth: CGFloat) -> Bool { contentWidth < narrowThreshold }
}

// MARK: - Elements

/// What an element does in the fit (ADR 054 §6).
nonisolated enum ElementRole: String, CaseIterable, Equatable, Sendable {
    case quantify, fitOnly, off
    var title: String {
        switch self {
        case .quantify: "Quantify"
        case .fitOnly: "Fit only"
        case .off: "Off"
        }
    }
}

/// Which line family of an element the markers and the fit use (the menu's "Lines ▸").
nonisolated enum LineFamily: String, CaseIterable, Equatable, Sendable { case K, L, M }

/// A proposer suggestion: a named conflict, never applied silently.
nonisolated struct ElementSuggestion: Equatable, Sendable {
    var z: Int
    var reason: String            // "Ga: from FIB?", "Ar: Al sum or Ar?"
    var proposedRole: ElementRole = .quantify
}

/// How one periodic-table cell is drawn (mock screen 4).
nonisolated enum PeriodicCellState: Equatable, Sendable {
    case quantify, fitOnly, off
    case suggested(String)
    /// H, He, Li, Be: no usable line at this detector window (greyed, with the reason).
    case unavailable(String)
}

/// The element choices of one spectrum image. Roles the owner set (`manual`) are
/// never touched by the proposer — Velox's Auto ID weakness, designed out here.
nonisolated struct ElementSelection: Equatable, Sendable {
    private(set) var roles: [Int: ElementRole] = [:]
    /// Elements whose role a person chose (click or menu). Accepting or re-running
    /// suggestions leaves these exactly as they are.
    private(set) var manual: Set<Int> = []
    private(set) var suggestions: [ElementSuggestion] = []
    private(set) var families: [Int: LineFamily] = [:]

    init(roles: [Int: ElementRole] = [:], manual: Set<Int> = [], suggestions: [ElementSuggestion] = []) {
        self.roles = roles
        self.manual = manual
        self.suggestions = suggestions
    }

    /// No lines below Z = 5 at an EDX window.
    static func unavailableReason(z: Int) -> String? {
        z <= 4 ? "No usable X-ray line at this detector window" : nil
    }

    func role(_ z: Int) -> ElementRole { roles[z] ?? .off }
    func family(_ z: Int) -> LineFamily { families[z] ?? .K }

    func cellState(_ z: Int) -> PeriodicCellState {
        if let why = Self.unavailableReason(z: z) { return .unavailable(why) }
        if let s = suggestions.first(where: { $0.z == z }) { return .suggested(s.reason) }
        switch role(z) {
        case .quantify: return .quantify
        case .fitOnly: return .fitOnly
        case .off: return .off
        }
    }

    var quantified: [Int] { roles.filter { $0.value == .quantify }.keys.sorted() }
    /// Quantified and fit-only elements, by Z: the ones whose lines are windowed, marked and (for the first) tabulated.
    var activeZ: [Int] { roles.filter { $0.value != .off }.keys.sorted() }

    /// Left click: Quantify <-> Off. On a pending suggestion the click applies that
    /// suggestion's proposed role (ADR 054 §6: one click accepts one suggestion).
    mutating func click(_ z: Int) {
        guard Self.unavailableReason(z: z) == nil else { return }
        if let s = suggestions.first(where: { $0.z == z }) { set(z, s.proposedRole); return }
        let next: ElementRole = (role(z) == .quantify) ? .off : .quantify
        set(z, next)
    }

    /// Right-click menu choice.
    mutating func set(_ z: Int, _ role: ElementRole) {
        guard Self.unavailableReason(z: z) == nil else { return }
        roles[z] = role
        manual.insert(z)
        suggestions.removeAll { $0.z == z }
    }

    mutating func setFamily(_ z: Int, _ family: LineFamily) { families[z] = family }

    /// The Review popover: accept ONE pending suggestion with the role the person picked
    /// on its row. A person's earlier choice for that element is never overwritten; the
    /// suggestion is simply dismissed.
    mutating func accept(_ z: Int, as role: ElementRole) {
        if !manual.contains(z) { set(z, role) } else { suggestions.removeAll { $0.z == z } }
    }

    /// The proposer ran again (new region, new frame range). Roles it set earlier and a
    /// person never touched fall back to Off unless proposed again; manual choices stay;
    /// an element a person already decided is never suggested.
    mutating func rerunAutoID(accepted: [Int: ElementRole], suggestions new: [ElementSuggestion]) {
        for z in roles.keys where !manual.contains(z) { roles[z] = nil }
        for (z, r) in accepted where !manual.contains(z) { roles[z] = r }
        suggestions = new.filter { !manual.contains($0.z) }
    }
}

/// Periodic-table geometry: 18 columns, f-block as a collapsed extra row (La–Yb, Ac–No;
/// Lu and Lr sit in group 3).
nonisolated enum PeriodicLayout {
    static let symbols: [String] = ("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr "
        + "Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu "
        + "Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr "
        + "Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og").split(separator: " ").map(String.init)

    static func symbol(_ z: Int) -> String { symbols[z - 1] }
    static func z(of symbol: String) -> Int? { symbols.firstIndex(of: symbol).map { $0 + 1 } }

    /// (row, column), both 0-based; row 7/8 (0-based 7, 8) are the f-block rows.
    static func position(_ z: Int) -> (row: Int, column: Int) {
        switch z {
        case 1: return (0, 0)
        case 2: return (0, 17)
        case 3...4: return (1, z - 3)
        case 5...10: return (1, z - 5 + 12)
        case 11...12: return (2, z - 11)
        case 13...18: return (2, z - 13 + 12)
        case 19...36: return (3, z - 19)
        case 37...54: return (4, z - 37)
        case 55...56: return (5, z - 55)
        case 57...70: return (7, z - 57 + 2)
        case 71...86: return (5, z - 71 + 2)
        case 87...88: return (6, z - 87)
        case 89...102: return (8, z - 89 + 2)
        default: return (6, z - 103 + 2)
        }
    }

    static func isFBlock(_ z: Int) -> Bool { (57...70).contains(z) || (89...102).contains(z) }
}

// MARK: - Spectrum axes

nonisolated struct SpectrumLayers: Equatable, Sendable {
    var spectrum = true, background = true, model = true, residual = true, overlay = true
    var log = true
}

/// The visible energy window, always inside the spectrum's own range. Zoom is about a
/// point (wheel/pinch), pan is a drag; both clamp so the window never leaves the data.
nonisolated struct SpectrumViewport: Equatable, Sendable {
    var domain: ClosedRange<Double>
    var lo: Double
    var hi: Double
    /// keV; two channels of the spectrum (`SpectrumSeries.energyStep`), so zooming never
    /// shows less than a line's worth of data.
    var minimumSpan: Double

    init(domain: ClosedRange<Double>, minimumSpan: Double = 0.02) {
        self.domain = domain; self.minimumSpan = minimumSpan; lo = domain.lowerBound; hi = domain.upperBound
    }

    var span: Double { hi - lo }
    mutating func reset() { lo = domain.lowerBound; hi = domain.upperBound }

    /// energy (keV) -> fraction of the plot width [0, 1] for the visible window.
    func fraction(of energy: Double) -> Double { (energy - lo) / span }
    func energy(atFraction f: Double) -> Double { lo + f * span }

    /// `factor` > 1 zooms in. The energy under `anchor` (a fraction of the plot width)
    /// stays under it.
    mutating func zoom(factor: Double, anchor: Double) {
        guard factor > 0, factor.isFinite else { return }
        let e = energy(atFraction: anchor)
        let newSpan = min(max(span / factor, minimumSpan), domain.upperBound - domain.lowerBound)
        lo = e - anchor * newSpan
        hi = lo + newSpan
        clamp()
    }

    /// Shift the window by a fraction of the *visible* width (positive = towards high energy).
    mutating func pan(byFraction f: Double) { let d = f * span; lo += d; hi += d; clamp() }

    private mutating func clamp() {
        let s = hi - lo
        if lo < domain.lowerBound { lo = domain.lowerBound; hi = lo + s }
        if hi > domain.upperBound { hi = domain.upperBound; lo = hi - s }
        lo = max(lo, domain.lowerBound)
    }
}

nonisolated enum AxisTicks {
    /// One tick per decade inside [lo, hi] (counts), as exponents: 10^e.
    static func logDecades(lo: Double, hi: Double) -> [Int] {
        guard lo > 0, hi > lo else { return [] }
        let a = Int(ceil(log10(lo) - 1e-9)), b = Int(floor(log10(hi) + 1e-9))
        return a <= b ? Array(a...b) : []
    }

    /// "Nice" linear ticks (1, 2, 5 × 10^k) with about `target` marks.
    static func niceStep(lo: Double, hi: Double, target: Int) -> Double {
        let raw = (hi - lo) / Double(target)
        let mag = pow(10, floor(log10(raw)))
        return [1.0, 2, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
    }

    /// Decimals a tick label needs so that neighbouring ticks never print alike
    /// (a 0.02 keV step must read 0.50, 0.52, 0.54, not 0.5, 0.5, 0.5).
    static func decimals(forStep step: Double) -> Int {
        guard step > 0, step.isFinite else { return 0 }
        return min(6, max(0, Int((-log10(step) - 1e-9).rounded(.up))))
    }

    static func label(_ v: Double, step: Double) -> String { String(format: "%.\(decimals(forStep: step))f", v) }

    static func linear(lo: Double, hi: Double, target: Int = 6) -> [Double] {
        guard hi > lo, target > 0 else { return [] }
        let step = niceStep(lo: lo, hi: hi, target: target)
        let first = ceil(lo / step - 1e-9) * step
        return Array(stride(from: first, through: hi + step * 1e-9, by: step))
    }
}

/// Counts-axis range for the log plot. `minPositive` is +∞ when no visible channel has a
/// positive count (an empty window); the floor then falls back to 1 so no coordinate is NaN.
nonisolated enum SpectrumYRange {
    static func log(minPositive: Double, maximum: Double) -> (lo: Double, hi: Double) {
        let lo = minPositive.isFinite && minPositive > 0 ? max(1, pow(10, floor(log10(minPositive)))) : 1
        let top = maximum.isFinite && maximum > 0 ? maximum * 1.05 : 10
        return (lo, max(pow(10, ceil(log10(top))), lo * 10))
    }
}

/// The residual strip: (data − model)/√model, the Poisson-normalised residual; ±3 is the
/// strip's frame. A channel with no modelled counts carries no information and shows 0.
nonisolated enum ResidualNormalisation {
    static func normalised(data: [Double], model: [Double]) -> [Double] {
        zip(data, model).map { d, m in m > 0 ? (d - m) / m.squareRoot() : 0 }
    }
    static let frame = 3.0
    /// A residual beyond ±3 is drawn at the frame edge and marked as clipped.
    static func isClipped(_ v: Double) -> Bool { abs(v) > frame }
}

/// Validation state as the session reports it (`validation:"none"` for every at% product,
/// ADR 054 §3). Anything but a named, non-"none" validation is shown as unvalidated, so a
/// missing value cannot read as validated.
nonisolated enum ValidationState {
    static func isUnvalidated(_ validation: String?) -> Bool {
        guard let v = validation?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return true }
        return v.lowercased() == "none"
    }
}

/// What the cursor is over: the channel's energy and counts, and the nearest line marker
/// within its own FWHM (`LineMarker.fwhm`), or `lineTolerance` keV when the marker carries none.
nonisolated enum SpectrumHover {
    static let lineTolerance = 0.1
    struct Sample: Equatable { var energy: Double; var counts: Double; var line: String? }
    static func sample(series: SpectrumSeries, viewport: SpectrumViewport, fraction f: Double, markers: [LineMarker]) -> Sample? {
        guard series.count > 0, f >= 0, f <= 1, series.energyStep > 0 else { return nil }
        let e = viewport.energy(atFraction: f)
        let ch = min(series.count - 1, max(0, Int(((e - series.energyStart) / series.energyStep).rounded())))
        let near = markers.filter { $0.kind != .edge }.min { abs($0.energy - e) < abs($1.energy - e) }
        // The cut-off is the marker's own FWHM when it has one (a Mg Kα marker 60 eV wide, a Cu Kα one 160 eV).
        let line = near.flatMap { abs($0.energy - e) <= ($0.fwhm ?? lineTolerance) ? $0.label : nil }
        return Sample(energy: series.energy(ch), counts: series.data[ch], line: line)
    }
}

nonisolated struct SpectrumSeries: Equatable, Sendable {
    var energyStart: Double          // keV of channel 0
    var energyStep: Double           // keV per channel
    var data: [Double]
    var background: [Double]
    var model: [Double]
    var overlay: [Double]?           // e.g. the matrix, normalised to Al Kα

    var count: Int { data.count }
    /// WP2 has no fit yet: a series may carry data only. Curves whose length differs from the
    /// data are treated as absent (never indexed), so a data-only series cannot trap.
    var hasModel: Bool { !data.isEmpty && model.count == data.count }
    var hasBackground: Bool { !data.isEmpty && background.count == data.count }
    var hasOverlay: Bool { overlay.map { $0.count == data.count } ?? false }
    func energy(_ channel: Int) -> Double { energyStart + Double(channel) * energyStep }
    var domain: ClosedRange<Double> { energyStart...(energy(max(count - 1, 0))) }
    var residual: [Double] { hasModel ? ResidualNormalisation.normalised(data: data, model: model) : [] }
}

nonisolated struct LineMarker: Equatable, Identifiable, Sendable {
    enum Kind: Sendable { case line, suspect, edge }   // edge: the Al K edge, grey and dotted
    var label: String                // "Mg Kα", "Ga Lα?", "Al K edge"
    var energy: Double
    var elementZ: Int?
    var kind: Kind = .line           // .suspect: dashed grey italic, "Ga Lα?"
    /// The detector's line width here, keV. The hover's nearest-line cut-off is this one value (nil: `SpectrumHover.lineTolerance`).
    var fwhm: Double? = nil
    var id: String { label }
}

// MARK: - Results

nonisolated enum AbundanceUnit: String, CaseIterable, Sendable { case atomic = "at%", weight = "wt%" }
nonisolated enum MapMode: String, CaseIterable, Sendable { case netCounts = "Net counts", atomic = "at%" }
nonisolated enum DrawTool: String, CaseIterable, Sendable {
    /// What a drag on the map can draw today.
    static let drawable: [DrawTool] = [.rectangle, .ellipse]

    case point, rectangle, ellipse, polygon, line
    var symbol: String {
        switch self {
        case .point: "scope"
        case .rectangle: "rectangle.dashed"
        case .ellipse: "circle.dashed"
        case .polygon: "pentagon"
        case .line: "line.diagonal"
        }
    }
}

nonisolated struct ResultRow: Equatable, Identifiable, Sendable {
    var z: Int
    var netCounts: Double, netSigma: Double
    var kFreeRatio: Double, kFreeSigma: Double?     // nil sigma on the reference (Al = 1)
    var atPercent: Double, atSigma: Double
    var wtPercent: Double, wtSigma: Double
    /// "counting 0.6 % · fit 0.4 % · k-factor 20 % flat · absorption 3 % · thickness 4 % → ±1.1 at%"
    var sigmaTerms: String
    /// "background overlaps Si Kα": another line a background window of this one lies on (a report, never a correction).
    var conflictNote: String? = nil
    /// Why there is no number (no line on the axis, a window outside it).
    var failure: String? = nil
    var id: Int { z }
}
