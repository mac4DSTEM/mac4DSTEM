//
//  VariantPalette.swift
//  Role: the colours of the variant map (design 2026-10-22 §3.3): a needle direction is one of three Okabe-Ito hues (sky blue, bluish green,
//        vermillion: the phase map's colour-blind-safe set), a variant is its direction's hue in four lightness steps, and the number in
//        the glyph or the table says which, so lightness is never the only cue. Pure values; the views turn them into colours.
//

import Foundation

nonisolated enum VariantPalette {
    typealias RGB = (r: Double, g: Double, b: Double)

    static let directionHues: [RGB] = [(0.34, 0.71, 0.91), (0.00, 0.62, 0.45), (0.84, 0.37, 0.00), (0.80, 0.47, 0.65)]   // the fourth, reddish purple, is T1's fourth <111> family
    /// Lightness of a variant's rank within its direction: toward white (+) or black (-) by this fraction.
    static let steps: [Double] = [0, 0.2, 0.4, -0.2]
    /// Neither a direction nor a variant: the unassigned objects.
    static let unassigned: RGB = (0.55, 0.55, 0.55)

    /// Variant `variant` (1...12, the kit's order)'s place among the variants of its direction: `directions[v - 1]` is each variant's direction.
    static func rank(variant: Int, directions: [Int]) -> Int {
        guard directions.indices.contains(variant - 1) else { return 0 }
        let d = directions[variant - 1]
        return directions[..<(variant - 1)].filter { $0 == d }.count
    }

    static func rgb(direction: Int, rank: Int = 0) -> RGB {
        guard directionHues.indices.contains(direction) else { return unassigned }
        let hue = directionHues[direction]
        let t = steps[min(max(rank, 0), steps.count - 1)]
        func shade(_ c: Double) -> Double { t >= 0 ? c + (1 - c) * t : c * (1 + t) }
        return (shade(hue.r), shade(hue.g), shade(hue.b))
    }

    /// A glyph's colour for a scheme; nil for the phase scheme (the phase colour is the report's).
    static func rgb(scheme: PrecipitateColourBy, direction: Int?, variant: Int?, directions: [Int]) -> RGB? {
        switch scheme {
        case .phase:
            return nil
        case .direction:
            return direction.map { rgb(direction: $0) } ?? unassigned
        case .variant:
            guard let direction, let variant else { return unassigned }
            return rgb(direction: direction, rank: rank(variant: variant, directions: directions))
        }
    }
}

/// What the glyphs are coloured by.
nonisolated enum PrecipitateColourBy: String, CaseIterable, Sendable, Identifiable {
    case phase = "Phase", direction = "Direction", variant = "Variant"
    var id: String { rawValue }
}
