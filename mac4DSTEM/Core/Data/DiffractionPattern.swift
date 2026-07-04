import Foundation

struct FloatImage {
    let width: Int
    let height: Int
    let pixels: [Float]

    var minMax: (Float, Float) {
        guard let lo = pixels.min(), let hi = pixels.max() else { return (0, 1) }
        return (lo, hi)
    }

    /// Linearly normalize to [0, 1]. If symmetric, the scale is centered on zero.
    func normalized(symmetric: Bool = false) -> [Float] {
        let (lo, hi) = minMax
        if symmetric {
            let magnitude = max(abs(lo), abs(hi))
            guard magnitude > 0 else { return pixels.map { _ in 0.5 } }
            return pixels.map { 0.5 + 0.5 * ($0 / magnitude) }
        }

        let span = hi - lo
        guard span > 0 else { return pixels.map { _ in 0.0 } }
        return pixels.map { ($0 - lo) / span }
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

    var minMax: (Float, Float) {
        guard let lo = pixels.min(), let hi = pixels.max() else { return (0, 1) }
        return (lo, hi)
    }

    /// Normalize for display. CBED patterns span many orders of magnitude, so log display is useful.
    func normalized(useLog: Bool) -> [Float] {
        if useLog {
            let logPixels = pixels.map { Float(log10(1.0 + Double(max($0, 0)))) }
            return FloatImage(width: qx, height: qy, pixels: logPixels).normalized()
        }

        return FloatImage(width: qx, height: qy, pixels: pixels).normalized()
    }

    var asFloatImage: FloatImage { FloatImage(width: qx, height: qy, pixels: pixels) }
}
