import Foundation

/// Per-scan-position position of the unscattered beam, in detector pixels.
struct OriginMaps {
    let width: Int
    let height: Int

    /// Raw per-pattern measurement.
    let measuredX: [Float]
    let measuredY: [Float]

    /// Smooth fit of the measurement. Analyses use the fitted origin when available.
    var fittedX: [Float]
    var fittedY: [Float]

    /// RMS of measured minus fitted origins.
    var rmsResidual: Float {
        let count = measuredX.count
        guard count > 0 else { return 0 }

        var accumulator: Float = 0
        for index in 0..<count {
            let dx = measuredX[index] - fittedX[index]
            let dy = measuredY[index] - fittedY[index]
            accumulator += dx * dx + dy * dy
        }
        return (accumulator / Float(count)).squareRoot()
    }

    /// Fitted origins interleaved as [x0, y0, x1, y1, ...].
    var interleavedFitted: [Float] {
        var output = [Float](repeating: 0, count: fittedX.count * 2)
        for index in 0..<fittedX.count {
            output[2 * index] = fittedX[index]
            output[2 * index + 1] = fittedY[index]
        }
        return output
    }
}

struct Calibration {
    /// Radius of the central bright-field disk in detector pixels.
    var probeRadius: Float?

    /// Center and spread of the unscattered beam across the scan.
    var origin: OriginMaps?

    var qPixelSize: Double?
    var qPixelUnits: String?
    var rPixelSize: Double?
    var rPixelUnits: String?

    /// Relative rotation between scan and detector axes.
    var rotationRad: Float?
    var transposeQR: Bool?

    var hasFittedOrigin: Bool { origin != nil }
    var hasRotation: Bool { rotationRad != nil }

    /// Mean fitted origin, suitable as a default detector center.
    var meanOrigin: (x: Float, y: Float)? {
        guard let origin, !origin.fittedX.isEmpty else { return nil }
        let count = Float(origin.fittedX.count)
        return (origin.fittedX.reduce(0, +) / count, origin.fittedY.reduce(0, +) / count)
    }
}
