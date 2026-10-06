import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// A reusable, self-contained intensity histogram of raw pixel values.
///
/// Bins are computed once when `pixels` changes (not on every redraw). A log-count
/// toggle (default ON) tames the heavy-tailed distributions typical of STEM images.
///
/// When `rangeLo`/`rangeHi` bindings are provided, the histogram gains two
/// draggable handles that pick a contrast window (fractions of the intensity
/// range); the excluded tails are dimmed. The log toggle only scales the BAR
/// HEIGHTS, so the two interact freely — handle positions are intensity-axis
/// fractions either way.
struct HistogramView: View {
    let pixels: [Float]
    /// Bump this when `pixels` changes (e.g. the result-image version counter)
    /// so recompute keys on a cheap Int instead of comparing the whole array.
    let version: Int
    /// Optional contrast-window bindings in [0, 1] (fraction of the range).
    var rangeLo: Binding<Float>? = nil
    var rangeHi: Binding<Float>? = nil
    /// The value a pixel of 1.0 stands for (counts at the tile's maximum, say):
    /// the readouts show `value * scale` and the window edges are typed in the
    /// same units. 1 keeps today's readouts.
    var scale: Float = 1
    /// The readouts' unit ("counts"); empty shows none.
    var unit: String = ""

    private static let binCount = 96
    private static let barHeight: CGFloat = 100

    // Owner decision (R26): linear counts by default — log counts on
    // startup would be unusual; log stays one toggle away.
    @State private var useLog = false
    @State private var bins: [Int] = []
    @State private var stats: (min: Float, max: Float, mean: Float)?
    /// Which window edge is being typed (true = low), nil when none.
    @State private var editingLow: Bool?
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Label leading, switch at the trailing edge — the
                // inspector's one alignment rule.
                Text("Log y-axis")
                Spacer()
                Toggle("Log y-axis", isOn: $useLog)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if let lo = rangeLo, let hi = rangeHi,
                   lo.wrappedValue > 0 || hi.wrappedValue < 1 {
                    Button("Reset range") {
                        lo.wrappedValue = 0
                        hi.wrappedValue = 1
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                }
            }

            Canvas { context, size in
                draw(context: context, size: size)
            }
            .frame(height: Self.barHeight)
            .overlay {
                if let lo = rangeLo, let hi = rangeHi {
                    rangeOverlay(lo: lo, hi: hi)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Intensity histogram")
            .accessibilityValue(histogramAccessibilityValue)
            .accessibilityRepresentation {
                if let lo = rangeLo, let hi = rangeHi {
                    VStack {
                        Slider(value: lo, in: 0...max(0, hi.wrappedValue - 0.01))
                            .accessibilityLabel("Lower contrast limit")
                            .accessibilityValue("\(Int(lo.wrappedValue * 100)) percent")
                        Slider(value: hi, in: min(1, lo.wrappedValue + 0.01)...1)
                            .accessibilityLabel("Upper contrast limit")
                            .accessibilityValue("\(Int(hi.wrappedValue * 100)) percent")
                    }
                } else {
                    Text(histogramAccessibilityValue)
                }
            }

            if let stats {
                HStack {
                    edgeReadout("min", isLow: true, stats: stats)
                    Spacer()
                    readout("mean", stats.mean)
                    Spacer()
                    edgeReadout("max", isLow: false, stats: stats)
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .task(id: version) { recompute() }
    }

    /// Which handle the current drag is moving (nil between drags).
    @State private var draggingHiHandle: Bool?

    private var histogramAccessibilityValue: String {
        guard let stats else { return "No finite pixel statistics" }
        return String(format: "minimum %.3g, mean %.3g, maximum %.3g", stats.min, stats.mean, stats.max)
    }

    /// Dimmed excluded tails + two handle markers. Instead of tiny per-handle
    /// hit areas (which clip at the row edges, making the hi handle at x = w
    /// ungrabbable), the WHOLE histogram takes the drag and moves whichever
    /// handle is nearest to the touch point.
    private func rangeOverlay(lo: Binding<Float>, hi: Binding<Float>) -> some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = geo.size.height
            let loX = CGFloat(lo.wrappedValue) * w
            let hiX = CGFloat(hi.wrappedValue) * w

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: max(loX, 0), height: h)
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: max(w - hiX, 0), height: h)
                    .offset(x: hiX)
                handleBar(x: min(max(loX, 1), w - 1), height: h)
                handleBar(x: min(max(hiX, 1), w - 1), height: h)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = Float(min(max(value.location.x / w, 0), 1))
                        if draggingHiHandle == nil {
                            draggingHiHandle =
                                abs(f - hi.wrappedValue) < abs(f - lo.wrappedValue)
                        }
                        if draggingHiHandle == true {
                            hi.wrappedValue = max(f, lo.wrappedValue + 0.01)
                        } else {
                            lo.wrappedValue = min(f, hi.wrappedValue - 0.01)
                        }
                    }
                    .onEnded { _ in draggingHiHandle = nil }
            )
        }
    }

    private func handleBar(x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: height)
            .overlay(alignment: .top) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 9)
                    .offset(y: -4)
            }
            .position(x: x, y: height / 2)
            .allowsHitTesting(false)
    }

    private func readout(_ label: String, _ value: Float) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundStyle(.tertiary)
            Text(HistogramReadout.text(value: value, scale: scale, unit: unit))
        }
    }

    /// The min / max readout. With range bindings and a real span it shows the
    /// contrast window's edge — the data's own min / max while the window is
    /// full — and a click turns it into a numeric field in the same units
    /// (Return or blur commits, Escape cancels).
    @ViewBuilder
    private func edgeReadout(_ label: String, isLow: Bool,
                             stats: (min: Float, max: Float, mean: Float)) -> some View {
        if let lo = rangeLo, let hi = rangeHi, stats.max > stats.min {
            let own = isLow ? lo : hi
            let other = isLow ? hi : lo
            let edge = HistogramReadout.edge(fraction: own.wrappedValue, dataMin: stats.min, dataMax: stats.max)
            VStack(spacing: 1) {
                Text(label).foregroundStyle(.tertiary)
                if editingLow == isLow {
                    edgeField(edge: edge, own: own, other: other, isLow: isLow, stats: stats)
                } else {
                    Button {
                        editingLow = isLow
                    } label: {
                        Text(HistogramReadout.text(value: edge, scale: scale, unit: unit))
                    }
                    .buttonStyle(.plain)
                    .help("Click to type the window's \(isLow ? "low" : "high") value")
                    .accessibilityIdentifier(isLow ? "histogram.min" : "histogram.max")
                }
            }
        } else {
            readout(label, isLow ? stats.min : stats.max)
        }
    }

    private func edgeField(edge: Float, own: Binding<Float>, other: Binding<Float>, isLow: Bool,
                           stats: (min: Float, max: Float, mean: Float)) -> some View {
        let format: FloatingPointFormatStyle<Float> = scale > 1
            ? .number.precision(.fractionLength(0))
            : .number.precision(.significantDigits(1...6))
        return NumberEntryField(title: isLow ? "Window low" : "Window high",
                                value: edge * HistogramReadout.safeScale(scale), format: format) { typed in
            if let typed {
                own.wrappedValue = HistogramReadout.commit(
                    typed: typed, scale: scale, other: other.wrappedValue, isLow: isLow,
                    dataMin: stats.min, dataMax: stats.max)
            }
            editingLow = nil
        }
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: LayoutPolicy.numericFieldWidth)
        .focused($editFocused)
        .onAppear { editFocused = true }
        .onChange(of: editFocused) { _, focused in if !focused { editingLow = nil } }
        .onKeyPress(.escape) { editingLow = nil; return .handled }
        .accessibilityIdentifier(isLow ? "histogram.min.field" : "histogram.max.field")
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        guard !bins.isEmpty else { return }
        let maxCount = bins.max() ?? 0
        guard maxCount > 0 else {
            // Flat line for degenerate (all-equal) data.
            let y = size.height - 1
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                with: .color(.secondary),
                lineWidth: 1
            )
            return
        }

        let scale = useLog ? log1p(Double(maxCount)) : Double(maxCount)
        let barWidth = size.width / CGFloat(bins.count)

        for (i, count) in bins.enumerated() {
            guard count > 0 else { continue }
            let value = useLog ? log1p(Double(count)) : Double(count)
            let h = CGFloat(value / scale) * size.height
            let rect = CGRect(
                x: CGFloat(i) * barWidth,
                y: size.height - h,
                width: max(barWidth - 0.5, 0.5),
                height: h
            )
            context.fill(Path(rect), with: .color(.accentColor))
        }
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
        stats = (lo, hi, mean)

        let span = hi - lo
        guard span > 0 else {
            bins = []  // Degenerate: min == max, draw returns flat line.
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
    static func safeScale(_ scale: Float) -> Float { scale > 0 ? scale : 1 }

    /// `value * scale` with `unit`: grouped whole numbers once a 1.0 stands
    /// for more than 1 (counts), "%.3g" as ever at scale 1 (or below).
    static func text(value: Float, scale: Float, unit: String) -> String {
        let number: String
        if scale > 1 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = "\u{202F}"   // a narrow no-break space: "4 120"
            formatter.groupingSize = 3
            number = formatter.string(from: NSNumber(value: Double(value * scale).rounded())) ?? "0"
        } else {
            number = String(format: "%.3g", value * safeScale(scale))
        }
        return unit.isEmpty ? number : number + " " + unit
    }

    /// The pixel value at a window fraction of the data range.
    static func edge(fraction: Float, dataMin: Float, dataMax: Float) -> Float {
        dataMin + fraction * (dataMax - dataMin)
    }

    /// The window fraction a typed value (in `scale` units) stands for, clamped
    /// to 0...1 and kept 0.01 clear of the other edge. `dataMin`/`dataMax`
    /// default to 0...1 (pixels already normalised to the scale).
    static func commit(typed: Float, scale: Float, other: Float, isLow: Bool,
                       dataMin: Float = 0, dataMax: Float = 1) -> Float {
        let span = dataMax - dataMin
        guard span > 0 else { return isLow ? 0 : 1 }
        let fraction = min(max((typed / safeScale(scale) - dataMin) / span, 0), 1)
        return isLow ? min(fraction, max(other - 0.01, 0))
                     : max(fraction, min(other + 0.01, 1))
    }
}
