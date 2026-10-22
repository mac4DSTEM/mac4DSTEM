//
//  QuantMaps.swift
//  Role: the wt% / at% / mass-thickness maps of the Spectroscopy room (ROADMAP task 4). The numbers are one kit call,
//        `EDXQuantification.quantifyMaps` (SpectroKit 0.8.1); this file holds only the app's side: the method mapping, the
//        navigation mask, the tile snapshots and the words. No numerics.
//
//  Since SpectroKit 0.8.2 the pooled fit's k (`PooledQuantification.kFactors`, computed or typed), each row's line energy and the
//  file's take-off angle are public, so the maps use the same k as the pooled number and the absorption correction when a thickness
//  is typed and the file states its geometry.
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

nonisolated struct QuantMapsPlan: Sendable, Equatable {
    var setup: EDXQuantificationSetup
    /// What the tile footers say about the absorption correction.
    var absorptionNote: String
}

nonisolated enum QuantMapsSetup {
    /// The kit setup for the maps, from the very k-factors the pooled fit used (`PooledQuantification.kFactors`, computed or typed),
    /// in the order of `elements` (the quantified elements in tile order). Absorption is on when the method asks for it, a thickness
    /// is typed and the file's geometry gives a take-off angle (`EDXQuantification.takeOffDegrees`); otherwise the maps run without
    /// it and the note says why.
    static func plan(method: QuantificationMethod, elements: [String], fit: PooledQuantification?,
                     metadata: SpectrumImageMetadata) -> Result<QuantMapsPlan, QuantMapsRefusal> {
        var k: [Double] = []
        if let fit, let factors = fit.kFactors {
            for e in elements {
                guard let f = factors.first(where: { $0.element == e }) else {
                    return .failure(QuantMapsRefusal(text: "The fit has no k for \(e): quantify it in the pooled fit first."))
                }
                k.append(f.k)
            }
        } else if method.kFactorSource == .typed {
            for e in elements {
                guard let t = method.typedK.first(where: { $0.element == e }), t.k > 0, t.k.isFinite else {
                    return .failure(QuantMapsRefusal(text: "No typed k for \(e): type it in Quantification."))
                }
                k.append(t.k)
            }
        } else {
            return .failure(QuantMapsRefusal(text: "wt% and at% maps use the k of the pooled fit: run Quantify first and give it at least two elements."))
        }
        var absorption: EDXAbsorptionSetting?
        var note = "no absorption correction"
        if method.absorptionCorrection {
            if method.thickness == nil {
                note = "no absorption correction (no thickness typed)"
            } else {
                do {
                    let angle = try EDXQuantification.takeOffDegrees(metadata: metadata)
                    let energies = elements.map { e in fit?.rows.first { $0.element == e }?.lineEnergyKeV }
                    if energies.allSatisfy({ $0 != nil }) {
                        absorption = EDXAbsorptionSetting(takeOffDegrees: angle, lineEnergiesKeV: energies.compactMap { $0 })
                        note = String(format: "absorption corrected, one take-off angle %.1f\u{00B0} (the pooled fit averages the detector segments)", locale: .autoupdatingCurrent, angle)
                    } else {
                        note = "no absorption correction (a line energy is unknown)"
                    }
                } catch {
                    note = "no absorption correction (" + ((error as? LocalizedError)?.errorDescription ?? "\(error)") + ")"
                }
            }
        }
        return .success(QuantMapsPlan(
            setup: EDXQuantificationSetup(elements: elements,
                                          method: .cliffLorimer(kFactors: k, thicknessNm: method.thickness?.nanometres),
                                          absorption: absorption),
            absorptionNote: note))
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

    static func summary(_ maps: EDXQuantificationMaps, masked: Int = 0, absorptionNote: String = "no absorption correction") -> QuantMapsSummary {
        QuantMapsSummary(failedPixels: maps.failures.reduce(0) { $0 + ($1 == nil ? 0 : 1) }, maskedPixels: masked,
                         validation: maps.validation, absorptionNote: absorptionNote)
    }

    /// The percent map as the picture filters it: a failed pixel (NaN) counts as 0 (it must not spread into its neighbours), then the
    /// display kernel. Display only: the raw percent is what the tile keeps and the export writes.
    static func filtered(percent: [Double], width: Int, height: Int, smoothing: MapSmoothing) -> [Double] {
        let clean = percent.map { $0.isFinite ? $0 : 0 }
        return smoothing.apply(clean, width: width, height: height)
    }

    /// The picture of a composition map: `filtered`, then 0...1 of its own maximum (a failed pixel is 0); `scale` is that maximum
    /// (the percent at value 1), 1 for an empty map.
    static func picture(percent: [Double], width: Int, height: Int, smoothing: MapSmoothing) -> (values: [Float], scale: Float) {
        let shown = smoothing == .none ? percent : filtered(percent: percent, width: width, height: height, smoothing: smoothing)
        let finiteMax = shown.filter(\.isFinite).max() ?? 0
        let scale = Float(max(finiteMax, 0))
        let values = shown.map { v -> Float in
            guard v.isFinite, scale > 0 else { return 0 }
            return min(max(Float(v) / scale, 0), 1)
        }
        return (values, scale > 0 ? scale : 1)
    }

    /// A composition tile: 0...1 of the picture's own maximum, a failed pixel (NaN) drawn as 0, the raw percent kept for the export
    /// and the readout (`counts` is never filtered).
    static func tile(z: Int, percent: [Double], width: Int, height: Int, summary: QuantMapsSummary, mode: MapMode,
                     smoothing: MapSmoothing = .none) -> MapTile {
        let shown = picture(percent: percent, width: width, height: height, smoothing: smoothing)
        var t = MapTile(z: z, width: width, height: height, values: shown.values, counts: percent, scale: shown.scale)
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
