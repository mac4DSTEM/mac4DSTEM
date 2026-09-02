import SwiftUI
import simd
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Compact sampled m-3m inverse-pole-figure key. The map and legend share the
/// same color function, keeping the on-screen key aligned with exported pixels.
struct CubicIPFLegendView: View {
    var body: some View {
        VStack(spacing: 1) {
            Canvas { context, size in
                let left = SIMD2<Double>(4, Double(size.height - 3))
                let right = SIMD2<Double>(Double(size.width - 4), Double(size.height - 3))
                let top = SIMD2<Double>(Double(size.width / 2), 3)
                let steps = 36
                let radius = max(1.4, Double(size.width) / Double(steps) * 0.65)
                // Triangle corners as named constants: the one-expression blend
                // exceeds Xcode 26.6's type-checker budget (CI run #1) even
                // though Xcode 27 accepts it.
                let dir001 = SIMD3<Double>(0, 0, 1)
                let dir101 = simd_normalize(SIMD3<Double>(1, 0, 1))
                let dir111 = simd_normalize(SIMD3<Double>(1, 1, 1))
                for topIndex in 0...steps {
                    for rightIndex in 0...(steps - topIndex) {
                        let wt = Double(topIndex) / Double(steps)
                        let wr = Double(rightIndex) / Double(steps)
                        let wl = 1 - wt - wr
                        let point = left * wl + right * wr + top * wt
                        let blended = dir001 * wl + dir101 * wr + dir111 * wt
                        let direction = simd_normalize(blended)
                        let rgb = CubicOrientationSymmetry.ipfColor(direction: direction)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(
                            red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)
                        )))
                    }
                }
            }
            .frame(width: 116, height: 62)
            HStack {
                Text("001")
                Spacer()
                Text("111")
                Spacer()
                Text("101")
            }
            .font(.caption2.monospacedDigit())
            .frame(width: 132)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cubic inverse pole figure color key: 001 red, 101 green, 111 blue")
    }
}

/// Native 6/mmm key sharing the production hexagonal color function.
struct HexagonalIPFLegendView: View {
    var body: some View {
        VStack(spacing: 1) {
            Canvas { context, size in
                let left = SIMD2<Double>(4, Double(size.height - 3))
                let right = SIMD2<Double>(Double(size.width - 4), Double(size.height - 3))
                let top = SIMD2<Double>(Double(size.width / 2), 3)
                let steps = 36
                let radius = max(1.4, Double(size.width) / Double(steps) * 0.65)
                for topIndex in 0...steps {
                    for rightIndex in 0...(steps - topIndex) {
                        let wt = Double(topIndex) / Double(steps)
                        let wr = Double(rightIndex) / Double(steps)
                        let wl = 1 - wt - wr
                        let point = left * wl + right * wr + top * wt
                        let direction = simd_normalize(
                            SIMD3(0.0, 0.0, 1.0) * wl
                                + SIMD3(1.0, 0.0, 0.0) * wr
                                + SIMD3(cos(.pi / 6), sin(.pi / 6), 0.0) * wt
                        )
                        let rgb = HexagonalOrientationSymmetry.ipfColor(direction: direction)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(
                            red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)
                        )))
                    }
                }
            }
            .frame(width: 116, height: 62)
            HStack {
                Text("0001")
                Spacer()
                Text("11-20")
                Spacer()
                Text("10-10")
            }
            .font(.caption2.monospacedDigit())
            .frame(width: 142)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hexagonal inverse pole figure color key: 0001 red, 10-10 green, 11-20 blue")
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
