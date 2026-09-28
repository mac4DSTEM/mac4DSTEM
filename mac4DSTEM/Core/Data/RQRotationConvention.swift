//
//  RQRotationConvention.swift
//  The R–Q rotation's sign at every boundary a user reads or a file carries
//  (ADR 040 decision 2). In `data` so every harness group that shows or
//  writes the angle composes it.
//

import Foundation

/// The one place the R–Q rotation changes sign (ADR 040 decision 2, Gate D
/// `docs/archive/v4/rq-sign-gateD-2026-09-28.md`).
///
/// DEVIATION (convention, not physics): this app reads a file's axes as
/// (Ry, Rx, Qy, Qx) (`DatasetDescriptor.swift`), py4DSTEM as (Rx, Ry, Qx, Qy).
/// Both the scan pair and the detector pair are swapped, and a reflection of
/// both spaces conjugates R(θ) to R(−θ). So the angle this app computes and
/// uses internally (DPC, strain frame, ACOM, ptychography, parallax) is the
/// NEGATIVE of py4DSTEM's on the same file; the transpose flag is identical.
/// Internals keep the app's angle, which is consistent with its own axes.
/// Everything a user reads or a file carries uses py4DSTEM's
/// (`QR_rotation`), converted here and nowhere else. Measured: the real cube
/// `Particle_1_Stack_1…bin8.h5` gives py4DSTEM +80.0° T and app −80.1° T
/// (`docs/archive/v3/rq-frame-class-2026-09-23.md`).
package enum RQRotationConvention {
    /// The value written beside `QR_rotation` in files this app writes, so a
    /// reader can tell them from sidecars written before 2026-09-28 in the
    /// app's own sign.
    package static let marker = "py4DSTEM"

    /// py4DSTEM's angle (radians) for the app's internal one.
    package nonisolated static func py4DSTEM(fromApp appRad: Double) -> Double { -appRad }

    /// The app's internal angle for py4DSTEM's (radians).
    package nonisolated static func app(fromPy4DSTEM fileRad: Double) -> Double { -fileRad }

    /// Degrees in py4DSTEM's convention, for display.
    package nonisolated static func displayDegrees(fromApp appRad: Float) -> Double {
        py4DSTEM(fromApp: Double(appRad)) * 180 / .pi
    }
}
