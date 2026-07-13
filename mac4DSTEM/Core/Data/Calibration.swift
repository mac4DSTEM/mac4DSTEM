import Foundation

/// Where the detector origin currently shown by the aperture came from.
/// This is deliberately separate from `hasFittedOrigin`: a py4DSTEM file can
/// provide a trustworthy fitted *mean* without carrying the per-position maps
/// needed by analyses that require descan correction.
enum OriginProvenance: Equatable, Sendable {
    /// Detector geometry only; no calibration has supplied an origin.
    case geometricDefault
    /// py4DSTEM qx0_mean/qy0_mean metadata, converted to the app's axis frame.
    case fileMean
    /// Full fitted per-position qx0/qy0 maps loaded from a py4DSTEM file.
    case fileMaps
    /// Origin mean restored from the mac4DSTEM session companion.
    case sessionMean
    /// Full origin maps restored from the mac4DSTEM session companion.
    case sessionMaps
    /// Mean of the per-position origin map fitted in this app.
    case fitted
    /// The user moved the aperture center after loading or calibration.
    case manual

    var displayName: String {
        switch self {
        case .geometricDefault: return "Geometric default (unfitted)"
        case .fileMean:         return "From file (qx0/qy0 mean)"
        case .fileMaps:         return "From file (fitted origin maps)"
        case .sessionMean:      return "From session sidecar (origin mean)"
        case .sessionMaps:      return "From session sidecar (origin maps)"
        case .fitted:           return "Fitted by calibration"
        case .manual:           return "Manual aperture center"
        }
    }
}

/// Per-scan-position position of the unscattered beam, in detector pixels.
struct OriginMaps: Sendable {
    let width: Int
    let height: Int

    /// Raw per-pattern measurement, when available. py4DSTEM files can carry
    /// fitted qx0/qy0 arrays without the corresponding measured arrays.
    let measuredX: [Float]?
    let measuredY: [Float]?

    /// Smooth fit of the measurement. Analyses use the fitted origin when available.
    var fittedX: [Float]
    var fittedY: [Float]

    /// RMS of measured minus fitted origins.
    var rmsResidual: Float? {
        guard let measuredX, let measuredY,
              measuredX.count == fittedX.count,
              measuredY.count == fittedY.count,
              !measuredX.isEmpty else { return nil }
        let count = measuredX.count

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

struct Calibration: Sendable {
    /// Provenance of the origin currently represented by the aperture center.
    var originProvenance: OriginProvenance = .geometricDefault

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

    /// Elliptical distortion in py4DSTEM's native (qx=row, qy=column) frame.
    var ellipseA: Double?
    var ellipseB: Double?
    var ellipseTheta: Double?

    var hasFittedOrigin: Bool { origin != nil }
    var hasRotation: Bool { rotationRad != nil }
    nonisolated var hasEllipse: Bool {
        guard let a = ellipseA, let b = ellipseB, let theta = ellipseTheta else { return false }
        return a.isFinite && b.isFinite && theta.isFinite && abs(a) > .leastNonzeroMagnitude
    }

    /// Mean fitted origin, suitable as a default detector center.
    var meanOrigin: (x: Float, y: Float)? {
        guard let origin, !origin.fittedX.isEmpty else { return nil }
        let count = Float(origin.fittedX.count)
        return (origin.fittedX.reduce(0, +) / count, origin.fittedY.reduce(0, +) / count)
    }

    /// Apply py4DSTEM `BraggVectors.cal._transform(..., ellipse=True)` to a
    /// detector offset. The axis swap is explicit: py4DSTEM [qx,qy] is this
    /// app's [dy,dx], and theta stays in that native py4DSTEM frame.
    nonisolated func ellipseCorrectedOffset(dx: Float, dy: Float) -> (x: Float, y: Float) {
        guard hasEllipse, let a = ellipseA, let b = ellipseB,
              let theta = ellipseTheta else { return (dx, dy) }
        let e = b / a
        let sine = sin(theta - .pi / 2)
        let cosine = cos(theta - .pi / 2)
        let t00 = e * sine * sine + cosine * cosine
        let t01 = sine * cosine * (1 - e)
        let t11 = sine * sine + e * cosine * cosine
        let qx = t00 * Double(dy) + t01 * Double(dx)
        let qy = t01 * Double(dy) + t11 * Double(dx)
        return (Float(qy), Float(qx))
    }
}

extension PixelOriginMaps {
    /// Convert py4DSTEM origin arrays to the app frame at the activation
    /// boundary. Real-space array order is unchanged; detector components swap
    /// because py4DSTEM qx is the first/row axis (app y), while qy is app x.
    nonisolated func appOriginMaps(width: Int, height: Int) -> OriginMaps? {
        guard shape == [height, width],
              fittedQX.count == width * height,
              fittedQY.count == width * height else { return nil }
        return OriginMaps(
            width: width, height: height,
            measuredX: measuredQY?.map(Float.init),
            measuredY: measuredQX?.map(Float.init),
            fittedX: fittedQY.map(Float.init),
            fittedY: fittedQX.map(Float.init)
        )
    }
}
