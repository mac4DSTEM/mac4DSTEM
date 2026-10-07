import Foundation
import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

// The Spectroscopy room's pure half (v5.0 WP2 lane V, ADR 054/055): everything the
// views decide that is not drawing — element roles, the "Auto ID never drops manual
// picks" rule, the narrow-layout switch, the spectrum's axes, the residual strip.
// No SwiftUI, no loading, no compute of a scientific number; the numbers shown come
// from the session (lane R) through `SpectroscopyRoomModel`. Unit-tested in
// `SpectroscopyViewModelTests`.

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
    /// The proposer's own bar, net / L_D (1 = just detectable); 0 when unknown.
    var significance: Double = 0
}

/// An energy band of a window a net map uses: the signal window of a line, or one of its two background windows.
nonisolated struct WindowBand: Equatable, Sendable, Identifiable {
    enum Kind: Sendable { case signal, background }
    var id: String                   // "Al_Ka.signal", "Al_Ka.left"
    var elementZ: Int?
    var label: String                // "Al Kα"
    var range: ClosedRange<Double>   // keV
    var kind: Kind
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
    /// The lines the person checked per element (ids like "Al_Ka", "Al_Kb"), all of the family in `families`; absent = the
    /// family's alpha line. They are what the maps sum and the spectrum marks; the fit takes whole families either way.
    private(set) var lines: [Int: Set<String>] = [:]

    init(roles: [Int: ElementRole] = [:], manual: Set<Int> = [], suggestions: [ElementSuggestion] = []) {
        self.roles = roles
        self.manual = manual
        self.suggestions = suggestions
    }

    /// No lines below Z = 5 at an EDX window; and none for an element the X-ray line table carries without lines
    /// (Hs, Og, Np, Pu, Am ...): a pick there could never fit or map anything (drive 2026-10-07).
    static func unavailableReason(z: Int) -> String? {
        if z <= 4 { return "No usable X-ray line at this detector window" }
        guard PeriodicLayout.symbols.indices.contains(z - 1) else { return nil }
        return XRayLines.lines(of: PeriodicLayout.symbol(z)).isEmpty ? "No X-ray line in the table" : nil
    }

    func role(_ z: Int) -> ElementRole { roles[z] ?? .off }
    /// The family a map and the markers use: the person's, else Velox's rule (`ElementWindows.defaultFamily`: K up to Ru, L above).
    func family(_ z: Int) -> LineFamily {
        families[z] ?? LineFamily(rawValue: ElementWindows.defaultFamily(of: PeriodicLayout.symbol(z)).rawValue) ?? .K
    }

    /// The lines a map and the markers use for this element, as the menu shows them: the checked ones, else the family's alpha line.
    func checkedLines(_ z: Int) -> Set<String> {
        if let l = lines[z], !l.isEmpty { return l }
        return ["\(PeriodicLayout.symbol(z))_\(family(z).rawValue)a"]
    }

    /// True when the person chose a family or lines for this element (so its tile and its provenance say which).
    func hasChosenLines(_ z: Int) -> Bool { families[z] != nil || !(lines[z] ?? []).isEmpty }

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

    /// The family row: that family's alpha line, the checked lines of any family dropped.
    mutating func setFamily(_ z: Int, _ family: LineFamily) { families[z] = family; lines[z] = nil }

    /// A line item of the Lines menu: check or uncheck it. Lines of one family at a time: a line of another family starts a new
    /// set in its family. Unchecking the last line (or checking back to the alpha alone) is the family's alpha line, which is
    /// what no checked line means.
    mutating func toggleLine(_ z: Int, _ id: String) {
        guard let line = XRayLines.line(id), line.element == PeriodicLayout.symbol(z),
              let f = LineFamily(rawValue: line.family.rawValue) else { return }
        var set: Set<String> = f == family(z) ? checkedLines(z) : []
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        families[z] = f.rawValue == ElementWindows.defaultFamily(of: line.element).rawValue ? nil : f
        let alpha = "\(line.element)_\(f.rawValue)a"
        lines[z] = (set.isEmpty || set == [alpha]) ? nil : set
    }

    /// "Default lines": the rule's family and its alpha line.
    mutating func resetLines(_ z: Int) { families[z] = nil; lines[z] = nil }

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

/// The periodic table's symbols and the folded places (the grid itself is `PeriodicTableGrid`): period 7 and the f-block
/// stay folded into one "La\u{2013}Lu \u{00B7} Ac\u{2013}Lr" disclosure.
nonisolated enum PeriodicLayout {
    static let symbols: [String] = ("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr "
        + "Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu "
        + "Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr "
        + "Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og").split(separator: " ").map(String.init)

    static func symbol(_ z: Int) -> String { symbols[z - 1] }
    static func z(of symbol: String) -> Int? { symbols.firstIndex(of: symbol).map { $0 + 1 } }

    /// The folded places: La to Lu, then period 7 (Fr to Og).
    static let folded: [Int] = Array(57...71) + Array(87...118)
}

// MARK: - Spectrum axes

nonisolated struct SpectrumLayers: Equatable, Sendable {
    var spectrum = true, background = true, model = true, residual = true
    /// The pinned regions' comparison curves (drawn faint, `pinOpacity`).
    var pins = true
    static let pinOpacity = 0.6
    /// Spec 2 D-6: linear by default (the owner); the Show menu's toggle switches to log.
    var log = false
    /// Counts per pooled pixel instead of counts (the region's size falls out of a comparison).
    var perPixel = false
    /// The line and background windows the net maps use, as faint bands.
    var windows = false
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
    /// Spec 2 D-6: the manual y stretch. 1 is auto; above 1 the drawn top is the auto top divided by it (peaks grow). A vertical
    /// drag in the y-axis gutter sets it; it is not part of the energy window, so `clamp()` and the zoom leave it alone.
    var yScale = 1.0
    static let yScaleRange: ClosedRange<Double> = 1...50
    /// Points of upward drag that double the stretch.
    static let yScalePointsPerDoubling = 60.0

    init(domain: ClosedRange<Double>, minimumSpan: Double = 0.02) {
        self.domain = domain; self.minimumSpan = minimumSpan; lo = domain.lowerBound; hi = domain.upperBound
    }

    /// The y stretch after a vertical drag of `dragDY` points (screen y: negative is up) that began at `start`: cumulative from the
    /// drag's start, clamped to `yScaleRange`.
    static func yScale(from start: Double, dragDY: Double) -> Double {
        let v = start * pow(2, -dragDY / yScalePointsPerDoubling)
        guard v.isFinite else { return start }
        return min(max(v, yScaleRange.lowerBound), yScaleRange.upperBound)
    }
    /// The drawn top of the y axis for an automatic top (counts in linear, the top decade's value in log), never below `floor`.
    func scaledTop(_ auto: Double, floor: Double = 0) -> Double { max(auto / yScale, floor) }

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

    /// A tick's text. A value that rounds to zero is "0", never "-0" (the energy offset leaves a tick at -1e-16).
    static func label(_ v: Double, step: Double) -> String {
        let s = String(format: "%.\(decimals(forStep: step))f", v)
        return s.hasPrefix("-") && !s.contains(where: { $0 != "-" && $0 != "0" && $0 != "." }) ? String(s.dropFirst()) : s
    }

    /// Estimated text width of a 10 pt axis label, points (digits and the point are about 5.6 pt).
    static func labelWidth(_ text: String) -> CGFloat { CGFloat(text.count) * 5.6 + 2 }

    /// The x-axis labels to draw. The unit is the axis title in the left gutter, right-aligned to `unitTrailing` (so it never
    /// meets the last label); a tick label whose box would reach it is left out.
    static func xLabels(ticks: [Double], x: (Double) -> CGFloat, step: Double, unit: String, unitTrailing: CGFloat) -> (labels: [(text: String, x: CGFloat)], unit: (text: String, trailing: CGFloat)) {
        let unitLeft = unitTrailing - labelWidth(unit)
        let kept = ticks.compactMap { e -> (text: String, x: CGFloat)? in
            let t = label(e, step: step), cx = x(e)
            return cx - labelWidth(t) / 2 > unitTrailing + 2 || cx + labelWidth(t) / 2 < unitLeft - 2 ? (t, cx) : nil
        }
        return (kept, (unit, unitTrailing))
    }

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
    /// `unit` is what one raw count is in the plotted unit (1 for counts, 1/pixels per pixel): the floor of the axis.
    static func log(minPositive: Double, maximum: Double, unit: Double = 1) -> (lo: Double, hi: Double) {
        let lo = minPositive.isFinite && minPositive > 0 ? max(unit, pow(10, floor(log10(minPositive)))) : unit
        let top = maximum.isFinite && maximum > 0 ? maximum * 1.05 : 10 * unit
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
    /// Which frame edge a clipped residual sits on: +1 top, -1 bottom, 0 not clipped. The strip draws a small tick there.
    static func clipSide(_ v: Double) -> Int { isClipped(v) ? (v > 0 ? 1 : -1) : 0 }
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

/// What the cursor is over: the channel's energy and counts, the nearest line marker within its own FWHM
/// (`LineMarker.fwhm`, or `lineTolerance` keV when the marker carries none), and the tabulated lines the energy could be
/// (`candidates`, Velox's cursor identification, sheet row 3a).
nonisolated enum SpectrumHover {
    static let lineTolerance = 0.1
    /// The Si Kα energy an escape peak lies below its parent line (the Si(Li)/SDD crystal's escape), keV.
    static let siEscapeKeV = 1.740
    /// How many names the readout shows after the counts.
    static let namesShown = 3

    /// A line, a pile-up sum or a Si escape that lies within one detector FWHM of the cursor.
    struct Candidate: Equatable, Sendable {
        enum Kind: Sendable { case line, sum, escape }
        var z: Int
        var label: String            // "Ar Kα", "Al Kα+Kα sum", "Cu Kα esc"
        var energy: Double           // keV
        var kind: Kind
    }

    struct Sample: Equatable {
        var energy: Double
        var counts: Double
        var line: String?
        var candidates: [Candidate] = []
    }

    /// The α lines of the table (Ka, La, Ma), H and He excluded (their "lines" are ionisation energies).
    private static let alphaLines: [XRayLine] = XRayLines.all.filter {
        ($0.name == "Ka" || $0.name == "La" || $0.name == "Ma") && !XRayLines.notRealLines.contains($0.element)
    }

    /// Every α line within ± 1 FWHM of `e` (the width law at the line's own energy, 0.1 keV where the law has none), closest
    /// first; plus, for the `listed` elements' α lines, the pile-up sum (2 E) and the Si escape (E − 1.740 keV) when within the
    /// same tolerance. A listed element's own line comes before every other; sums and escapes follow by distance with the rest.
    static func candidates(at e: Double, resolutionMnKaEV: Double, listed: [Int]) -> [Candidate] {
        func tolerance(_ at: Double) -> Double { XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: at) ?? lineTolerance }
        let listedSet = Set(listed)
        var out: [Candidate] = []
        for l in alphaLines {
            let greek = String(l.name.prefix(1)) + "\u{03B1}"
            if abs(l.energy - e) <= tolerance(l.energy) {
                out.append(Candidate(z: l.atomicNumber, label: "\(l.element) \(greek)", energy: l.energy, kind: .line))
            }
            guard listedSet.contains(l.atomicNumber) else { continue }
            let sum = 2 * l.energy
            if abs(sum - e) <= tolerance(sum) {
                out.append(Candidate(z: l.atomicNumber, label: "\(l.element) \(greek)+\(greek) sum", energy: sum, kind: .sum))
            }
            let esc = l.energy - siEscapeKeV
            if esc > 0, abs(esc - e) <= tolerance(esc) {
                out.append(Candidate(z: l.atomicNumber, label: "\(l.element) \(greek) esc", energy: esc, kind: .escape))
            }
        }
        func rank(_ c: Candidate) -> Int { c.kind == .line && listedSet.contains(c.z) ? 0 : 1 }
        return out.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            let d0 = abs($0.energy - e), d1 = abs($1.energy - e)
            return d0 != d1 ? d0 < d1 : $0.z < $1.z
        }
    }

    static func sample(series: SpectrumSeries, viewport: SpectrumViewport, fraction f: Double, markers: [LineMarker],
                       resolutionMnKaEV: Double = ElementWindows.defaultResolutionMnKaEV, listed: [Int] = []) -> Sample? {
        guard series.count > 0, f >= 0, f <= 1, series.energyStep > 0 else { return nil }
        let e = viewport.energy(atFraction: f)
        let ch = min(series.count - 1, max(0, Int(((e - series.energyStart) / series.energyStep).rounded())))
        let near = markers.filter { $0.kind != .edge }.min { abs($0.energy - e) < abs($1.energy - e) }
        // The cut-off is the marker's own FWHM when it has one (a Mg Kα marker 60 eV wide, a Cu Kα one 160 eV).
        let line = near.flatMap { abs($0.energy - e) <= ($0.fwhm ?? lineTolerance) ? $0.label : nil }
        return Sample(energy: series.energy(ch), counts: series.data[ch], line: line,
                      candidates: candidates(at: e, resolutionMnKaEV: resolutionMnKaEV, listed: listed))
    }

    /// The range marker (⌥-drag, sheet row 13a): the counts of the channels whose energy lies in `from...to` (either order),
    /// and their share of the series' total. A series with no counts has fraction 0.
    static func range(series: SpectrumSeries, from: Double, to: Double) -> (counts: Double, fraction: Double) {
        guard series.count > 0, series.energyStep > 0 else { return (0, 0) }
        let lo = min(from, to), hi = max(from, to)
        let i0 = max(0, Int(ceil((lo - series.energyStart) / series.energyStep - 1e-9)))
        let i1 = min(series.count - 1, Int(floor((hi - series.energyStart) / series.energyStep + 1e-9)))
        let counts = i1 >= i0 ? series.data[i0...i1].reduce(0, +) : 0
        let total = series.data.reduce(0, +)
        return (counts, total > 0 ? counts / total : 0)
    }
}

/// Counts per pooled pixel (Show › Per pixel): a region's size falls out of a comparison. Pure; the drawing divides curves and
/// readouts by `divisor`. Fits, the residual and every export stay in counts.
nonisolated enum SpectrumScale {
    /// 1 (no scaling) unless the toggle is on and the pooled pixel count is known.
    static func divisor(perPixel: Bool, pixels: Int) -> Double { perPixel && pixels > 0 ? Double(pixels) : 1 }
    /// `v` per pixel; unchanged when the pixel count is unknown (0), never a division by zero.
    static func perPixel(_ v: [Double], pixels: Int) -> [Double] { pixels > 0 ? v.map { $0 / Double(pixels) } : v }
}

/// How a window band of the net maps is drawn (Show \u{203A} Windows): faint, so the spectrum stays the picture. The signal window
/// takes 8 % of its element's colour, a background window 5 % grey; no labels.
nonisolated enum WindowBandStyle {
    static func opacity(_ kind: WindowBand.Kind) -> Double { kind == .signal ? 0.08 : 0.05 }
}

/// The plot's readout text: the cursor's, and the range marker's. Numbers in the person's locale (a decimal comma in German),
/// pixel counts grouped like the spectrum header's (a thin space).
nonisolated enum SpectrumReadout {
    static func energy(_ e: Double, decimals: Int = 3, locale: Locale = .current) -> String {
        e.formatted(.number.precision(.fractionLength(decimals)).grouping(.never).locale(locale))
    }

    /// 1380 -> "1 380" (thin grouping; `ResultFormat.counts` is this). Lives here, not in QuantPanelView, so the
    /// autoid-velox-check harness (the `readers` group plus this file) compiles without the view.
    static func counts(_ v: Double) -> String { grouped(v, locale: Locale(identifier: "en_US")) }

    /// Digits grouped with a narrow no-break space (U+202F), in `locale`'s digits, decimal mark and minus sign. FormatStyle has no
    /// grouping-separator option, so the locale's own thousands mark is swapped for U+202F (pinned by `FormatStyleMigrationTests`).
    static func grouped(_ v: Double, fraction: ClosedRange<Int> = 0...0, locale: Locale) -> String {
        v.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
            .replacingOccurrences(of: locale.groupingSeparator ?? ",", with: "\u{202F}")
    }

    /// Counts per pixel: three decimals below 10 ("0,027"), one below 100, none above.
    static func perPixel(_ v: Double, locale: Locale = .current) -> String {
        let d = abs(v) < 10 ? 3 : (abs(v) < 100 ? 1 : 0)
        return v.formatted(.number.precision(.fractionLength(d)).grouping(.never).locale(locale))
    }

    /// "2,957 keV", "1 380 counts" (or "0,027 counts/px" with `pixels` > 0 and `perPixel`), then the names: the marker's own line
    /// first (today's nearest-listed rule), then the candidates, at most `SpectrumHover.namesShown` in all.
    static func parts(_ s: SpectrumHover.Sample, divisor: Double = 1, locale: Locale = .current) -> [String] {
        var out = [energy(s.energy, locale: locale) + " keV",
                   divisor == 1 ? counts(s.counts) + " counts" : perPixel(s.counts / divisor, locale: locale) + " counts/px"]
        var names: [String] = []
        if let l = s.line { names.append(l) }
        for c in s.candidates where !names.contains(c.label) { names.append(c.label) }
        out += names.prefix(SpectrumHover.namesShown)
        return out
    }

    /// "1,40–1,60 keV · 61 230 counts · 15,4 % of the region".
    static func rangeText(from: Double, to: Double, counts c: Double, fraction: Double, divisor: Double = 1, locale: Locale = .current) -> String {
        let lo = min(from, to), hi = max(from, to)
        let share = (fraction * 100).formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
        return [energy(lo, decimals: 2, locale: locale) + "\u{2013}" + energy(hi, decimals: 2, locale: locale) + " keV",
                divisor == 1 ? counts(c) + " counts" : perPixel(c / divisor, locale: locale) + " counts/px",
                share + " % of the region"].joined(separator: " \u{00B7} ")
    }

    /// The counts axis title: "counts / 20 eV", or "counts / px / 20 eV" per pixel.
    static func yAxisTitle(channelEV: Int, perPixel: Bool) -> String { "counts / \(perPixel ? "px / " : "")\(channelEV) eV" }

    static let separator = " \u{00B7} "
    /// The readout box's widest text, points.
    static let widthCap: CGFloat = 320

    /// The parts joined, the trailing ones dropped (and "…" added) until the text is no wider than `cap` by `width`; the first
    /// part (the energy) is never dropped.
    static func fit(_ parts: [String], cap: CGFloat = widthCap, width: (String) -> CGFloat) -> String {
        var kept = parts
        while true {
            let text = kept.joined(separator: separator) + (kept.count < parts.count ? "\u{2026}" : "")
            if kept.count <= 1 || width(text) <= cap { return text }
            kept.removeLast()
        }
    }
}

nonisolated struct SpectrumSeries: Equatable, Sendable {
    var energyStart: Double          // keV of channel 0
    var energyStep: Double           // keV per channel
    var data: [Double]
    var background: [Double]
    var model: [Double]
    var overlay: [Double]?           // e.g. the matrix, normalised to Al Kα
    /// The channels the fit covered (R3): the model, background and residual are drawn there only. nil = every channel.
    var fitChannels: Range<Int>? = nil

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
    enum Kind: Sendable { case line, edge }   // edge: the Al K edge, grey and dotted
    var label: String                // "Mg Kα", "Al K edge"
    var energy: Double
    var elementZ: Int?
    var kind: Kind = .line
    /// The detector's line width here, keV. The hover's nearest-line cut-off is this one value (nil: `SpectrumHover.lineTolerance`).
    var fwhm: Double? = nil
    /// Which label survives a collision: higher first (the chosen K\u{03B1}-type line of a quantified element beats a satellite or a fit-only element).
    var priority = 0
    var id: String { label }
}

/// Where the line-marker names go. Names are staggered into a few rows; one that still collides in every row is left out
/// (its marker line stays) and reported, so the plot can say which. Pure: the plot only draws what this returns.
nonisolated enum MarkerLabelLayout {
    struct Placement: Equatable {
        var label: String
        var row: Int
        var x: CGFloat              // the marker line's x
        var leading: Bool           // text starts right of the line (false: it ends left of it, at the frame's edge)
    }
    struct Result: Equatable { var placed: [Placement]; var left: [String] }

    static let rows = 3
    static let gap: CGFloat = 3

    /// Estimated text width of an 11 pt semibold label.
    static func width(_ label: String) -> CGFloat { CGFloat(label.count) * 6.6 + 4 }

    /// The markers whose energy lies inside the viewport: only these get a line and a name.
    static func inView(_ markers: [LineMarker], lo: Double, hi: Double) -> [LineMarker] {
        markers.filter { $0.energy >= lo && $0.energy <= hi }
    }

    static func place(_ markers: [(label: String, x: CGFloat, priority: Int)], minX: CGFloat, maxX: CGFloat) -> Result {
        var occupied = [[ClosedRange<CGFloat>]](repeating: [], count: rows)
        var placed: [Placement] = [], left: [String] = []
        let order = markers.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.x < $1.x }
        for m in order {
            let w = width(m.label)
            let leading = m.x + 2 + w <= maxX
            let span = leading ? (m.x + 2)...(m.x + 2 + w) : max(minX, m.x - 2 - w)...(m.x - 2)
            if let r = (0..<rows).first(where: { row in !occupied[row].contains { $0.lowerBound < span.upperBound + gap && span.lowerBound < $0.upperBound + gap } }) {
                occupied[r].append(span)
                placed.append(Placement(label: m.label, row: r, x: m.x, leading: leading))
            } else { left.append(m.label) }
        }
        return Result(placed: placed, left: left)
    }
}

// MARK: - Results

nonisolated enum AbundanceUnit: String, CaseIterable, Sendable { case atomic = "at%", weight = "wt%" }
/// What the maps show (the grid header's switch). `integrated` is the signal window's sum, `netCounts` the same less its
/// background windows. at% and wt% are computed on pooled regions only (ADR 054 item 3, a pooled fit has a σ and a pixel's
/// counts have none worth a composition), so the two are listed but never offered for the maps.
nonisolated enum MapMode: String, CaseIterable, Sendable {
    case integrated = "int", netCounts = "net", weight = "wt%", atomic = "at%"
    var isAvailable: Bool { self == .integrated || self == .netCounts }
    var units: String { self == .integrated ? "integrated counts" : (self == .netCounts ? "net counts" : rawValue) }
}
/// The region tools in the grid header: a rectangle, or a polygon closed by a click on its first vertex.
nonisolated enum DrawTool: String, CaseIterable, Sendable {
    case rectangle, ellipse = "Ellipse", polygon
    var symbol: String {
        switch self {
        case .rectangle: "rectangle.dashed"
        case .ellipse: "oval"
        case .polygon: "pentagon"
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
    /// The weight-percent form of `sigmaTerms` (R3); nil takes `sigmaTerms`.
    var sigmaTermsWeight: String? = nil
    /// False when no at% / wt% was computed for this row (no k source, absorption-independent): the cells show "—".
    var hasAbundance = true
    /// False when the row has no k-free ratio (a failed line).
    var hasKFree = true
    var id: Int { z }
}
