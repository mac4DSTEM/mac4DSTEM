import Foundation

enum ColormapKind: String, CaseIterable, Identifiable {
    case viridis
    case inferno
    case gray
    case rdbu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .viridis: return "Viridis"
        case .inferno: return "Inferno"
        case .gray: return "Gray"
        case .rdbu: return "RdBu (diverging)"
        }
    }

    /// Diverging maps are meant for symmetric data such as strain or DPC.
    var isDiverging: Bool { self == .rdbu }
}

enum Colormaps {
    /// Returns RGBA bytes for the requested colormap.
    static func lutRGBA(_ kind: ColormapKind, count: Int = 256) -> [UInt8] {
        let stops = anchors(for: kind)
        var output = [UInt8](repeating: 255, count: count * 4)

        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let (r, g, b) = sample(stops, at: t)
            output[index * 4 + 0] = UInt8((r * 255).rounded().clamped(0, 255))
            output[index * 4 + 1] = UInt8((g * 255).rounded().clamped(0, 255))
            output[index * 4 + 2] = UInt8((b * 255).rounded().clamped(0, 255))
            output[index * 4 + 3] = 255
        }

        return output
    }

    private static func sample(
        _ stops: [(Double, Double, Double, Double)],
        at t: Double
    ) -> (Double, Double, Double) {
        if t <= stops.first!.0 {
            let stop = stops.first!
            return (stop.1, stop.2, stop.3)
        }

        if t >= stops.last!.0 {
            let stop = stops.last!
            return (stop.1, stop.2, stop.3)
        }

        for index in 1..<stops.count {
            let start = stops[index - 1]
            let end = stops[index]

            if t <= end.0 {
                let fraction = (t - start.0) / (end.0 - start.0)
                return (
                    start.1 + (end.1 - start.1) * fraction,
                    start.2 + (end.2 - start.2) * fraction,
                    start.3 + (end.3 - start.3) * fraction
                )
            }
        }

        return (1, 1, 1)
    }

    private static func anchors(for kind: ColormapKind) -> [(Double, Double, Double, Double)] {
        switch kind {
        case .gray:
            return [(0, 0, 0, 0), (1, 1, 1, 1)]
        case .viridis:
            return [
                (0.00, 0.267, 0.005, 0.329),
                (0.25, 0.254, 0.265, 0.530),
                (0.50, 0.128, 0.567, 0.551),
                (0.75, 0.369, 0.789, 0.383),
                (1.00, 0.993, 0.906, 0.144)
            ]
        case .inferno:
            return [
                (0.00, 0.001, 0.000, 0.014),
                (0.25, 0.258, 0.039, 0.406),
                (0.50, 0.578, 0.148, 0.404),
                (0.75, 0.865, 0.316, 0.226),
                (0.90, 0.988, 0.645, 0.040),
                (1.00, 0.988, 0.998, 0.645)
            ]
        case .rdbu:
            return [
                (0.00, 0.129, 0.400, 0.674),
                (0.50, 0.969, 0.969, 0.969),
                (1.00, 0.698, 0.094, 0.168)
            ]
        }
    }
}

private extension Double {
    func clamped(_ lowerBound: Double, _ upperBound: Double) -> Double {
        Swift.min(Swift.max(self, lowerBound), upperBound)
    }
}
