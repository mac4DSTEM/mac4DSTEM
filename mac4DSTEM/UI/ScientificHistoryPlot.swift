import SwiftUI
import DSTEMCore
import DSTEMSession

/// Compact interactive plot for retained analysis histories. Dragging selects
/// an existing finite sample; gaps remain visible for invalid samples.
struct ScientificHistoryPlot: View {
    let title: String
    let values: [Float]
    var scale: ScientificSeriesScale = .linear
    @State private var selectedIndex: Int?

    private var geometry: ScientificSeriesGeometry {
        ScientificSeriesGeometry.make(values: values, scale: scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(selectionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Canvas { context, size in
                    let inset = CGRect(x: 3, y: 3, width: max(0, size.width - 6),
                                       height: max(0, size.height - 6))
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = inset.maxY - inset.height * fraction
                        context.stroke(Path { path in
                            path.move(to: CGPoint(x: inset.minX, y: y))
                            path.addLine(to: CGPoint(x: inset.maxX, y: y))
                        }, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                    }
                    for segment in geometry.segments where !segment.isEmpty {
                        let path = Path { path in
                            for (offset, point) in segment.enumerated() {
                                let mapped = CGPoint(
                                    x: inset.minX + inset.width * point.x,
                                    y: inset.maxY - inset.height * point.y
                                )
                                offset == 0 ? path.move(to: mapped) : path.addLine(to: mapped)
                            }
                        }
                        context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
                    }
                    if let point = geometry.point(at: effectiveSelection) {
                        let center = CGPoint(x: inset.minX + inset.width * point.x,
                                             y: inset.maxY - inset.height * point.y)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3,
                                                            width: 6, height: 6)),
                                     with: .color(.accentColor))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let x = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                    selectedIndex = geometry.nearestIndex(toUnitX: x)
                })
            }
            .frame(height: 58)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(selectionLabel)
            .accessibilityHint("Adjust to inspect finite samples")
            .accessibilityAdjustableAction { direction in
                let indices = geometry.points.map(\.index)
                guard !indices.isEmpty else { return }
                let current = effectiveSelection ?? indices.last!
                let position = indices.firstIndex(of: current) ?? indices.count - 1
                switch direction {
                case .increment: selectedIndex = indices[min(indices.count - 1, position + 1)]
                case .decrement: selectedIndex = indices[max(0, position - 1)]
                @unknown default: break
                }
            }
            HStack {
                Text(scale == .logarithmic ? "log₁₀ scale" : "linear scale")
                Spacer()
                Text("\(geometry.points.count) samples")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .onChange(of: values) { _, _ in selectedIndex = nil }
    }

    private var effectiveSelection: Int? { selectedIndex ?? geometry.points.last?.index }

    private var selectionLabel: String {
        guard let point = geometry.point(at: effectiveSelection) else { return "No finite samples" }
        return "#\(point.index)  \(String(format: "%.5g", point.value))"
    }
}
