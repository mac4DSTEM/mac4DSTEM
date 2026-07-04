//
//  DiffractionPattern.swift
//  Role: Value types for image data + their display normalization.
//
//  `FloatImage`  — a generic 2D float image (real-space results live here).
//  `DiffractionPattern` — a single [Qy, Qx] CBED pattern, with the log-scale
//                         normalizer that CBED viewing essentially requires.
//
//  Normalization maps raw float values into [0, 1] for the GPU colormap step.
//

import Foundation

// MARK: - FloatImage

struct FloatImage {
    let width: Int
    let height: Int
    let pixels: [Float]   // row-major, length == width * height

    var minMax: (Float, Float) {
        guard let lo = pixels.min(), let hi = pixels.max() else { return (0, 1) }
        return (lo, hi)
    }

    /// Linearly normalize to [0,1]. If `symmetric`, the scale is centered on
    /// zero (so a diverging colormap puts 0 at its midpoint — used for strain).
    func normalized(symmetric: Bool = false) -> [Float] {
        let (lo, hi) = minMax
        if symmetric {
            let m = max(abs(lo), abs(hi))
            guard m > 0 else { return pixels.map { _ in 0.5 } }
            return pixels.map { 0.5 + 0.5 * ($0 / m) }   // [-m, m] → [0,1]
        } else {
            let span = hi - lo
            guard span > 0 else { return pixels.map { _ in 0.0 } }
            return pixels.map { ($0 - lo) / span }
        }
    }
}

// MARK: - RGBAImage

/// A packed RGBA8 image for results that are inherently colored (DPC color
/// wheel). Rendered by MetalImageView's RGBA path — no colormap applied.
struct RGBAImage {
    let width: Int
    let height: Int
    let rgba: [UInt8]     // row-major, length == width * height * 4
}

// MARK: - DiffractionPattern

struct DiffractionPattern {
    let qy: Int
    let qx: Int
    let pixels: [Float]   // length == qy * qx

    var minMax: (Float, Float) {
        guard let lo = pixels.min(), let hi = pixels.max() else { return (0, 1) }
        return (lo, hi)
    }

    /// Normalize for display. CBED patterns span many orders of magnitude, so
    /// `useLog` (the default in the UI) applies log10(1 + I) before scaling.
    func normalized(useLog: Bool) -> [Float] {
        if useLog {
            let lg = pixels.map { Float(log10(1.0 + Double(max($0, 0)))) }
            return FloatImage(width: qx, height: qy, pixels: lg).normalized()
        } else {
            return FloatImage(width: qx, height: qy, pixels: pixels).normalized()
        }
    }

    var asFloatImage: FloatImage { FloatImage(width: qx, height: qy, pixels: pixels) }
}
