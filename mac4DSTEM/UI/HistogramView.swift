import SwiftUI

/// A reusable, self-contained intensity histogram of raw pixel values.
///
/// Bins are computed once when `pixels` changes (not on every redraw). A log-count
/// toggle (default ON) tames the heavy-tailed distributions typical of STEM images.
struct HistogramView: View {
    let pixels: [Float]
    /// Bump this when `pixels` changes (e.g. the result-image version counter)
    /// so recompute keys on a cheap Int instead of comparing the whole array.
    let version: Int

    private static let binCount = 96
    private static let barHeight: CGFloat = 100

    @State private var useLog = true
    @State private var bins: [Int] = []
    @State private var stats: (min: Float, max: Float, mean: Float)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Log counts", isOn: $useLog)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Canvas { context, size in
                draw(context: context, size: size)
            }
            .frame(height: Self.barHeight)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))

            if let stats {
                HStack {
                    readout("min", stats.min)
                    Spacer()
                    readout("mean", stats.mean)
                    Spacer()
                    readout("max", stats.max)
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .task(id: version) { recompute() }
    }

    private func readout(_ label: String, _ value: Float) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundStyle(.tertiary)
            Text(String(format: "%.3g", value))
        }
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
        guard pixels.count > 1,
              let lo = pixels.min(),
              let hi = pixels.max() else {
            bins = []
            stats = nil
            return
        }

        let mean = pixels.reduce(Float(0)) { $0 + $1 } / Float(pixels.count)
        stats = (lo, hi, mean)

        let span = hi - lo
        guard span > 0 else {
            bins = []  // Degenerate: min == max, draw returns flat line.
            return
        }

        var counts = [Int](repeating: 0, count: Self.binCount)
        let inverseSpan = Float(Self.binCount) / span
        for p in pixels {
            var idx = Int((p - lo) * inverseSpan)
            if idx >= Self.binCount { idx = Self.binCount - 1 }
            if idx < 0 { idx = 0 }
            counts[idx] += 1
        }
        bins = counts
    }
}
