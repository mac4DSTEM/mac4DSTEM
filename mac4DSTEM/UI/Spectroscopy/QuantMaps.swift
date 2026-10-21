//
//  QuantMaps.swift
//  Role: the wt% / at% / mass-thickness maps of the Spectroscopy room (ROADMAP task 4). The numbers are one kit call,
//        `EDXQuantification.quantifyMaps` (SpectroKit 0.8.1); this file holds only the app's side: the method mapping, the
//        navigation mask, the tile snapshots and the words. No numerics.
//
//  Gaps in the kit's public API (noted, not worked around in the app):
//   * a computed k set (`KFactorSource.computed`) is `package` (`PooledQuantification.kSet`), so the maps take typed k only;
//   * the line energies and the Velox take-off angle are not public either, so the maps run without the absorption
//     correction and say so on the tile.
//

import Foundation
import SpectroCore
import SpectroEDX

/// Why the maps cannot be made, in the person's words.
nonisolated struct QuantMapsRefusal: Error, Equatable, Sendable, LocalizedError {
    var text: String
    var errorDescription: String? { text }
}

/// Everything one maps pass needs besides the net-count maps; built on the main actor, run off it.
nonisolated struct QuantMapsRequest: Sendable, Equatable {
    var setup: EDXQuantificationSetup
    var rows: Int
    var columns: Int
    /// Pixels whose summed net counts over the quantified elements fall below this are left out (composition 0). 0: no mask.
    var minimumCounts: Double
    var methodHash: String
}

/// The tile footer's facts for one element: the picture, the pixels the kit could not answer and the badge.
nonisolated struct QuantMapsSummary: Sendable, Equatable {
    var failedPixels: Int
    var maskedPixels: Int
    var validation: String
    var absorptionNote: String
}

nonisolated enum QuantMapsSetup {
    /// The method's typed k, in the order of `elements` (the quantified elements in tile order), as the kit's setup.
    static func setup(method: QuantificationMethod, elements: [String]) -> Result<EDXQuantificationSetup, QuantMapsRefusal> {
        guard method.kFactorSource == .typed else {
            return .failure(QuantMapsRefusal(text: "wt% and at% maps need typed k-factors for now: choose \u{201C}typed\u{201D} in Quantification. (The kit does not yet expose its computed set.)"))
        }
        var k: [Double] = []
        for e in elements {
            guard let t = method.typedK.first(where: { $0.element == e }), t.k > 0, t.k.isFinite else {
                return .failure(QuantMapsRefusal(text: "No typed k for \(e): type it in Quantification."))
            }
            k.append(t.k)
        }
        return .success(EDXQuantificationSetup(elements: elements,
                                               method: .cliffLorimer(kFactors: k, thicknessNm: method.thickness?.nanometres)))
    }
}

nonisolated enum QuantMapsPass {
    /// The kit call over the net-count maps (`netMaps[e][pixel]`, e in `request.setup.elements` order).
    static func run(_ request: QuantMapsRequest, netMaps: [[Double]]) throws -> EDXQuantificationMaps {
        let mask = mask(request, netMaps: netMaps)
        return try EDXQuantification.quantifyMaps(intensityMaps: netMaps, rows: request.rows, columns: request.columns,
                                                  setup: request.setup, navigationMask: mask)
    }

    /// The app's mask rule: summed net counts of the quantified elements below the threshold. nil when off.
    static func mask(_ request: QuantMapsRequest, netMaps: [[Double]]) -> [Bool]? {
        guard request.minimumCounts > 0 else { return nil }
        let pixels = request.rows * request.columns
        guard netMaps.allSatisfy({ $0.count == pixels }) else { return nil }
        return (0..<pixels).map { p in netMaps.reduce(0) { $0 + $1[p] } < request.minimumCounts }
    }

    static func maskedCount(_ request: QuantMapsRequest, netMaps: [[Double]]) -> Int {
        mask(request, netMaps: netMaps)?.reduce(0) { $0 + ($1 ? 1 : 0) } ?? 0
    }

    /// The comment lines a maps CSV carries (the lineage facts: method hash, mask rule, failed pixels, badge).
    static func provenance(_ s: QuantMapsSummary, methodHash: String, minimumCounts: Double) -> [String] {
        ["# quantification maps: EDXQuantification.quantifyMaps (SpectroKit), Cliff-Lorimer with typed k, \(s.absorptionNote)",
         "# method hash: \(methodHash)",
         "# mask rule: " + (minimumCounts > 0 ? "summed net counts < \(minimumCounts) left out (\(s.maskedPixels) px)" : "none"),
         "# failed pixels: \(s.failedPixels) (empty cell); per-pixel, no \u{03C3}",
         "# validation: \(s.validation)"]
    }

    /// The percent map of element `index` in `mode` (nil for a mode that is not a composition).
    static func percentMap(_ maps: EDXQuantificationMaps, index: Int, mode: MapMode) -> [Double]? {
        switch mode {
        case .weight: maps.weightPercent[index]
        case .atomic: maps.atomicPercent[index]
        default: nil
        }
    }

    static func summary(_ maps: EDXQuantificationMaps, masked: Int = 0) -> QuantMapsSummary {
        QuantMapsSummary(failedPixels: maps.failures.reduce(0) { $0 + ($1 == nil ? 0 : 1) }, maskedPixels: masked,
                         validation: maps.validation, absorptionNote: "no absorption correction")
    }

    /// A composition tile: 0...1 of the tile's own maximum, a failed pixel (NaN) drawn as 0, the raw percent kept for the export.
    static func tile(z: Int, percent: [Double], width: Int, height: Int, summary: QuantMapsSummary, mode: MapMode) -> MapTile {
        let finiteMax = percent.filter(\.isFinite).max() ?? 0
        let scale = Float(max(finiteMax, 0))
        let values = percent.map { v -> Float in
            guard v.isFinite, scale > 0 else { return 0 }
            return min(max(Float(v) / scale, 0), 1)
        }
        var t = MapTile(z: z, width: width, height: height, values: values, counts: percent, scale: scale > 0 ? scale : 1)
        t.footer = footerText(summary, mode: mode)
        return t
    }

    /// "3 failed px · per-pixel, no σ; pool a region for a σ · no absorption correction · validation: none"
    static func footerText(_ s: QuantMapsSummary, mode: MapMode) -> String {
        var parts: [String] = []
        if s.failedPixels > 0 { parts.append("\(s.failedPixels) failed px") }
        if s.maskedPixels > 0 { parts.append("\(s.maskedPixels) masked px") }
        parts.append("per-pixel, no \u{03C3}; pool a region for a \u{03C3}")
        parts.append(s.absorptionNote)
        parts.append("validation: \(s.validation)")
        return parts.joined(separator: " \u{00B7} ")
    }
}
