import ShellControls
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The app's histogram of raw pixel values: the BINNING and the readout wording; the drawing, the contrast-window handles and the
/// min / mean / max footer are ShellControls' `HistogramChart` (suite task 8, MacEMUI).
///
/// Bins are computed once when `pixels` changes (not on every redraw: `.task(id: version)`). With `rangeLo`/`rangeHi` the chart gains
/// its two draggable handles (fractions of the intensity range); without them the window is the full range and the handles do nothing.
struct HistogramView: View {
    let pixels: [Float]
    /// Bump this when `pixels` changes (e.g. the result-image version counter)
    /// so recompute keys on a cheap Int instead of comparing the whole array.
    let version: Int
    /// Optional contrast-window bindings in [0, 1] (fraction of the range).
    var rangeLo: Binding<Float>? = nil
    var rangeHi: Binding<Float>? = nil
    /// The value a pixel of 1.0 stands for (counts at the tile's maximum, say): the readouts show `value * scale` and the window edges are
    /// typed in the same units. 1 keeps today's readouts.
    var scale: Float = 1
    /// The readouts' unit ("counts"); empty shows none.
    var unit: String = ""

    private static let binCount = 96

    @State private var bins: [Int] = []
    @State private var stats: HistogramStatistics?
    /// Stand-ins for a call with no window bindings: the full range, never written.
    @State private var fullLo: Float = 0
    @State private var fullHi: Float = 1

    var body: some View {
        HistogramChart(
            counts: bins, statistics: stats,
            rangeLo: rangeLo ?? $fullLo, rangeHi: rangeHi ?? $fullHi,
            scale: scale,
            // Counts (scale above 1) keep this app's grouped, unit-carrying text; plain pixel values take the chart's own 4-digit text.
            valueText: scale > 1 || !unit.isEmpty ? { [scale, unit] in HistogramReadout.text(value: $0, scale: scale, unit: unit) } : nil)
            .padding(.vertical, 2)
            .task(id: version) { recompute() }
    }

    private func recompute() {
        // Non-finite pixels (masked "no data" positions) carry no intensity;
        // including them would poison the stats and trap in Int(NaN) below.
        let finite = pixels.filter(\.isFinite)
        guard finite.count > 1,
              let lo = finite.min(),
              let hi = finite.max() else {
            bins = []
            stats = nil
            return
        }

        let mean = finite.reduce(Float(0)) { $0 + $1 } / Float(finite.count)
        stats = HistogramStatistics(minimum: lo, maximum: hi, mean: mean)

        let span = hi - lo
        guard span > 0 else {
            bins = []  // Degenerate: min == max, the chart draws nothing.
            return
        }

        var counts = [Int](repeating: 0, count: Self.binCount)
        let inverseSpan = Float(Self.binCount) / span
        for p in finite {
            var idx = Int((p - lo) * inverseSpan)
            if idx >= Self.binCount { idx = Self.binCount - 1 }
            if idx < 0 { idx = 0 }
            counts[idx] += 1
        }
        bins = counts
    }
}

/// The histogram readouts' text and the window edge a typed value maps to —
/// pure, so the rules are testable without a view.
enum HistogramReadout {
    /// A non-positive scale is meaningless; 1 stands in.
    static func safeScale(_ scale: Float) -> Float { HistogramWindowRules.safeScale(scale) }

    /// `value * scale` with `unit`: grouped whole numbers once a 1.0 stands
    /// for more than 1 (counts), "%.3g" as ever at scale 1 (or below).
    static func text(value: Float, scale: Float, unit: String, locale: Locale = .current) -> String {
        let number: String
        if scale > 1 {
            number = ResultFormat.grouped(Double(value * scale).rounded(), locale: locale)   // "4 120" (narrow no-break space)
        } else {
            number = CalibrationUnitConversion.localizedDecimal(String(format: "%.3g", value * safeScale(scale)), locale: locale)
        }
        return unit.isEmpty ? number : number + " " + unit
    }

    /// The pixel value at a window fraction of the data range (ShellControls' rule).
    static func edge(fraction: Float, dataMin: Float, dataMax: Float) -> Float {
        HistogramWindowRules.edge(fraction: fraction, dataMin: dataMin, dataMax: dataMax)
    }

    /// The window fraction a typed value (in `scale` units) stands for, clamped to 0...1 and kept 0.01 clear of the other edge.
    static func commit(typed: Float, scale: Float, other: Float, isLow: Bool,
                       dataMin: Float = 0, dataMax: Float = 1) -> Float {
        HistogramWindowRules.commit(typed: typed, scale: scale, other: other, isLow: isLow, dataMin: dataMin, dataMax: dataMax)
    }
}
