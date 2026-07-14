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

    /// Sentinel for invalid (masked / non-finite) pixels in display-normalized
    /// space. Valid pixels normalize into [0,1]; renderers (the Metal fragment
    /// shader and the PNG export colormap) show negative values as an explicit
    /// masked color instead of a colormap entry.
    nonisolated static let invalidDisplayValue: Float = -1

    /// Linearly normalize to [0, 1]. If symmetric, the scale is centered on
    /// zero. Non-finite pixels map to `invalidDisplayValue`, never to a valid
    /// color — "no data" must stay distinguishable from any real value.
    nonisolated func normalized(symmetric: Bool = false) -> [Float] {
        let invalid = Self.invalidDisplayValue
        let (lo, hi) = minMax
        if symmetric {
            let magnitude = max(abs(lo), abs(hi))
            guard magnitude > 0 else {
                return pixels.map { $0.isFinite ? 0.5 : invalid }
            }
            return pixels.map { $0.isFinite ? 0.5 + 0.5 * ($0 / magnitude) : invalid }
        }

        let span = hi - lo
        guard span > 0 else { return pixels.map { $0.isFinite ? 0.0 : invalid } }
        return pixels.map { $0.isFinite ? ($0 - lo) / span : invalid }
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
