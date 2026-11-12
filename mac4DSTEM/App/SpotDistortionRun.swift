//
//  SpotDistortionRun.swift
//  Role: the detector distortion fitted on the matrix's spots (mac4DSTEM#210), held until the user applies it.
//        The fit is DiffractoKit's (`PhaseVectorMatcher.matrixSpotDistortion`); this file turns its result into
//        the values Prepare's ellipse correction and Q pixel scale take, and holds one pending fit per dataset.
//

import Foundation
import DiffractoOrientation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

/// A fitted distortion, in the words and units Prepare shows.
package nonisolated struct SpotDistortionFit: Equatable, Sendable {
    /// Long axis over short axis (1.05 for a pattern stretched by 5 %).
    package var stretchRatio: Double
    /// Direction of the long axis on the detector, degrees in [0, 180) from the column axis (x) towards the row axis (y).
    package var axisDegrees: Double
    /// RMS distance of the measured spots from the fitted ones, detector pixels: with the stretch, and with rotation and scale alone.
    package var residualPixels: Double
    package var residualWithoutStretchPixels: Double
    package var pairCount: Int
    package var positionCount: Int
    /// The ellipse the correction takes: semi-major and semi-minor axis of the ring the matrix's first reflection would draw,
    /// pixels, and the tilt of the semi-major axis from the row axis, degrees (py4DSTEM's a, b, theta, as `applyManualEllipse`).
    package var ellipseA: Double
    package var ellipseB: Double
    package var ellipseThetaDegrees: Double
    /// The reciprocal pixel size that belongs to the corrected pattern, Å⁻¹ per pixel. The ellipse correction scales the
    /// long axis down to the short one, so this is the scale in use divided by the short axis' factor.
    package var invAngstromPerPixel: Double

    /// The kit's fit as Prepare's values.
    /// - Parameters:
    ///   - invAngstromPerPixel: the scale the measured vectors were given in.
    ///   - firstShellInvAngstrom: the matrix's shortest reflection, which sizes a and b (only b/a and theta reach the correction).
    package init?(_ fit: MatrixSpotDistortion, invAngstromPerPixel q: Double, firstShellInvAngstrom: Double, positionCount: Int) {
        let scales = fit.principalScales
        guard q.isFinite, q > 0, firstShellInvAngstrom.isFinite, firstShellInvAngstrom > 0,
              scales.long.isFinite, scales.short.isFinite, scales.short > 0 else { return nil }
        stretchRatio = fit.stretchRatio
        axisDegrees = fit.stretchAxisRad * 180 / .pi
        residualPixels = fit.residualInvAngstrom / q
        residualWithoutStretchPixels = fit.residualWithoutStretchInvAngstrom / q
        pairCount = fit.pairCount
        self.positionCount = positionCount
        ellipseA = firstShellInvAngstrom * scales.long / q
        ellipseB = firstShellInvAngstrom * scales.short / q
        // The kit's axis is measured from x (columns) towards y (rows); py4DSTEM's theta from the row axis.
        var theta = 90 - axisDegrees
        theta = theta.truncatingRemainder(dividingBy: 180)
        if theta < 0 { theta += 180 }
        ellipseThetaDegrees = theta
        self.invAngstromPerPixel = q / scales.short
    }

    /// Below this the pattern is called undistorted and nothing is offered (0.2 %: a tenth of a pixel at 50 px).
    package static let smallestStretchOffered = 1.002

    /// Above this residual the spots do not lie on one stretched lattice and nothing is offered (half a pixel). Seen on a
    /// public steel scan with the matrix away from a zone axis: a "stretch" of 1.060 with 1.27 px left over (2.14 px without).
    package static let largestResidualOfferedPixels = 0.5

    /// Whether the fit is good enough to be applied.
    package var isCredible: Bool { residualPixels.isFinite && residualPixels <= Self.largestResidualOfferedPixels }

    /// "1.051 at 166°": the stretch and the direction of the long axis on the detector, from the column axis towards the
    /// row axis. The one way the fit is named: when it is found and when it is applied (the ellipse row keeps py4DSTEM's
    /// a, b and θ, whose θ is measured from the row axis and so read 104° beside this 166°).
    package func stretchText(locale: Locale = .autoupdatingCurrent) -> String {
        func n(_ value: Double, _ digits: Int) -> String { CalibrationUnitConversion.displayNumber(value, digits: digits, locale: locale) }
        return "\(n(stretchRatio, 4)) at \(n(axisDegrees, 3))°"
    }

    /// One line for the inspector and the status line.
    package func summary(locale: Locale = .autoupdatingCurrent) -> String {
        func n(_ value: Double, _ digits: Int) -> String { CalibrationUnitConversion.displayNumber(value, digits: digits, locale: locale) }
        return "\(stretchText(locale: locale)) · residual \(n(residualPixels, 2))\u{00A0}px (\(n(residualWithoutStretchPixels, 2))\u{00A0}px without)"
    }

    /// The status line once the fit is applied: the same stretch and direction the fit was offered with, and the Q scale set.
    package func appliedLine(locale: Locale = .autoupdatingCurrent) -> String {
        "Distortion applied · stretch \(stretchText(locale: locale)) · Q "
            + CalibrationUnitConversion.displayNumber(invAngstromPerPixel, digits: 4, locale: locale) + "\u{00A0}Å⁻¹/px"
    }
}

/// The pending fit of one dataset window.
@Observable
@MainActor
package final class SpotDistortionRun {
    package nonisolated init() {}

    /// The last fit, until it is applied or the dataset, the ellipse or the disks change.
    package private(set) var pending: SpotDistortionFit?

    /// Why the last fit offered nothing, whole: the status line holds the short form, the note under the button this.
    /// Gone with the next fit and whenever the pending fit is cleared for another reason.
    package private(set) var refusal: String?

    package func record(_ fit: SpotDistortionFit) { pending = fit; refusal = nil }
    package func clear() { pending = nil; refusal = nil }
    package func refuse(_ text: String) { pending = nil; refusal = text }
}
