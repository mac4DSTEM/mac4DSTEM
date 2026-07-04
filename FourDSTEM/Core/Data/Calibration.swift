//
//  Calibration.swift
//  Role: Calibration state attached to one dataset. Mirrors the role of
//        py4DSTEM's Calibration class: measured/fitted origin maps, probe
//        radius, pixel sizes, and (later) elliptical distortion + R–Q rotation.
//
//  Every analysis that works in q-space consumes this — DPC measures CoM
//  shifts relative to the *fitted* per-position origin, Bragg vectors are
//  centered on it, and strain/ACOM inherit it from there.
//
//  Coordinate convention (app-wide): X = detector column (qx index),
//  Y = detector row (qy index) — the same convention as `Aperture`.
//  py4DSTEM's (qx0, qy0) has x as the FIRST (row-ish) axis; translation
//  happens in one place, OriginCalibration, never in consumers.
//

import Foundation

// MARK: - OriginMaps

/// Per-scan-position position of the unscattered (000) beam, in detector px.
/// Row-major [Ry * Rx], same layout as every real-space result image.
struct OriginMaps {
    let width: Int                // Rx
    let height: Int               // Ry

    /// Raw per-pattern measurement (windowed CoM about the brightest disk).
    let measuredX: [Float]
    let measuredY: [Float]

    /// Smooth fit of the measurement (plane/parabola) — what analyses use.
    /// The fit rejects per-pattern noise and fills positions where the
    /// measurement is unreliable (e.g. weak vacuum patterns).
    var fittedX: [Float]
    var fittedY: [Float]

    /// RMS of (measured − fitted), a quick quality figure for the status bar.
    var rmsResidual: Float {
        let n = measuredX.count
        guard n > 0 else { return 0 }
        var acc: Float = 0
        for i in 0..<n {
            let dx = measuredX[i] - fittedX[i]
            let dy = measuredY[i] - fittedY[i]
            acc += dx * dx + dy * dy
        }
        return (acc / Float(n)).squareRoot()
    }

    /// Fitted origins interleaved [x0, y0, x1, y1, ...] — the layout the
    /// CenterOfMass kernel consumes.
    var interleavedFitted: [Float] {
        var out = [Float](repeating: 0, count: fittedX.count * 2)
        for i in 0..<fittedX.count {
            out[2 * i]     = fittedX[i]
            out[2 * i + 1] = fittedY[i]
        }
        return out
    }
}

// MARK: - Calibration

struct Calibration {
    /// Radius of the central (BF) disk in detector px, from get_probe_size.
    var probeRadius: Float?

    /// Center + spread of the (000) beam across the scan.
    var origin: OriginMaps?

    /// Pixel sizes. Units are free-form strings straight from file metadata
    /// ("nm", "A^-1", "pixel"); unit *handling* comes with the q-calibration
    /// workflows later.
    var qPixelSize: Double?
    var qPixelUnits: String?
    var rPixelSize: Double?
    var rPixelUnits: String?

    /// Relative rotation between scan (R) and detector (Q) axes, and whether
    /// the detector axes are transposed, from CoM curl minimization
    /// (RotationCalibration). Applied to CoM fields before DPC/iDPC.
    var rotationRad: Float?
    var transposeQR: Bool?

    /// FUTURE: elliptical distortion (a, b, theta), filled in by its
    /// calibration workflow.

    var hasFittedOrigin: Bool { origin != nil }
    var hasRotation: Bool { rotationRad != nil }

    /// Mean fitted origin — a sensible default detector center elsewhere.
    var meanOrigin: (x: Float, y: Float)? {
        guard let o = origin, !o.fittedX.isEmpty else { return nil }
        let n = Float(o.fittedX.count)
        return (o.fittedX.reduce(0, +) / n, o.fittedY.reduce(0, +) / n)
    }
}
