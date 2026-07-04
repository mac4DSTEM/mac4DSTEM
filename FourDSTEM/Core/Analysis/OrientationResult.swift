//
//  OrientationResult.swift
//  Role: Value types that hold ACOM output. These are the bridge between the
//        Metal template-match kernel (which returns raw {index, score, score2})
//        and the UI maps (IPF, reliability, Euler, phase).
//
//  This is pure data — no compute — and it compiles today. The OrientationMapper
//  that fills it in is Stage 2; this file defines the shape of that result so
//  the UI and exporters can be written against a stable type.
//
//  NCC + reliability follow the EBSD convention:
//    reliability R = 1 − (score_best / score_second).  Low R ⇒ ambiguous match.
//

import Foundation

// MARK: - EulerAngles (Bunge ZXZ)

/// Orientation as Bunge-convention Euler angles (radians).
struct EulerAngles: Equatable, Hashable {
    var phi1: Float    // φ1  (first rotation about Z)
    var Phi:  Float    // Φ   (rotation about X')
    var phi2: Float    // φ2  (rotation about Z'')

    static let zero = EulerAngles(phi1: 0, Phi: 0, phi2: 0)

    /// Degrees, handy for display.
    var degrees: (Float, Float, Float) {
        let k = Float(180.0 / Double.pi)
        return (phi1 * k, Phi * k, phi2 * k)
    }
}

// MARK: - OrientationResult (one scan pixel)

struct OrientationResult: Equatable {
    /// Index into the template library for the best match.
    var templateIndex: Int
    /// Euler angles looked up from the library for `templateIndex`.
    var euler: EulerAngles
    /// Best normalized cross-correlation score.
    var score: Float
    /// Second-best score (for the reliability index).
    var secondScore: Float
    /// Which phase won, when matching multiple phases.
    var phaseID: Int

    /// EBSD-style reliability: 1 − (best / second). Clamped to [0, 1].
    var reliability: Float {
        guard score > 0 else { return 0 }
        let r = 1 - (secondScore / score)
        return max(0, min(1, r))
    }

    static let empty = OrientationResult(templateIndex: -1,
                                         euler: .zero,
                                         score: 0, secondScore: 0,
                                         phaseID: -1)
}

// MARK: - OrientationMap (the whole scan)

/// Row-major [Ry × Rx] grid of per-pixel results, plus a little metadata.
struct OrientationMap {
    let width: Int      // Rx
    let height: Int     // Ry
    var results: [OrientationResult]   // length == width * height

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.results = Array(repeating: .empty, count: width * height)
    }

    subscript(x: Int, y: Int) -> OrientationResult {
        get { results[y * width + x] }
        set { results[y * width + x] = newValue }
    }

    /// Reliability as a renderable scalar image.
    var reliabilityImage: FloatImage {
        FloatImage(width: width, height: height, pixels: results.map { $0.reliability })
    }

    /// Best-match NCC score as a renderable scalar image.
    var scoreImage: FloatImage {
        FloatImage(width: width, height: height, pixels: results.map { $0.score })
    }
}
