import Foundation

/// Min/max over the FINITE values only — a single NaN/Inf pixel (dead-pixel
/// correction, division artifacts) must not blank the display scaling.
nonisolated func finiteMinMax(_ pixels: [Float]) -> (Float, Float) {
    var lo = Float.greatestFiniteMagnitude
    var hi = -Float.greatestFiniteMagnitude
    for v in pixels where v.isFinite {
        if v < lo { lo = v }
        if v > hi { hi = v }
    }
    guard lo <= hi else { return (0, 1) }
    return (lo, hi)
}

struct FloatImage {
    let width: Int
    let height: Int
    let pixels: [Float]

    nonisolated var minMax: (Float, Float) { finiteMinMax(pixels) }

    /// Linearly normalize to [0, 1]. If symmetric, the scale is centered on
    /// zero. Non-finite pixels map to the low end (0, or 0.5 for symmetric).
    nonisolated func normalized(symmetric: Bool = false) -> [Float] {
        let (lo, hi) = minMax
        if symmetric {
            let magnitude = max(abs(lo), abs(hi))
            guard magnitude > 0 else { return pixels.map { _ in 0.5 } }
            return pixels.map { $0.isFinite ? 0.5 + 0.5 * ($0 / magnitude) : 0.5 }
        }

        let span = hi - lo
        guard span > 0 else { return pixels.map { _ in 0.0 } }
        return pixels.map { $0.isFinite ? ($0 - lo) / span : 0 }
    }
}

/// A packed RGBA8 image for results that are inherently colored.
struct RGBAImage {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}

struct DiffractionPattern {
    let qy: Int
    let qx: Int
    let pixels: [Float]

    nonisolated var minMax: (Float, Float) { finiteMinMax(pixels) }

    /// Normalize for display. CBED patterns span many orders of magnitude, so log display is useful.
    nonisolated func normalized(useLog: Bool) -> [Float] {
        FloatImage(width: qx, height: qy,
                   pixels: contrastPixels(useLog: useLog)).normalized()
    }

    /// Values along the CBED contrast/histogram axis before [0,1]
    /// normalization. Log mode uses log10(1 + max(I, 0)).
    nonisolated func contrastPixels(useLog: Bool) -> [Float] {
        guard useLog else { return pixels }
        return pixels.map {
            $0.isFinite ? Float(log10(1.0 + Double(max($0, 0)))) : 0
        }
    }

    nonisolated var asFloatImage: FloatImage { FloatImage(width: qx, height: qy, pixels: pixels) }
}
