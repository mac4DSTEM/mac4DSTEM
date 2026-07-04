//
//  Colormaps.swift
//  Role: CPU-side colormap definitions. Produces 256-entry RGBA LUTs that are
//        uploaded to a 1D Metal texture and sampled by colormapFragment.
//
//  The scientific colormaps (viridis, inferno) here are anchor-interpolated
//  approximations — visually correct and good enough to read structure. For
//  publication-exact ramps, paste matplotlib's 256×3 tables into `anchors`
//  as 256 stops; the rest of the code is unchanged.
//

import Foundation

// MARK: - ColormapKind

enum ColormapKind: String, CaseIterable, Identifiable {
    case viridis, inferno, gray, rdbu
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .viridis: return "Viridis"
        case .inferno: return "Inferno"
        case .gray:    return "Gray"
        case .rdbu:    return "RdBu (diverging)"
        }
    }
    /// Diverging maps are meant for symmetric data (e.g. strain, DPC).
    var isDiverging: Bool { self == .rdbu }
}

// MARK: - LUT generation

enum Colormaps {

    /// Returns 256 RGBA bytes (1024 total) for the given colormap.
    static func lutRGBA(_ kind: ColormapKind, count: Int = 256) -> [UInt8] {
        let stops = anchors(for: kind)
        var out = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let (r, g, b) = sample(stops, at: t)
            out[i * 4 + 0] = UInt8((r * 255).rounded().clamped(0, 255))
            out[i * 4 + 1] = UInt8((g * 255).rounded().clamped(0, 255))
            out[i * 4 + 2] = UInt8((b * 255).rounded().clamped(0, 255))
            out[i * 4 + 3] = 255
        }
        return out
    }

    /// Linear interpolation across (position, r, g, b) anchor stops in [0,1].
    private static func sample(_ stops: [(Double, Double, Double, Double)], at t: Double) -> (Double, Double, Double) {
        if t <= stops.first!.0 { let s = stops.first!; return (s.1, s.2, s.3) }
        if t >= stops.last!.0  { let s = stops.last!;  return (s.1, s.2, s.3) }
        for i in 1..<stops.count {
            let a = stops[i - 1], b = stops[i]
            if t <= b.0 {
                let f = (t - a.0) / (b.0 - a.0)
                return (a.1 + (b.1 - a.1) * f,
                        a.2 + (b.2 - a.2) * f,
                        a.3 + (b.3 - a.3) * f)
            }
        }
        return (1, 1, 1)
    }

    private static func anchors(for kind: ColormapKind) -> [(Double, Double, Double, Double)] {
        switch kind {
        case .gray:
            return [(0, 0, 0, 0), (1, 1, 1, 1)]
        case .viridis:
            return [(0.00, 0.267, 0.005, 0.329),
                    (0.25, 0.254, 0.265, 0.530),
                    (0.50, 0.128, 0.567, 0.551),
                    (0.75, 0.369, 0.789, 0.383),
                    (1.00, 0.993, 0.906, 0.144)]
        case .inferno:
            return [(0.00, 0.001, 0.000, 0.014),
                    (0.25, 0.258, 0.039, 0.406),
                    (0.50, 0.578, 0.148, 0.404),
                    (0.75, 0.865, 0.316, 0.226),
                    (0.90, 0.988, 0.645, 0.040),
                    (1.00, 0.988, 0.998, 0.645)]
        case .rdbu:
            // Diverging: blue (low) → white (mid) → red (high).
            return [(0.00, 0.129, 0.400, 0.674),
                    (0.50, 0.969, 0.969, 0.969),
                    (1.00, 0.698, 0.094, 0.168)]
        }
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
