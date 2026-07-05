import Foundation

/// Orientation as Bunge-convention Euler angles in radians.
struct EulerAngles: Equatable, Hashable {
    var phi1: Float
    var Phi: Float
    var phi2: Float

    static let zero = EulerAngles(phi1: 0, Phi: 0, phi2: 0)

    var degrees: (Float, Float, Float) {
        let scale = Float(180.0 / Double.pi)
        return (phi1 * scale, Phi * scale, phi2 * scale)
    }
}

struct OrientationResult: Equatable {
    /// Index into the template library (zone axis) for the best match.
    var templateIndex: Int
    var euler: EulerAngles
    /// Best in-plane rotation angle (radians), from azimuthal correlation.
    var inPlaneAngle: Float = 0
    /// Best normalized cross-correlation score.
    var score: Float
    /// Second-best score, used for reliability.
    var secondScore: Float
    var phaseID: Int

    /// EBSD-style reliability. Higher values indicate a clearer best match.
    var reliability: Float {
        guard score > 0 else { return 0 }
        let value = 1 - (secondScore / score)
        return max(0, min(1, value))
    }

    static let empty = OrientationResult(
        templateIndex: -1,
        euler: .zero,
        inPlaneAngle: 0,
        score: 0,
        secondScore: 0,
        phaseID: -1
    )
}

struct OrientationMap {
    let width: Int
    let height: Int
    var results: [OrientationResult]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.results = Array(repeating: .empty, count: width * height)
    }

    subscript(x: Int, y: Int) -> OrientationResult {
        get { results[y * width + x] }
        set { results[y * width + x] = newValue }
    }

    var reliabilityImage: FloatImage {
        FloatImage(width: width, height: height, pixels: results.map { $0.reliability })
    }

    var scoreImage: FloatImage {
        FloatImage(width: width, height: height, pixels: results.map { $0.score })
    }

    /// In-plane rotation angle at each position, in [0, 1) (radians / 2π) —
    /// suitable for a cyclic colormap.
    var inPlaneAngleImage: FloatImage {
        let twoPi = Float(2 * Double.pi)
        return FloatImage(width: width, height: height,
                          pixels: results.map { $0.inPlaneAngle / twoPi })
    }
}
